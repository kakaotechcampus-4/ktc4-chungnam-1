import asyncio

import psycopg
from fastapi import APIRouter

from app.api.deps import SettingsDep
from app.core.config import get_settings
from app.core.database import connect
from app.core.errors import AppError
from app.schemas.common import HealthResponse

router = APIRouter(prefix="/health", tags=["health"])


@router.get("/live", summary="생존 확인", response_model=HealthResponse)
async def liveness() -> HealthResponse:
    """서버 프로세스가 응답하는지만 봄. compose 헬스체크가 호출함."""

    settings = get_settings()
    return HealthResponse(
        status="ok",
        service=settings.service_name,
        version=settings.service_version,
    )


@router.get("/ready", summary="준비 상태 확인", response_model=HealthResponse)
async def readiness(settings: SettingsDep) -> HealthResponse:
    """DB 연결과 조회만 확인한다. GPU와 모델 호출은 운영 점검에서 따로 확인한다."""

    if not settings.database_url:
        raise AppError(
            status_code=503,
            error_code="DATABASE_NOT_CONFIGURED",
            message="서버 저장소가 설정되지 않았습니다.",
        )

    async def check_database() -> None:
        async with connect(settings.database_url) as connection:
            await connection.execute("SELECT 1")

    try:
        await asyncio.wait_for(check_database(), timeout=3)
    except (psycopg.Error, OSError, TimeoutError) as error:
        # 연결 문자열과 DB 예외의 원문은 응답과 로그에 남기지 않는다.
        raise AppError(
            status_code=503,
            error_code="DATABASE_UNAVAILABLE",
            message="서버 저장소에 연결할 수 없습니다.",
            retryable=True,
        ) from error

    return HealthResponse(
        status="ready",
        service=settings.service_name,
        version=settings.service_version,
    )
