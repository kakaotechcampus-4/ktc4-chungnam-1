from contextlib import asynccontextmanager

import psycopg
import pytest

from app.api.routes import health
from app.core.config import Settings, get_settings
from app.main import app, create_app
from tests.support import request


def test_liveness() -> None:
    response = request(app, "GET", "/health/live")

    assert response.status_code == 200
    assert response.json() == {
        "schemaVersion": 1,
        "status": "ok",
        "service": "saerok-backend",
        "version": "0.1.0",
    }
    assert response.headers["X-Request-ID"]


def configured_app(database_url):
    application = create_app()
    settings = Settings(_env_file=None, database_url=database_url)
    application.dependency_overrides[get_settings] = lambda: settings
    return application


def test_readiness(migrated_database_url) -> None:
    response = request(configured_app(migrated_database_url), "GET", "/health/ready")

    assert response.status_code == 200
    assert response.json()["status"] == "ready"


def test_readiness_without_database_does_not_report_ready():
    response = request(configured_app(None), "GET", "/health/ready")
    assert response.status_code == 503
    assert response.json()["errorCode"] == "DATABASE_NOT_CONFIGURED"


@pytest.mark.parametrize("error", [psycopg.OperationalError, TimeoutError, OSError])
def test_database_failure_is_safe_and_liveness_is_independent(monkeypatch, error):
    @asynccontextmanager
    async def unavailable(url):
        raise error("password=synthetic-secret host=private-database")
        yield

    monkeypatch.setattr(health, "connect", unavailable)
    application = configured_app(
        "postgresql://synthetic:synthetic-secret@private-database/db"
    )
    response = request(application, "GET", "/health/ready")
    assert response.status_code == 503
    assert response.json()["errorCode"] == "DATABASE_UNAVAILABLE"
    assert response.json()["retryable"] is True
    assert (
        "synthetic-secret" not in response.text
        and "private-database" not in response.text
    )
    assert request(application, "GET", "/health/live").status_code == 200
