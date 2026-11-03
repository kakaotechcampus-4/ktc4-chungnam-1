"""앱의 실제 API 코드로 실제 BE 서버를 부르는 E2E를 돌린다.

    python scripts/run_app_server_e2e.py --admin-database-url postgresql://.../postgres

하는 일
1. 빈 DB를 새로 만들고 `alembic upgrade head`를 적용한다.
2. 이 실행에서만 쓰는 RSA 키로 구글 ID 토큰을 서명하고, 공개키를 로컬 JWKS 주소로 연다.
3. 이 프로세스 안에서 BE(uvicorn), 카드 생성 worker, 음성 분석 worker를 띄운다.
   바꾸는 것은 서버 밖으로 나가는 경계뿐이다. 카드 생성 함수는 합성 카드 12장을, 녹음 저장소는
   메모리를, STT 서버 호출은 화자 두 명의 합성 전사를, 리포트 생성 함수는 합성 리포트와 제안을
   돌려준다. 모델과 S3로는 요청이 나가지 않는다.
4. `app/`에서 `flutter test e2e/server_journey_test.dart`를 실행한다. 앱 쪽 테스트는
   AuthApi, ProfileApi, ServerCardApi, ServerVisitApi, ReportApi와 ApiClient를 그대로 쓰고
   HTTP만 실제로 보낸다.
5. 서버와 worker를 멈추고 DB를 지운다(`--keep-database`면 남긴다).

대신하는 것: 구글 로그인(로컬 서명 키), 카드 생성 모델, S3, STT, 리포트 모델. 사진 업로드는
넣지 않았다. 값은 모두 합성이다.

실제 모델과 STT로 돌리기(선택)
    --secrets-env-file <파일>   이 파일에서 SAEROK_ML_API_KEY 한 줄만 읽는다. 값은 출력하지 않는다.
    --card-model real           카드를 실제 모델로 만든다(app.workers.card_generation.card_generator).
    --report-model real         리포트와 변경 제안을 실제 모델로 만든다.
    --stt real --stt-url <주소> 녹음을 실제 S3(SAEROK_SPEECH_AUDIO_S3_* 와 AWS 자격 증명 필요)에 올리고
                                실제 STT 서버가 내려받아 전사한다.
화면까지(선택)
    --ui --device <기기>        `app/integration_test/server_app_journey_test.dart`를 에뮬레이터나 기기에서
                                돌린다. 계정과 어르신 정보는 API로 미리 만들고, 앱은 로그인 화면부터 실제
                                화면을 눌러 간다. 에뮬레이터는 호스트를 10.0.2.2로 부른다.
    --audio-file <WAV>          면회 녹음으로 올릴 합성 음성. 없으면 0.1초 무음이다.

실제 모델 모드에서는 생성된 글을 미리 알 수 없으므로 앱 쪽 테스트는 구조만 확인한다. 승인한 이야기가
다음 카드 생성 자료에 출처 `visit`으로 들어갔는지는 이 스크립트가 서버가 생성 함수에 넘긴 요청을
기록해 두고 직접 확인한다. 실제 모드에서도 서버에 넣는 자료는 모두 합성이다.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import secrets
import shutil
import socket
import subprocess
import sys
import threading
import time
import uuid
from datetime import UTC, datetime, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.request import urlopen

BACKEND_DIR = Path(__file__).resolve().parents[1]
REPO_DIR = BACKEND_DIR.parent
APP_DIR = REPO_DIR / "app"
# `python scripts/run_app_server_e2e.py`로 실행해도 `app` 패키지와 같은 저장소의 `ai` 패키지를 찾게 한다.
sys.path[:0] = [str(BACKEND_DIR), str(REPO_DIR / "ai")]
CLIENT_ID = "e2e-client-id.apps.googleusercontent.com"
KEY_ID = "e2e-key-1"
# 앱 쪽 테스트가 이야기 제안을 고쳐 승인할 때 쓰는 제목. 다음 카드 생성 요청에서 이 제목을 찾는다.
APPROVED_TITLE = "E2E 고쳐서 승인한 이야기"
# 합성 카드 생성 함수는 이 제목의 이야기가 있으면 실패한다. 앱 쪽 테스트가 실패 뒤 다시 요청하는 경로를 본다.
FAIL_CARDS_TITLE = "E2E 생성 실패 유도"
RETRY_ROUTE = "/api/v1/speech-analyses/{analysis_id}/retry"
SECRET_NAMES = {"SAEROK_ML_API_KEY"}


def _serve_file(path: str) -> tuple[ThreadingHTTPServer, int]:
    """합성 음성 파일 하나를 로컬 HTTP로 연다. 에뮬레이터는 10.0.2.2로 받아 간다."""
    body = Path(path).read_bytes()

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802 - http.server 규칙
            self.send_response(200)
            self.send_header("Content-Type", "audio/wav")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, server.server_address[1]


def _post(url: str, body: dict, token: str | None = None, method: str = "POST") -> dict:
    from urllib.request import Request

    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = Request(url, data=json.dumps(body).encode(), headers=headers, method=method)
    with urlopen(request, timeout=15) as response:
        return json.loads(response.read() or b"{}")


def _seed_account(base_url: str, id_token: str, name: str) -> None:
    """화면 여정 전에 계정, 어르신 정보, 이야기 하나를 API로 만든다. 모두 합성이다."""
    first = _post(f"{base_url}/auth/google", {"idToken": id_token})
    consents = {key: True for key in first["requiredConsents"]} | {key: False for key in first["optionalConsents"]}
    session = _post(
        f"{base_url}/auth/consent",
        {"registrationToken": first["registrationToken"], "consentVersion": first["consentVersion"], "consents": consents},
    )
    token = session["accessToken"]
    profile = _post(
        f"{base_url}/api/v1/profiles",
        {"name": name, "gender": "female", "birthDate": "1943-03-12", "condition": {"stage": "unknown", "symptomNote": None}},
        token,
    )
    profile_id = profile["profileId"]
    _post(f"{base_url}/api/v1/profiles/{profile_id}", {"hobby": "합성 정원 가꾸기"}, token, method="PATCH")
    _post(
        f"{base_url}/api/v1/profiles/{profile_id}/life-facts",
        {"storyCategory": "work", "title": "합성 수선집", "content": "합성 수선집에 단골손님이 많았어요.", "imageNumber": 3},
        token,
    )
    # 앱은 첫 카드 생성 요청이 있어야 등록을 마친 분으로 본다(`setupStatus: completed`). 온보딩의 마지막
    # 단계와 같이 첫 묶음을 요청하고 다 될 때까지 기다린다.
    _post(f"{base_url}/api/v1/profiles/{profile_id}/card-generations", {}, token)
    deadline = time.monotonic() + 600
    while time.monotonic() < deadline:
        from urllib.request import Request

        request = Request(
            f"{base_url}/api/v1/profiles/{profile_id}/card-generations/status",
            headers={"Authorization": f"Bearer {token}"},
        )
        with urlopen(request, timeout=15) as response:
            status = json.loads(response.read())["status"]
        if status == "ready":
            break
        if status != "running":
            raise RuntimeError(f"SEED_CARD_GENERATION_{status.upper()}")
        time.sleep(1)
    else:
        raise RuntimeError("SEED_CARD_GENERATION_TIMEOUT")
    # 로그인은 앱 화면에서 다시 한다. 여기서 받은 세션은 버린다.
    _post(f"{base_url}/auth/logout", {}, token)


def _load_secrets(path: str) -> list[str]:
    """지정한 파일에서 허용한 이름의 값만 환경변수로 옮긴다. 값은 출력하지 않는다."""
    loaded = []
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        name, sep, value = line.partition("=")
        name, value = name.strip(), value.strip().strip('"').strip("'")
        if sep and name in SECRET_NAMES and value:
            os.environ[name] = value
            loaded.append(name)
    return loaded


def _free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def _jwks_server(public_jwk: dict) -> tuple[ThreadingHTTPServer, str]:
    body = json.dumps({"keys": [public_jwk]}).encode()

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802 - http.server 규칙
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, f"http://127.0.0.1:{server.server_address[1]}/jwks"


def _signing_material():
    import jwt
    from cryptography.hazmat.primitives.asymmetric import rsa

    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    jwk = json.loads(jwt.algorithms.RSAAlgorithm.to_jwk(key.public_key()))
    jwk.update({"kid": KEY_ID, "alg": "RS256", "use": "sig"})

    def id_token(subject: str) -> str:
        now = datetime.now(UTC)
        payload = {
            "sub": subject,
            "aud": CLIENT_ID,
            "iss": "https://accounts.google.com",
            "iat": now,
            "exp": now + timedelta(minutes=30),
        }
        return jwt.encode(payload, key, algorithm="RS256", headers={"kid": KEY_ID})

    return jwk, id_token


def _synthetic_generate(request):
    """카드 생성 모델 대신 합성 카드 12장을 돌려준다.

    서버가 넘긴 이야기 하나마다 앞에서부터 카드 한 장을 만들고, 카드 제목과 설명에 그 이야기의
    제목과 출처(`caregiver`, `visit`)를 적는다. 승인한 이야기가 다음 카드 생성 자료에 들어갔는지를
    앱 쪽 테스트가 카드에서 확인할 수 있게 하려는 것이다.
    """
    from app.schemas.card_generation import CardGenerationResult, GeneratedCard, GeneratedTopic
    from app.services.card_sets import CardGenerationError

    facts = request.context.life_facts
    if any(fact.title == FAIL_CARDS_TITLE for fact in facts):
        raise CardGenerationError("E2E_SYNTHETIC_FAILURE", "앱 쪽 테스트가 실패 경로를 보려고 넣은 이야기")
    cards = []
    for position in range(1, 13):
        fact = facts[position - 1] if position <= len(facts) else None
        evidence = [{"factId": str(fact.fact_id)}] if fact else []
        cards.append(
            GeneratedCard(
                position=position,
                topic=GeneratedTopic(
                    title=f"E2E 합성 주제 {position}", description="E2E 합성 주제 설명", evidence=evidence
                ),
                card_title=f"E2E 이야기 카드: {fact.title}" if fact else f"E2E 합성 카드 {position}",
                description=f"E2E 합성 카드 설명(이야기 출처: {fact.source})" if fact else "E2E 합성 카드 설명",
                primary_question="좋아하시던 꽃이 있으세요?",
                follow_up_questions=["어떤 색이었나요?", "어디서 보셨나요?", "누구와 보셨나요?"],
                evidence_source="lifeFact" if evidence else "none",
                evidence=evidence,
            )
        )
    return CardGenerationResult(
        model=request.model, prompt_version=request.prompt_version, cards=cards, log={"source": "app-server-e2e"}
    )


def _run_card_worker(settings, generate, stop: threading.Event) -> None:
    from app.workers.card_generation import create_worker

    worker = create_worker(settings, generate)

    async def loop():
        while not stop.is_set():
            if not await worker.run_once():
                await asyncio.sleep(0.2)

    # psycopg 비동기 연결은 Windows 기본 루프(ProactorEventLoop)에서 동작하지 않는다.
    asyncio.run(loop(), loop_factory=asyncio.SelectorEventLoop)


class _MemoryImageStorage:
    """S3 대신 메모리에 사진을 둔다."""

    def __init__(self) -> None:
        self.objects: dict[str, bytes] = {}

    def object_key(self, *, photo_id, image) -> str:
        return f"e2e/{photo_id}.{image.extension}"

    async def upload(self, *, object_key: str, file, image) -> None:
        file.seek(0)
        self.objects[object_key] = file.read()

    async def create_download(self, *, object_key: str):
        from app.services.image_storage import ImageDownload

        if object_key not in self.objects:
            raise RuntimeError("E2E_IMAGE_NOT_UPLOADED")
        return ImageDownload(
            url=f"https://e2e-image.invalid/{object_key}", expires_at=datetime.now(UTC) + timedelta(minutes=15)
        )

    async def delete(self, *, object_key: str) -> None:
        self.objects.pop(object_key, None)


class _TrackedAudioStorage:
    """다른 저장소(실제 S3)를 감싸 올린 녹음과 지운 녹음을 센다."""

    def __init__(self, inner) -> None:
        self._inner = inner
        self.objects: dict[str, bytes] = {}
        self.deleted: list[str] = []

    async def upload(self, *, object_key: str, file) -> None:
        await self._inner.upload(object_key=object_key, file=file)
        self.objects[object_key] = b""

    async def create_download(self, *, object_key: str, expires_at: datetime):
        return await self._inner.create_download(object_key=object_key, expires_at=expires_at)

    async def delete(self, *, object_key: str) -> None:
        await self._inner.delete(object_key=object_key)
        self.objects.pop(object_key, None)
        self.deleted.append(object_key)


class _MemoryAudioStorage:
    """S3 대신 메모리에 녹음을 둔다. 분석이 끝나면 서버가 지우는 것도 그대로 받는다."""

    def __init__(self) -> None:
        self.objects: dict[str, bytes] = {}
        self.deleted: list[str] = []

    async def upload(self, *, object_key: str, file) -> None:
        file.seek(0)
        self.objects[object_key] = file.read()

    async def create_download(self, *, object_key: str, expires_at: datetime):
        from app.services.audio_storage import AudioDownload

        if object_key not in self.objects:
            raise RuntimeError("E2E_AUDIO_NOT_UPLOADED")
        return AudioDownload(url="https://e2e-audio.invalid/synthetic.wav", expires_at=expires_at)

    async def delete(self, *, object_key: str) -> None:
        self.objects.pop(object_key, None)
        self.deleted.append(object_key)


def _synthetic_transcript(request):
    """STT 서버(8-1) 대신 보호자와 어르신 두 화자의 합성 전사를 돌려준다."""
    import httpx

    analysis_id = json.loads(request.content)["analysisId"]
    lines = [
        ("SPEAKER_00", "어머니, 수선집 하실 때 단골손님이 많으셨다면서요?"),
        ("SPEAKER_01", "그럼, 양복 맞추러 오는 사람이 줄을 섰지."),
        ("SPEAKER_00", "제일 기억에 남는 손님은 누구셨어요?"),
        ("SPEAKER_01", "한복을 지어 달라던 새댁이 있었어. 고름을 몇 번이나 다시 달았지."),
    ]
    segments = [
        {"startMs": i * 4000, "endMs": i * 4000 + 3500, "speakerLabel": speaker, "text": text, "words": []}
        for i, (speaker, text) in enumerate(lines)
    ]
    body = {
        "schemaVersion": 1,
        "analysisId": analysis_id,
        "language": "ko",
        "durationMs": len(lines) * 4000,
        "text": " ".join(text for _, text in lines),
        "segments": segments,
    }
    return httpx.Response(200, json=body)


def _synthetic_report(request, deadline):
    """리포트 모델 대신, 평가에서 쓴 카드 하나에 대한 합성 리포트와 변경 제안을 돌려준다."""
    from app.services.visit_report_generator import parse_result

    used = next(card for card in request.cards if card.reaction is not None)
    data = {
        "schemaVersion": 1,
        "analysisId": request.analysis_id,
        "model": "e2e-synthetic-report",
        "promptVersion": "e2e-report",
        "title": "E2E 합성 리포트",
        "body": "수선집 단골손님과 한복 이야기를 나눈 합성 리포트입니다.",
        "cardSummaries": [{"cardId": str(used.card_id), "summary": "E2E 합성 카드 요약"}],
        "lifeFactProposals": [
            {"title": "E2E 합성 제안 이야기", "content": "한복 고름을 여러 번 다시 다셨어요.", "reason": "E2E 합성 이유"}
        ],
        "topicProposals": [{"cardId": str(used.card_id), "suggestedAction": "more", "reason": "E2E 합성 이유"}],
    }
    return parse_result(data, request)


def _run_speech_worker(database_url: str, storage, ai_server, generate_report, stop: threading.Event) -> None:
    from app.core.database import connect
    from app.services.speech_analysis_jobs import PostgresSpeechAnalysisJobRepository
    from app.services.speech_analysis_pipeline import create_speech_worker
    from app.services.visit_report_generator import VisitReportGenerator

    worker = create_speech_worker(
        jobs_for=lambda connection: PostgresSpeechAnalysisJobRepository(connection, lease_seconds=900),
        audio_storage=storage,
        ai_server=ai_server,
        open_connection=lambda: connect(database_url),
        lease_seconds=900,
        report_generator=VisitReportGenerator(generate=generate_report, time_limit_seconds=600),
    )

    async def loop():
        while not stop.is_set():
            if not await worker.run_once():
                await asyncio.sleep(0.2)

    asyncio.run(loop(), loop_factory=asyncio.SelectorEventLoop)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--admin-database-url",
        default=os.environ.get("SAEROK_TEST_DATABASE_URL", ""),
        help="DB를 만들고 지울 수 있는 계정의 주소. 기본값은 SAEROK_TEST_DATABASE_URL",
    )
    parser.add_argument("--flutter", default=shutil.which("flutter") or "flutter")
    parser.add_argument("--keep-database", action="store_true")
    parser.add_argument("--secrets-env-file", help="SAEROK_ML_API_KEY 한 줄만 읽을 파일")
    parser.add_argument("--card-model", choices=["synthetic", "real"], default="synthetic")
    parser.add_argument("--report-model", choices=["synthetic", "real"], default="synthetic")
    parser.add_argument("--stt", choices=["synthetic", "real"], default="synthetic")
    parser.add_argument("--stt-url", help="--stt real일 때 STT 서버 주소(예: SSH 터널 http://127.0.0.1:18001)")
    parser.add_argument("--ui", action="store_true", help="화면 여정을 에뮬레이터나 기기에서 돌린다")
    parser.add_argument("--device", default="emulator-5554")
    parser.add_argument("--audio-file", help="면회 녹음으로 올릴 합성 음성 WAV")
    args = parser.parse_args(argv)
    if not args.admin_database_url:
        print("ADMIN_DATABASE_URL_MISSING: --admin-database-url 또는 SAEROK_TEST_DATABASE_URL이 필요합니다")
        return 2
    if args.secrets_env_file:
        print(f"SECRETS_LOADED {','.join(_load_secrets(args.secrets_env_file)) or 'none'}")
    real_models = args.card_model == "real" or args.report_model == "real"
    if real_models and not os.environ.get("SAEROK_ML_API_KEY"):
        print("ML_API_KEY_MISSING: 실제 모델 모드에는 SAEROK_ML_API_KEY가 필요합니다(--secrets-env-file)")
        return 2
    if args.stt == "real" and not (args.stt_url and os.environ.get("SAEROK_SPEECH_AUDIO_S3_BUCKET")):
        print("REAL_STT_NOT_CONFIGURED: --stt-url과 SAEROK_SPEECH_AUDIO_S3_BUCKET, AWS 자격 증명이 필요합니다")
        return 2

    import psycopg

    admin = args.admin_database_url.replace("postgresql+psycopg://", "postgresql://")
    database = f"saerok_e2e_{uuid.uuid4().hex[:10]}"
    database_url = f"{admin.rsplit('/', 1)[0]}/{database}"
    with psycopg.connect(admin, autocommit=True) as connection:
        connection.execute(f'CREATE DATABASE "{database}"')

    jwk, id_token = _signing_material()
    jwks, jwks_url = _jwks_server(jwk)
    port = _free_port()
    # 이 실행에서만 쓰는 값이다. 합성 모드의 ML 키 자리 값은 4-1이 비어 있지 않은지만 보고,
    # 생성은 합성 함수가 하므로 모델로 나가지 않는다.
    os.environ.update(
        {
            "SAEROK_ENVIRONMENT": "test",
            # Alembic(SQLAlchemy) 형식. 앱은 연결할 때 driver 표기를 뗀다.
            "SAEROK_DATABASE_URL": database_url.replace("postgresql://", "postgresql+psycopg://", 1),
            "SAEROK_GOOGLE_CLIENT_IDS": CLIENT_ID,
            "SAEROK_GOOGLE_JWKS_URL": jwks_url,
            "SAEROK_SESSION_SECRET": secrets.token_urlsafe(48),
        }
    )
    if not real_models:
        os.environ.setdefault("SAEROK_ML_API_KEY", "e2e-synthetic-generator-no-model-call")
    stop = threading.Event()
    server = None
    code = 1
    try:
        # 출력 인코딩이 OS마다 달라 바이트로 받고 실패할 때만 풀어 쓴다.
        migrate = subprocess.run([sys.executable, "-m", "alembic", "upgrade", "head"], cwd=BACKEND_DIR, capture_output=True)
        if migrate.returncode != 0:
            print("MIGRATION_FAILED")
            print(migrate.stderr.decode("utf-8", errors="replace")[-2000:])
            return 1

        import uvicorn

        from app.core.config import Settings
        from app.main import create_app

        import httpx

        from app.api.deps import get_speech_audio_storage
        from app.clients.ai_server import AiServerClient

        settings = Settings(_env_file=None)
        if args.stt == "real":
            from app.services.audio_storage import S3AudioStorage

            storage = _TrackedAudioStorage(
                S3AudioStorage(
                    bucket=settings.speech_audio_s3_bucket,
                    region=settings.speech_audio_s3_region,
                    presigned_ttl_seconds=settings.speech_audio_presigned_ttl_seconds,
                    server_side_encryption=settings.speech_audio_s3_encryption,
                )
            )
            ai_server = AiServerClient(base_url=args.stt_url, timeout_seconds=settings.ai_server_timeout_seconds)
        else:
            storage = _MemoryAudioStorage()
            ai_server = AiServerClient(
                base_url="http://stt.e2e.invalid", timeout_seconds=5, transport=httpx.MockTransport(_synthetic_transcript)
            )
        if args.card_model == "real":
            from app.workers.card_generation import card_generator

            base_generate = card_generator(settings)
        else:
            base_generate = _synthetic_generate
        card_requests = []

        def generate_cards(request):
            card_requests.append(request)
            return base_generate(request)

        from app.api.deps import get_image_storage

        application = create_app()
        retry_supported = RETRY_ROUTE in application.openapi()["paths"]
        # 6-5가 있는 서버에서는 첫 리포트 생성을 일부러 실패시켜 다시 요청하는 경로를 본다. 6-5는 남은
        # 전사로 리포트만 다시 만든다.
        fail_first_report = args.report_model == "synthetic" and retry_supported
        if args.report_model == "real":
            from app.workers.speech_analysis import report_generator

            generate_report = report_generator(settings)
        else:
            report_calls = []

            def generate_report(request, deadline):
                report_calls.append(request.analysis_id)
                if fail_first_report and len(report_calls) == 1:
                    from app.services.visit_report_generator import parse_result

                    return parse_result({"schemaVersion": 1, "analysisId": request.analysis_id}, request)
                return _synthetic_report(request, deadline)

        print(
            f"E2E_MODES card={args.card_model} report={args.report_model} stt={args.stt} "
            f"report_retry={'checked' if fail_first_report else 'not-checked'}"
        )
        images = _MemoryImageStorage()
        application.dependency_overrides[get_speech_audio_storage] = lambda: storage
        application.dependency_overrides[get_image_storage] = lambda: images
        server = uvicorn.Server(uvicorn.Config(application, host="127.0.0.1", port=port, log_level="warning"))
        threading.Thread(
            target=lambda: asyncio.run(server.serve(), loop_factory=asyncio.SelectorEventLoop), daemon=True
        ).start()
        threading.Thread(target=_run_card_worker, args=(settings, generate_cards, stop), daemon=True).start()
        threading.Thread(
            target=_run_speech_worker, args=(database_url, storage, ai_server, generate_report, stop), daemon=True
        ).start()
        base_url = f"http://127.0.0.1:{port}"
        for _ in range(50):
            try:
                with urlopen(f"{base_url}/health/ready", timeout=1) as response:
                    if response.status == 200:
                        break
            except OSError:
                time.sleep(0.1)
        else:
            print("SERVER_NOT_READY")
            return 1

        report_file = Path(os.environ.get("TEMP", "/tmp")) / f"saerok_e2e_{uuid.uuid4().hex[:8]}.json"
        token = id_token(f"e2e-{uuid.uuid4()}")
        models = "real" if real_models else "synthetic"
        env = {
            **{k: v for k, v in os.environ.items() if k not in SECRET_NAMES},
            "SAEROK_E2E_BASE_URL": base_url,
            "SAEROK_E2E_ID_TOKEN": token,
            "SAEROK_E2E_MODELS": models,
            "SAEROK_E2E_REPORT_FILE": str(report_file),
            "SAEROK_E2E_EXPECT_REPORT_RETRY": "1" if fail_first_report else "0",
            "SAEROK_E2E_CARD_MODEL": args.card_model,
        }
        if args.audio_file:
            env["SAEROK_E2E_AUDIO_FILE"] = str(Path(args.audio_file).resolve())
        print(f"E2E_SERVER {base_url} database={database}")
        if args.ui:
            profile_name = "E2E 화면 어르신"
            _seed_account(base_url, token, profile_name)
            defines = {
                "SAEROK_API_BASE_URL": f"http://10.0.2.2:{port}",
                "SAEROK_E2E_ID_TOKEN": token,
                "SAEROK_E2E_PROFILE_NAME": profile_name,
                "SAEROK_E2E_MODELS": models,
                "SAEROK_E2E_EXPECT_REPORT_RETRY": "1" if fail_first_report else "0",
            }
            if args.audio_file:
                audio_server, audio_port = _serve_file(args.audio_file)
                defines["SAEROK_E2E_AUDIO_URL"] = f"http://10.0.2.2:{audio_port}/audio.wav"
            command = [args.flutter, "test", "integration_test/server_app_journey_test.dart", "-d", args.device]
            command += [f"--dart-define={name}={value}" for name, value in defines.items()]
            result = subprocess.run(command, cwd=APP_DIR, env=env, capture_output=True)
            output = result.stdout.decode("utf-8", errors="replace")
            print(output[-6000:])
            print(result.stderr.decode("utf-8", errors="replace")[-3000:])
            marker = next((line for line in output.splitlines() if "E2E_UI_OUTCOME " in line), "")
            if marker:
                report_file.write_text(marker.split("E2E_UI_OUTCOME ", 1)[1], encoding="utf-8")
        else:
            result = subprocess.run(
                [args.flutter, "test", "e2e/server_journey_test.dart", "--reporter", "expanded"], cwd=APP_DIR, env=env
            )
        code = result.returncode
        if code == 0 and storage.objects:
            print(f"E2E_AUDIO_NOT_DELETED count={len(storage.objects)}")
            code = 1
        outcome = json.loads(report_file.read_text(encoding="utf-8")) if report_file.exists() else {}
        report_file.unlink(missing_ok=True)
        if code == 0:
            approved_in_context = any(
                fact.title == APPROVED_TITLE and fact.source == "visit"
                for request in card_requests
                for fact in request.context.life_facts
            )
            print(f"E2E_OUTCOME {json.dumps(outcome, ensure_ascii=False)} card_requests={len(card_requests)}")
            if outcome.get("approved") and not approved_in_context:
                print("E2E_APPROVED_STORY_NOT_IN_NEXT_CARD_CONTEXT")
                code = 1
            elif outcome.get("approved"):
                print("E2E_APPROVED_STORY_IN_NEXT_CARD_CONTEXT source=visit")
            elif not real_models:
                print("E2E_APPROVAL_NOT_EXERCISED")
                code = 1
            else:
                print("E2E_APPROVAL_NOT_EXERCISED: 실제 모델이 이야기 제안을 내지 않았다")
        print("E2E_PASSED" if code == 0 else f"E2E_FAILED rc={code}")
        return code
    finally:
        stop.set()
        if server is not None:
            server.should_exit = True
        jwks.shutdown()
        time.sleep(0.5)
        if args.keep_database:
            print(f"E2E_DATABASE_KEPT {database}")
        else:
            with psycopg.connect(admin, autocommit=True) as connection:
                connection.execute(
                    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = %s AND pid <> pg_backend_pid()",
                    (database,),
                )
                connection.execute(f'DROP DATABASE IF EXISTS "{database}"')


if __name__ == "__main__":
    raise SystemExit(main())
