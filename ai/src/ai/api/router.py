from fastapi import APIRouter

from ai.api.routes.health import router as health_router
from ai.api.routes.speech_analyses import router as speech_analyses_router


api_router = APIRouter()
api_router.include_router(health_router)
api_router.include_router(speech_analyses_router)
