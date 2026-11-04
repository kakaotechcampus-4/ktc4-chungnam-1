"""운영 환경에서는 자동 API 문서(/docs, /redoc, /openapi.json)를 열지 않는다."""

import pytest

from app.core.config import get_settings
from app.main import create_app
from tests.support import request

DOC_PATHS = ("/docs", "/redoc", "/openapi.json")


@pytest.fixture
def app_in(monkeypatch):
    def build(environment: str):
        monkeypatch.setenv("SAEROK_ENVIRONMENT", environment)
        get_settings.cache_clear()
        return create_app()

    yield build
    get_settings.cache_clear()


def test_production_hides_generated_api_docs(app_in):
    app = app_in("production")
    for path in DOC_PATHS:
        assert request(app, "GET", path).status_code == 404, path
    assert request(app, "GET", "/health/live").status_code == 200
    # 코드 안에서는 스키마를 계속 만들 수 있다(명세 대조 테스트가 쓴다).
    assert "/health/live" in app.openapi()["paths"]


@pytest.mark.parametrize("environment", ["development", "test"])
def test_other_environments_keep_api_docs(app_in, environment):
    app = app_in(environment)
    for path in DOC_PATHS:
        assert request(app, "GET", path).status_code == 200, path
