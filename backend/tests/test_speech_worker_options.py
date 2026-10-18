import sys

import pytest

from app.core.config import Settings
from app.workers import speech_analysis as entry


@pytest.mark.parametrize('stt_only', [False, True])
def test_report_wiring(monkeypatch, stt_only):
    monkeypatch.setattr(entry, 'S3AudioStorage', lambda **kwargs: object())
    monkeypatch.setattr(entry, 'create_speech_worker', lambda **kwargs: kwargs)
    # 기본 모드는 리포트 생성에 ML API 키가 필요하다(#123). 합성 키를 쓴다.
    settings = Settings(
        database_url='postgresql://synthetic', speech_audio_s3_bucket='synthetic',
        ml_api_key='synthetic-key',
    )
    worker = entry.create_worker(settings, stt_only=stt_only)
    assert (worker['report_generator'] is None) is stt_only


def test_stt_only_runs_without_the_ml_api_key(monkeypatch):
    monkeypatch.setattr(entry, 'S3AudioStorage', lambda **kwargs: object())
    monkeypatch.setattr(entry, 'create_speech_worker', lambda **kwargs: kwargs)
    settings = Settings(
        _env_file=None, database_url='postgresql://synthetic',
        speech_audio_s3_bucket='synthetic', ml_api_key='',
    )
    assert entry.create_worker(settings, stt_only=True)['report_generator'] is None
    # 키 없이 전체 처리(리포트 생성)가 되는 것처럼 시작하지 않는다.
    with pytest.raises(RuntimeError, match='SAEROK_ML_API_KEY'):
        entry.create_worker(settings)


def test_report_time_limit_must_fit_in_the_lease(monkeypatch):
    monkeypatch.setattr(entry, 'S3AudioStorage', lambda **kwargs: object())
    monkeypatch.setattr(entry, 'create_speech_worker', lambda **kwargs: kwargs)
    settings = Settings(
        _env_file=None, database_url='postgresql://synthetic',
        speech_audio_s3_bucket='synthetic', ml_api_key='synthetic-key',
        speech_analysis_lease_seconds=900, report_generation_time_limit_seconds=841,
    )
    with pytest.raises(RuntimeError, match='LEASE_SECONDS'):
        entry.create_worker(settings)
    # STT만 돌릴 때는 리포트 제한 시간을 보지 않는다.
    assert entry.create_worker(settings, stt_only=True)['report_generator'] is None
    fits = settings.model_copy(update={'report_generation_time_limit_seconds': 840})
    assert entry.create_worker(fits)['report_generator'] is not None


def test_production_rejects_stt_only():
    with pytest.raises(RuntimeError, match='development/test'):
        entry.create_worker(Settings(environment='production'), stt_only=True)


def test_cli_stt_only_once(monkeypatch):
    from app.workers import base

    seen = {}

    class FakeWorker:
        async def run(self, *, poll_seconds, once):
            seen['once'] = once

    def create(settings, *, stt_only=False):
        seen['stt_only'] = stt_only
        return FakeWorker()

    monkeypatch.setattr(entry, 'create_worker', create)
    monkeypatch.setattr(base, 'get_settings', lambda: Settings())
    monkeypatch.setattr(sys, 'argv', ['speech-worker', '--stt-only', '--once'])
    entry.main()
    assert seen == {'stt_only': True, 'once': True}
