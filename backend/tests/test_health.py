from app.main import app
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


def test_readiness() -> None:
    response = request(app, "GET", "/health/ready")

    assert response.status_code == 200
    assert response.json()["status"] == "ready"
