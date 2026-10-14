from fastapi import APIRouter

from app.core.config import get_settings
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
async def readiness() -> HealthResponse:
    """지금은 DB 같은 외부 의존성을 확인하지 않고 항상 `ready`."""

    settings = get_settings()
    return HealthResponse(
        status="ready",
        service=settings.service_name,
        version=settings.service_version,
    )
