from fastapi import APIRouter

from app.api.routes.auth import router as auth_router
from app.api.routes.health import router as health_router
from app.api.routes.speech_analyses import router as speech_analyses_router

api_router = APIRouter()
api_router.include_router(health_router)
api_router.include_router(speech_analyses_router)
api_router.include_router(auth_router)
