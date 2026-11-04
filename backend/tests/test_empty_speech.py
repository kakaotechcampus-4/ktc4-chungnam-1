import pytest

from tests.support import run
from tests.test_speech_analyses import (
    ACCOUNT,
    FakeAiServer,
    FakeReportGenerator,
    harness,
    speech_worker,
    submit,
)


@pytest.mark.parametrize(
    "segments",
    [
        [],
        [
            {
                "startMs": 0,
                "endMs": 100,
                "speakerLabel": None,
                "text": " \n\t",
                "words": [],
            }
        ],
    ],
)
def test_empty_segments_never_generate_report(segments):
    application, jobs, storage, _ = harness()
    accepted = submit(application).json()

    class EmptyAi(FakeAiServer):
        async def analyze_speech(self, payload):
            result = await super().analyze_speech(payload)
            return type(result).model_validate(
                {**result.model_dump(by_alias=True), "segments": segments}
            )

    reports = FakeReportGenerator()
    run(speech_worker(jobs, storage, EmptyAi(), reports).run_once())
    job = run(
        jobs.get_for_account(
            analysis_id=accepted["analysisId"], account_id=ACCOUNT.account_id
        )
    )
    assert job.status == "failed"
    assert job.error_code == "EMPTY_TRANSCRIPT"
    assert job.stt_completed_at is None
    assert reports.sessions == []
    assert storage.objects == {}


def test_unassigned_but_nonempty_speech_is_not_rejected_as_empty():
    application, jobs, storage, _ = harness()
    accepted = submit(application).json()

    class UnassignedAi(FakeAiServer):
        async def analyze_speech(self, payload):
            result = await super().analyze_speech(payload)
            return result.model_copy(
                update={
                    "segments": [
                        result.segments[0].model_copy(update={"speaker_label": None})
                    ]
                }
            )

    reports = FakeReportGenerator()
    run(speech_worker(jobs, storage, UnassignedAi(), reports).run_once())
    job = run(
        jobs.get_for_account(
            analysis_id=accepted["analysisId"], account_id=ACCOUNT.account_id
        )
    )
    assert job.status == "completed"
