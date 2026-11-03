"""앱의 실제 API 코드로 실제 BE 서버를 부르는 E2E를 돌린다.

    python scripts/run_app_server_e2e.py --admin-database-url postgresql://.../postgres

하는 일
1. 빈 DB를 새로 만들고 `alembic upgrade head`를 적용한다.
2. 이 실행에서만 쓰는 RSA 키로 구글 ID 토큰을 서명하고, 공개키를 로컬 JWKS 주소로 연다.
3. 이 프로세스 안에서 BE(uvicorn)와 카드 생성 worker를 띄운다. worker의 생성 함수만
   합성 카드 12장을 돌려주는 함수로 바꾼다. 모델은 부르지 않는다.
4. `app/`에서 `flutter test e2e/server_journey_test.dart`를 실행한다. 앱 쪽 테스트는
   AuthApi, ProfileApi, ServerCardApi, ServerVisitApi, ReportApi와 ApiClient를 그대로 쓰고
   HTTP만 실제로 보낸다.
5. 서버와 worker를 멈추고 DB를 지운다(`--keep-database`면 남긴다).

대신하는 것: 구글 로그인(로컬 서명 키), 카드 생성 모델(합성 카드). 녹음 업로드와 사진은
S3가 필요해 이 E2E에 넣지 않았다. 녹음 이후 흐름은 `tests/test_second_visit_flow.py`가
API와 worker 수준에서 본다. 값은 모두 합성이다.
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
# `python scripts/run_app_server_e2e.py`로 실행해도 `app` 패키지를 찾게 한다.
sys.path.insert(0, str(BACKEND_DIR))
CLIENT_ID = "e2e-client-id.apps.googleusercontent.com"
KEY_ID = "e2e-key-1"


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
    """카드 생성 모델 대신 합성 카드 12장을 돌려준다. 첫 카드는 첫 이야기를 근거로 둔다."""
    from app.schemas.card_generation import CardGenerationResult, GeneratedCard, GeneratedTopic

    facts = request.context.life_facts
    cards = []
    for position in range(1, 13):
        evidence = [{"factId": str(facts[0].fact_id)}] if facts and position == 1 else []
        cards.append(
            GeneratedCard(
                position=position,
                topic=GeneratedTopic(
                    title=f"E2E 합성 주제 {position}", description="E2E 합성 주제 설명", evidence=evidence
                ),
                card_title=f"E2E 합성 카드 {position}",
                description="E2E 합성 카드 설명",
                primary_question="좋아하시던 꽃이 있으세요?",
                follow_up_questions=["어떤 색이었나요?", "어디서 보셨나요?", "누구와 보셨나요?"],
                evidence_source="lifeFact" if evidence else "none",
                evidence=evidence,
            )
        )
    return CardGenerationResult(
        model=request.model, prompt_version=request.prompt_version, cards=cards, log={"source": "app-server-e2e"}
    )


def _run_card_worker(settings, stop: threading.Event) -> None:
    from app.workers.card_generation import create_worker

    worker = create_worker(settings, _synthetic_generate)

    async def loop():
        while not stop.is_set():
            if not await worker.run_once():
                await asyncio.sleep(0.2)

    # psycopg 비동기 연결은 Windows 기본 루프(ProactorEventLoop)에서 동작하지 않는다.
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
    args = parser.parse_args(argv)
    if not args.admin_database_url:
        print("ADMIN_DATABASE_URL_MISSING: --admin-database-url 또는 SAEROK_TEST_DATABASE_URL이 필요합니다")
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
    # 이 실행에서만 쓰는 값이다. 실제 키나 비밀이 아니다. ML 키는 4-1이 비어 있지 않은지만 보고,
    # 생성은 합성 함수가 하므로 모델로 나가지 않는다.
    os.environ.update(
        {
            "SAEROK_ENVIRONMENT": "test",
            # Alembic(SQLAlchemy) 형식. 앱은 연결할 때 driver 표기를 뗀다.
            "SAEROK_DATABASE_URL": database_url.replace("postgresql://", "postgresql+psycopg://", 1),
            "SAEROK_GOOGLE_CLIENT_IDS": CLIENT_ID,
            "SAEROK_GOOGLE_JWKS_URL": jwks_url,
            "SAEROK_SESSION_SECRET": secrets.token_urlsafe(48),
            "SAEROK_ML_API_KEY": "e2e-synthetic-generator-no-model-call",
        }
    )
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

        settings = Settings(_env_file=None)
        server = uvicorn.Server(uvicorn.Config(create_app(), host="127.0.0.1", port=port, log_level="warning"))
        threading.Thread(
            target=lambda: asyncio.run(server.serve(), loop_factory=asyncio.SelectorEventLoop), daemon=True
        ).start()
        threading.Thread(target=_run_card_worker, args=(settings, stop), daemon=True).start()
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

        env = {
            **os.environ,
            "SAEROK_E2E_BASE_URL": base_url,
            "SAEROK_E2E_ID_TOKEN": id_token(f"e2e-{uuid.uuid4()}"),
        }
        print(f"E2E_SERVER {base_url} database={database}")
        result = subprocess.run(
            [args.flutter, "test", "e2e/server_journey_test.dart", "--reporter", "expanded"], cwd=APP_DIR, env=env
        )
        code = result.returncode
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
