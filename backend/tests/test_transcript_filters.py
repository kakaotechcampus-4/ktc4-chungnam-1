"""무음에서 STT가 지어내는 알려진 문장을 거르는지 확인한다. 문장은 모두 합성이다."""

from types import SimpleNamespace

import pytest

from app.services.transcript_filters import drop_known_hallucinations, is_known_hallucination
from tests.support import run
from tests.test_empty_speech import ACCOUNT, FakeAiServer, FakeReportGenerator, harness, speech_worker, submit
from tests.test_short_speech_transcription import harness as short_harness
from tests.test_short_speech_transcription import submit as short_submit


@pytest.mark.parametrize(
    "text",
    [
        "다음 영상에서 만나요.",
        " 다음 영상에서 만나요! ",
        "시청해 주셔서 감사합니다.",
        "구독과 좋아요 부탁드립니다.",
        "MBC 뉴스 이덕영입니다.",
        "한글자막 by 한효정",
        "한글 자막 by 한효정",
        "이 영상은 유료 광고를 포함하고 있습니다.",
        "자막 제공 및 광고를 포함하고 있습니다.",
    ],
)
def test_known_hallucinations_are_recognized(text):
    assert is_known_hallucination(text)


@pytest.mark.parametrize(
    "text",
    [
        "",
        "감사합니다.",
        "다음 영상에서 만나요 그런 말을 손녀가 자주 해.",
        "시장에서 국수 가게를 했어.",
        "다음에 또 만나요.",
        "아토",
        "자막을 켜고 드라마를 보셨어요.",
        "광고에 나오던 노래를 좋아하셨지.",
    ],
)
def test_real_speech_is_kept(text):
    assert not is_known_hallucination(text)


def _segment(text, start=0):
    return {"startMs": start, "endMs": start + 900, "speakerLabel": "SPEAKER_00", "text": text, "words": []}


def _with_segments(result, texts):
    return type(result).model_validate({
        **result.model_dump(by_alias=True),
        "text": " ".join(texts),
        "segments": [_segment(text, i * 1000) for i, text in enumerate(texts)],
    })


class _ScriptedAi(FakeAiServer):
    def __init__(self, texts):
        super().__init__()
        self.texts = texts

    async def analyze_speech(self, payload):
        result = await super().analyze_speech(payload)
        return _with_segments(result, self.texts)


def test_only_known_segments_are_dropped_and_text_is_rebuilt():
    result = run(_ScriptedAi(["누렁이를 팔러 갔어.", "다음 영상에서 만나요."]).analyze_speech(SimpleNamespace(analysis_id="synthetic-analysis")))

    filtered = drop_known_hallucinations(result)

    assert [segment.text for segment in filtered.segments] == ["누렁이를 팔러 갔어."]
    assert filtered.text == "누렁이를 팔러 갔어."


def test_result_without_known_segments_is_returned_as_is():
    result = run(_ScriptedAi(["누렁이를 팔러 갔어."]).analyze_speech(SimpleNamespace(analysis_id="synthetic-analysis")))
    assert drop_known_hallucinations(result) is result


def test_visit_with_only_a_known_hallucination_fails_as_empty_without_a_report():
    application, jobs, storage, _ = harness()
    accepted = submit(application).json()
    reports = FakeReportGenerator()

    run(speech_worker(jobs, storage, _ScriptedAi(["다음 영상에서 만나요."]), reports).run_once())

    job = run(jobs.get_for_account(analysis_id=accepted["analysisId"], account_id=ACCOUNT.account_id))
    assert job.status == "failed"
    assert job.error_code == "EMPTY_TRANSCRIPT"
    assert reports.sessions == []


class _Reports:
    def __init__(self):
        self.texts = []

    async def generate(self, connection, *, session_id, speech):
        del connection, session_id
        self.texts.append(speech.text)


def test_visit_keeps_real_speech_around_a_known_hallucination():
    application, jobs, storage, _ = harness()
    accepted = submit(application).json()
    reports = _Reports()

    run(speech_worker(jobs, storage, _ScriptedAi(["누렁이를 팔러 갔어.", "다음 영상에서 만나요."]), reports).run_once())

    job = run(jobs.get_for_account(analysis_id=accepted["analysisId"], account_id=ACCOUNT.account_id))
    assert job.status == "completed"
    assert reports.texts == ["누렁이를 팔러 갔어."]


def test_profile_speech_returns_empty_text_for_a_known_hallucination(migrated_database_url):
    app, _, _ = short_harness(migrated_database_url, ai=_ScriptedAi(["다음 영상에서 만나요."]))

    response = short_submit(app)

    assert response.status_code == 200, response.text
    assert response.json() == {"schemaVersion": 1, "text": ""}
