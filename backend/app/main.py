from fastapi import FastAPI

from app.api.body_limits import RequestBodyLimit
from app.api.router import api_router
from app.clients.ai_server import AiServerClient
from app.core.config import get_settings
from app.core.errors import register_exception_handlers
from app.core.logging import configure_logging, install_request_logging


def create_app() -> FastAPI:
    settings = get_settings()
    configure_logging(settings.log_level)

    # 운영에서는 자동 API 문서와 스키마 주소를 닫는다. 명세는 docs/architecture/api-spec.md가 기준이다.
    docs_open = settings.environment != "production"
    application = FastAPI(
        title=settings.service_name,
        version=settings.service_version,
        description="Flutter 연동과 Python 처리 파이프라인 검증을 위한 로컬 기준 환경",
        docs_url="/docs" if docs_open else None,
        redoc_url="/redoc" if docs_open else None,
        openapi_url="/openapi.json" if docs_open else None,
    )
    register_exception_handlers(application)
    # 본문 크기 상한과 업로드 경로의 세션 서명 확인. FastAPI가 본문을 읽기 전에 돈다.
    # 요청 로그보다 먼저 등록해야 안쪽에 놓여, 여기서 거절한 요청도 요청 ID와 로그가 남는다.
    application.add_middleware(RequestBodyLimit)
    install_request_logging(application)
    application.state.ai_server_client = AiServerClient(
        base_url=settings.ai_server_url,
        timeout_seconds=settings.ai_server_timeout_seconds,
        backup_base_url=settings.ai_server_backup_url,
        failover_connect_timeout_seconds=settings.ai_server_failover_connect_timeout_seconds,
    )
    application.include_router(api_router)
    return application


app = create_app()
