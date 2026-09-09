from fastapi import FastAPI

from app.api.router import api_router
from app.core.config import get_settings
from app.core.errors import register_exception_handlers
from app.core.logging import configure_logging, install_request_logging


def create_app() -> FastAPI:
    settings = get_settings()
    configure_logging(settings.log_level)

    application = FastAPI(
        title=settings.service_name,
        version=settings.service_version,
        description="Flutter 연동과 Python 처리 파이프라인 검증을 위한 로컬 기준 환경",
    )
    register_exception_handlers(application)
    install_request_logging(application)
    application.include_router(api_router)
    return application


app = create_app()
