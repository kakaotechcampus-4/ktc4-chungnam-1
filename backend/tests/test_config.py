from app.core.config import Settings


def test_default_settings_are_safe_for_local_development() -> None:
    settings = Settings(_env_file=None)

    assert settings.environment == "development"
    assert settings.log_level == "INFO"
    assert settings.service_name == "saerok-backend"
    assert settings.ai_server_url == "http://127.0.0.1:8001"
    assert settings.ai_server_timeout_seconds == 600.0
