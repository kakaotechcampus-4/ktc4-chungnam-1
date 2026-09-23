import pytest

from app.core.config import Settings


def test_default_settings_are_safe_for_local_development() -> None:
    settings = Settings(_env_file=None)

    assert settings.environment == "development"
    assert settings.log_level == "INFO"
    assert settings.service_name == "saerok-backend"


# 아래 두 개는 환경변수를 직접 읽는 경로를 검사한다. 값을 생성자로 넘기면
# pydantic-settings 의 환경변수 디코딩 단계를 건너뛰어서, `google_client_ids` 의
# NoDecode 가 빠져도 통과해 버린다.
def test_google_client_ids_read_each_id_from_comma_separated_environment_value(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv(
        "SAEROK_GOOGLE_CLIENT_IDS",
        "first.apps.googleusercontent.com, second.apps.googleusercontent.com",
    )

    settings = Settings(_env_file=None)

    assert settings.google_client_ids == (
        "first.apps.googleusercontent.com",
        "second.apps.googleusercontent.com",
    )


def test_google_client_ids_read_empty_environment_value_as_empty_list(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("SAEROK_GOOGLE_CLIENT_IDS", "")

    settings = Settings(_env_file=None)

    assert settings.google_client_ids == ()
