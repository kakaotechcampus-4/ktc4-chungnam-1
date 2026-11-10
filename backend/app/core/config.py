from functools import lru_cache
from typing import Annotated, Literal

from pydantic import Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict

# 구글이 ID 토큰의 `iss` 에 넣는 두 가지 값. 둘 다 같은 발급자를 뜻한다.
GOOGLE_ISSUERS = frozenset({"accounts.google.com", "https://accounts.google.com"})
GOOGLE_JWKS_URL = "https://www.googleapis.com/oauth2/v3/certs"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        env_prefix="SAEROK_",
        extra="ignore",
    )

    environment: Literal["development", "test", "production"] = "development"
    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"] = (
        "INFO"
    )
    service_name: str = "saerok-backend"
    service_version: str = "0.1.0"
    ai_server_url: str = "http://127.0.0.1:8001"
    ai_server_timeout_seconds: float = 600.0
    ai_server_backup_url: str | None = None
    ai_server_failover_connect_timeout_seconds: float = Field(default=5.0, gt=0, le=30)
    database_url: str | None = None

    # 면회 음성은 비공개 S3 버킷에 임시 저장한다. 버킷과 DB가 모두 설정돼야
    # 공개 업로드 API가 활성화된다.
    speech_audio_s3_bucket: str = ""
    speech_audio_s3_region: str = "ap-northeast-2"
    speech_audio_s3_prefix: str = "temporary/speech"
    speech_audio_s3_encryption: Literal["AES256", "aws:kms"] = "AES256"
    speech_audio_presigned_ttl_seconds: int = Field(default=900, ge=60)
    # STT 상한(24시간)과 서버 시계 차이를 감안해 기본 23시간 55분. 86100초보다 길게 줘도
    # 접수 서비스가 86100초로 맞춘다(`speech_analysis_pipeline.STT_MAX_DATA_SECONDS`).
    speech_audio_retention_seconds: int = Field(default=86100, ge=60, le=86400)
    max_audio_bytes: int = Field(default=512 * 1024 * 1024, gt=0)
    speech_analysis_lease_seconds: int = Field(default=900, ge=60)
    speech_worker_poll_seconds: float = Field(default=2.0, ge=0.1)

    # 카드 생성(API 4-1). 모델과 promptVersion은 작업을 만들 때 저장하고 생성 함수에 넘김.
    # ML API 키가 비어 있으면 4-1은 503. 2판부터 아픈 경험 카드에 `sensitive`를 붙임(2026-11-09).
    # 기본은 v3(general을 어르신의 취향과 겪은 일을 여쭙는 열린 소재로 바꾼 버전, 2026-11-10). ai 패키지의 최신 버전과 같아야 함
    card_generation_model: str = "gpt-6-luna"
    card_generation_prompt_version: int = Field(default=3, ge=1)
    ml_api_key: SecretStr = SecretStr("")
    # 운영 동작 보존: 합성 검증 뒤 명시적으로 켠다. 횟수는 최대 1회로 고정.
    llm_retry_enabled: bool = False
    llm_retry_delay_seconds: float = Field(default=1.0, ge=0, le=30)
    # 카드 생성 worker(4-1 처리). 생성에 1~2분 걸려 임대는 300초로 둠.
    card_generation_lease_seconds: int = Field(default=300, ge=60)
    # 4-1 뒤 이 시간이 지나도 worker가 가져가지 않았고, 이 시간 동안 worker가 어떤 작업도
    # 가져가지 않은 작업은 4-1, 4-2가 실패로 정리함. worker가 앞 작업을 처리하는 중이면
    # 기다리게 둠. 앞 작업 하나가 임대 시간까지 걸릴 수 있어 임대 시간보다 길게 둠.
    card_generation_start_timeout_seconds: int = Field(default=360, ge=60)
    # 첫 등록 사진 대기 상한. 카드 실행 임대와 별개이며, 넘으면 사용자 선택을 기다린다.
    card_photo_wait_timeout_seconds: int = Field(default=180, ge=10)
    card_worker_poll_seconds: float = Field(default=2.0, ge=0.1)
    # 리포트 생성(8-3). 음성 worker가 STT 뒤 `ai/`의 생성 함수를 이 모델과 ML API 키로 부름.
    report_generation_model: str = "gpt-6-luna"
    # 리포트 생성 전체(요청 조립 → 리포트·변경 제안 생성 → 검증) 제한 시간. 넘기면
    # AI_SERVER_TIMEOUT. 저장과 완료 처리까지 음성 작업 임대 안에 끝나도록 임대보다
    # 60초 이상 짧아야 하며, 아니면 음성 worker가 시작하지 않음.
    report_generation_time_limit_seconds: int = Field(default=600, ge=10)

    # 프로필 사진과 면회 사진은 별도 보관 정책을 쓰므로 임시 녹음 버킷과 다른
    # 비공개 버킷에 저장한다. 비어 있으면 사진 업로드와 조회 URL 생성을 거절한다.
    image_s3_bucket: str = ""
    image_s3_region: str = "ap-northeast-2"
    image_s3_prefix: str = "photos"
    image_s3_encryption: Literal["AES256", "aws:kms"] = "AES256"
    image_presigned_ttl_seconds: int = Field(default=900, ge=60)
    max_image_bytes: int = Field(default=20 * 1024 * 1024, gt=0)
    # 프로필 사진 분석 worker(app/workers/photo_analysis.py). 환경과 관계없이 실행되며
    # AI 사진 분석(photoAnalysis)에 동의한 계정의 사진만 분석한다(photo_analysis_jobs.py).
    photo_analysis_model: str = ""  # 비어 있으면 report_generation_model을 사용
    photo_analysis_timeout_seconds: int = Field(default=120, ge=10)
    photo_analysis_lease_seconds: int = Field(default=180, ge=60)
    photo_worker_poll_seconds: float = Field(default=2.0, ge=0.1)

    # 구글 ID 토큰의 `aud` 로 허용할 클라이언트 ID 목록. 쉼표로 구분한다.
    # `google_sign_in` 에 `serverClientId` 를 넘기면 `aud` 가 그 웹 클라이언트 ID가
    # 되므로, FE 가 어떤 값을 쓰는지 확인한 뒤 채운다. 비어 있으면 로그인을 거부한다.
    # NoDecode 가 없으면 pydantic-settings 가 복합 타입 값을 JSON 으로 먼저
    # 파싱해서, 빈 값이나 쉼표 목록이 `_split_client_ids` 에 닿기 전에 깨진다.
    google_client_ids: Annotated[tuple[str, ...], NoDecode] = ()
    google_jwks_url: str = GOOGLE_JWKS_URL
    google_jwks_cache_seconds: int = Field(default=3600, ge=60)

    # 자체 세션 토큰 서명 키. 비어 있으면 인증 경로 전체가 503 으로 거부된다.
    # HS256 서명에 쓰므로 32바이트 미만은 설정 단계에서 막는다(RFC 7518 3.2).
    session_secret: str = ""
    session_ttl_seconds: int = Field(default=3600, ge=60)
    # 구글 인증과 동의 제출 사이에만 쓰는 임시 등록 토큰의 수명.
    registration_ttl_seconds: int = Field(default=600, ge=60)

    # 동의 화면이 제시하는 약관 버전. 계약의 `consentVersion` 과 같은 값이다.
    consent_version: str = "2026-09-06"

    # ADR-007 의 PM 제안(이메일과 구글 계정 이름을 저장하지 않음)을 기본값으로 둔다.
    # 저장 범위가 확정되면 이 값을 바꾸고 ADR-007 과 법률 문서를 함께 갱신한다.
    store_google_profile: bool = False
    # 구글 계정 이름을 저장하지 않을 때 쓰는 기본 표시 이름.
    default_display_name: str = "보호자"

    # 받을 수 있는 가장 낮은 안드로이드 앱 versionCode. 앱이 `X-App-Version-Code` 로
    # 보낸 값이 이보다 낮으면 426 `APP_UPDATE_REQUIRED` 로 거절한다. 0 이면 검사하지
    # 않는다. 구버전과 맞지 않는 서버를 올리기 전에, 맞는 앱을 Play 에 낸 뒤 올린다.
    min_android_version_code: int = Field(default=0, ge=0)

    # 리포트 완료 푸시(FCM)에 쓰는 Firebase 서비스 계정 키 파일 경로. 음성 worker만
    # 읽는다. 비어 있으면 푸시를 보내지 않고 리포트 처리는 그대로 한다. 키 파일은
    # 저장소와 이미지에 넣지 않고 실행할 때 마운트한다(docs/deployment.md).
    fcm_credentials_path: str = ""
    # FCM 인증과 발송 요청 하나의 제한 시간.
    fcm_timeout_seconds: float = Field(default=10.0, gt=0, le=60)

    # 계정별 사용 한도(2026-11-09 PM 결정). 한 계정이 DB 연결, STT와 ML 호출을 독차지하지
    # 않게 한다. 짧은 음성 전사(6-6)를 한 계정이 동시에 보낼 수 있는 수. 넘으면 429.
    # 앱은 전사 중에도 `건너뛰기`로 다음 항목을 녹음해 보낼 수 있어 기본을 2로 둔다.
    short_transcription_concurrency_per_account: int = Field(default=2, ge=1)
    # 짧은 음성 전사(6-6)를 서버 전체에서 동시에 처리하는 수. 넘으면 S3와 STT를 부르지 않고
    # 503. STT 서버가 동시에 처리하는 수를 확인하기 전이라 기본은 제한 없음(비워 둠).
    short_transcription_concurrency_total: int | None = Field(default=None, ge=1)
    # 6-6이 STT 응답을 기다리는 시간. 앱은 업로드를 포함해 2분에 포기하므로(speech_api.dart)
    # 그보다 짧게 둬서, 앱이 떠난 뒤 서버가 DB 연결과 STT를 붙잡고 있지 않게 한다. 잠정값이며
    # 실제 처리 시간 측정 뒤 #138에서 정한다. `ai_server_timeout_seconds`보다 길면 그 값을 쓴다.
    short_transcription_timeout_seconds: float = Field(default=90.0, gt=0)
    # 계정당 푸시 받을 기기 수(1-7). 넘으면 등록 시각이 가장 오래된 기기를 지운다.
    push_devices_per_account: int = Field(default=5, ge=1)
    # 면회 회차당 리포트 재요청(6-5) 수. 넘으면 409.
    report_retries_per_session: int = Field(default=3, ge=1)

    @field_validator("session_secret")
    @classmethod
    def _reject_short_secret(cls, value: str) -> str:
        if value and len(value.encode("utf-8")) < 32:
            raise ValueError("session_secret 은 32바이트 이상이어야 한다")
        return value

    @field_validator("ai_server_backup_url", mode="before")
    @classmethod
    def _empty_backup_url_is_disabled(cls, value: object) -> object:
        if isinstance(value, str):
            return value.strip() or None
        return value

    @field_validator("short_transcription_concurrency_total", mode="before")
    @classmethod
    def _empty_total_is_unlimited(cls, value: object) -> object:
        if isinstance(value, str):
            return value.strip() or None
        return value

    @field_validator("google_client_ids", mode="before")
    @classmethod
    def _split_client_ids(cls, value: object) -> object:
        if isinstance(value, str):
            return tuple(part.strip() for part in value.split(",") if part.strip())
        return value


@lru_cache
def get_settings() -> Settings:
    return Settings()
