"""화자 미확인 시 모델 호출, 해석과 제안을 막고 실패로 남겨 리포트를 다시 요청할 수 있게 한다."""

import pytest

from app.core.database import connect
from app.core.errors import AppError
from app.services.visit_report_generator import build_request, validate_result
from tests import test_visit_report_generator as report_tests
from tests.support import run
from tests.test_speech_job_repository import _Db
from tests.test_visit_report_generator import (
    ANALYSIS_ID, FakeAi, NOTHING_SAVED, _connected, _connected_generator,
    _evaluated, _generate, _generate_with, _generating_job, _report, _run_worker, _saved_rows,
)
from tests.visit_records import Records


def _set_labels(monkeypatch, labels):
    original = report_tests._speech

    def speech(analysis_id=ANALYSIS_ID):
        result = original(analysis_id)
        segment = result.segments[0]
        return result.model_copy(update={"segments": [
            segment.model_copy(update={"speaker_label": label}) for label in labels
        ]})

    monkeypatch.setattr(report_tests, "_speech", speech)


def _request(records, visit):
    _generating_job(records, visit)

    async def scenario():
        async with connect(records.database_url) as connection:
            _, request = await build_request(connection, visit.session_id, report_tests._speech())
            return request

    return run(scenario())


@pytest.mark.parametrize("labels", [
    ["SPEAKER_00"], ["SPEAKER_00", "SPEAKER_00"], [None], [""], ["  "],
    ["SPEAKER_00", None], ["SPEAKER_00", "SPEAKER_01", None],
])
def test_unverified_speech_fails_without_calling_generators_or_saving(
    migrated_database_url, monkeypatch, labels,
):
    """화자를 확인하지 못하면 모델을 부르지 않고 실패로 남긴다. 보호자 소감과 평가는 그대로다."""
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    records.execute(
        "UPDATE visit_sessions SET evaluation_note = '직접 남긴 합성 소감' WHERE session_id = %s",
        (visit.session_id,),
    )
    before = records.query(
        "SELECT evaluation_satisfaction, evaluation_reaction, evaluation_note, evaluated_at "
        "FROM visit_sessions WHERE session_id = %s", (visit.session_id,),
    )
    _set_labels(monkeypatch, labels)
    calls = _connected(monkeypatch)

    with pytest.raises(AppError) as error:
        _generate_with(records, visit, _connected_generator())

    assert error.value.error_code == "SPEAKER_UNVERIFIED"
    assert calls == []
    assert _saved_rows(records, visit) == NOTHING_SAVED
    assert records.scalar("SELECT count(*) FROM life_facts") == 0
    assert records.query(
        "SELECT evaluation_satisfaction, evaluation_reaction, evaluation_note, evaluated_at "
        "FROM visit_sessions WHERE session_id = %s", (visit.session_id,),
    ) == before
    assert [r["review_reaction"] for r in records.query(
        "SELECT review_reaction FROM conversation_cards WHERE set_id = %s ORDER BY position",
        (visit.set_id,),
    )] == ["positive", "notUsed", None]


def test_unverified_session_fails_keeps_transcript_and_report_can_be_requested_again(
    migrated_database_url, monkeypatch,
):
    """멘토 리뷰(11/5): 완료로 끝내지 않고 실패로 남겨 전사를 보관하고, 리포트를 다시 요청할 수 있다."""
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    old_id = records.job(visit.session_id, "queued")
    _set_labels(monkeypatch, ["SPEAKER_00", None])
    ai = FakeAi(_report(visit))

    _run_worker(records, ai)

    row = records.query(
        "SELECT status, error_code, transcript IS NOT NULL AS has_transcript, "
        "transcript_expires_at > now() AS transcript_kept FROM speech_analysis_jobs "
        "WHERE analysis_id = %s", (old_id,),
    )[0]
    assert row == {"status": "failed", "error_code": "SPEAKER_UNVERIFIED",
                   "has_transcript": True, "transcript_kept": True}
    assert ai.report_requests == []
    assert _saved_rows(records, visit) == NOTHING_SAVED

    owner = str(records.scalar("SELECT user_id FROM profiles WHERE profile_id = %s", (visit.profile_id,)))
    retried = run(_Db(migrated_database_url).repository.retry_report(
        analysis_id=str(old_id), account_id=owner,
    ))
    assert retried.analysis_id != str(old_id)
    assert retried.status == "sttCompleted"


def test_unverified_result_cannot_be_saved_through_validation(migrated_database_url, monkeypatch):
    """다른 호출 경로가 미확인 전사로 만든 결과를 넘겨도 저장 검증에서 거절한다."""
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    _set_labels(monkeypatch, ["SPEAKER_00"])
    request = _request(records, visit)
    fabricated = report_tests.parse_result(_report(visit), request)

    with pytest.raises(AppError) as error:
        validate_result(request, fabricated)
    assert error.value.error_code == "UNVERIFIED_SPEAKER_FACT"
    assert _saved_rows(records, visit) == NOTHING_SAVED


@pytest.mark.parametrize("labels,participants", [
    (["SPEAKER_00", "SPEAKER_01"], 2), (["SPEAKER_00"], 1),
])
def test_sufficient_labels_keep_existing_generation_path(
    migrated_database_url, monkeypatch, labels, participants,
):
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    _generating_job(records, visit)
    records.execute("UPDATE speech_analysis_jobs SET participant_count = %s WHERE analysis_id = %s",
                    (participants, ANALYSIS_ID))
    _set_labels(monkeypatch, labels)
    calls = _connected(monkeypatch)
    _generate_with(records, visit, _connected_generator())
    assert [call["kind"] for call in calls] == ["report", "proposals"]
    saved = _saved_rows(records, visit)
    assert len(saved["life_fact_proposals"]) == 1
    assert len(saved["topic_proposals"]) == 1


def test_empty_transcript_is_its_own_failure(migrated_database_url, monkeypatch):
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    _set_labels(monkeypatch, [])
    ai = FakeAi(_report(visit))
    with pytest.raises(AppError) as error:
        _generate(records, visit, ai)
    assert error.value.error_code == "EMPTY_TRANSCRIPT"
    assert ai.report_requests == []
    assert _saved_rows(records, visit) == NOTHING_SAVED
