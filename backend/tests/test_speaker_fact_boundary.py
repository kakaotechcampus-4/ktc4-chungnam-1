"""화자 미확인 시 모델 호출, 해석과 제안을 막고 조회 가능한 안내만 저장한다."""

import pytest

from app.core.database import connect
from app.core.errors import AppError
from app.services.visit_report_generator import (
    _unverified_speaker_notice, build_request, validate_result,
)
from tests import test_visit_report_generator as report_tests
from tests.support import run
from tests.test_visit_report_generator import (
    ANALYSIS_ID, FakeAi, NOTHING_SAVED, _connected, _connected_generator,
    _evaluated, _generate, _generate_with, _generating_job, _report, _saved_rows,
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
def test_unverified_speech_skips_both_generators_and_returns_notice(
    migrated_database_url, monkeypatch, labels,
):
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

    _generate_with(records, visit, _connected_generator())

    assert calls == []
    saved = _saved_rows(records, visit)
    assert saved["report"]["report_title"] == "화자 미확인 안내"
    body = saved["report"]["report_body"]
    assert "누가 한 말인지 충분히 구분하지 못했습니다" in body
    assert "새 이야기 후보와 주제 조정 제안을 만들지 않았습니다" in body
    assert saved["report"]["report_model"] == "not-invoked"
    assert saved["report"]["report_prompt_version"] == "speaker-unverified-v1"
    assert saved["report"]["generated"] is True
    assert saved["summaries"] == []
    assert saved["life_fact_proposals"] == []
    assert saved["topic_proposals"] == []
    assert records.scalar("SELECT count(*) FROM life_facts") == 0
    assert records.scalar("SELECT status FROM speech_analysis_jobs WHERE analysis_id = %s",
                          (ANALYSIS_ID,)) == "completed"
    assert records.query(
        "SELECT evaluation_satisfaction, evaluation_reaction, evaluation_note, evaluated_at "
        "FROM visit_sessions WHERE session_id = %s", (visit.session_id,),
    ) == before
    assert [r["review_reaction"] for r in records.query(
        "SELECT review_reaction FROM conversation_cards WHERE set_id = %s ORDER BY position",
        (visit.set_id,),
    )] == ["positive", "notUsed", None]

    user_id = records.scalar("SELECT user_id FROM profiles WHERE profile_id = %s", (visit.profile_id,))
    response = records.call(user_id, "GET", f"/api/v1/visit-sessions/{visit.session_id}/report")
    assert response.status_code == 200
    assert response.json()["title"] == "화자 미확인 안내"
    assert response.json()["body"] == body
    assert response.json()["cardSummaries"] == []
    proposals = records.call(user_id, "GET", f"/api/v1/visit-sessions/{visit.session_id}/proposals")
    assert proposals.status_code == 200
    assert proposals.json()["lifeFactProposals"] == []
    assert proposals.json()["topicProposals"] == []


@pytest.mark.parametrize("field", [
    "life_fact_proposals", "topic_proposals", "card_summaries", "body", "title",
    "model", "prompt_version", "analysis_id",
])
def test_unverified_result_cannot_bypass_notice_validation(
    migrated_database_url, monkeypatch, field,
):
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    _set_labels(monkeypatch, ["SPEAKER_00"])
    request = _request(records, visit)
    notice = _unverified_speaker_notice(request)
    fabricated = report_tests.parse_result(_report(visit), request)
    value = "another-analysis" if field == "analysis_id" else getattr(fabricated, field)

    with pytest.raises(AppError) as error:
        validate_result(request, notice.model_copy(update={field: value}))
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


def test_empty_transcript_is_not_saved_as_unverified_notice(migrated_database_url, monkeypatch):
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    _set_labels(monkeypatch, [])
    ai = FakeAi(_report(visit))
    with pytest.raises(AppError) as error:
        _generate(records, visit, ai)
    assert error.value.error_code == "EMPTY_TRANSCRIPT"
    assert ai.report_requests == []
    assert _saved_rows(records, visit) == NOTHING_SAVED


def test_unverified_notice_still_requires_live_worker_lease(migrated_database_url, monkeypatch):
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    _generating_job(records, visit)
    records.execute(
        "UPDATE speech_analysis_jobs SET lease_expires_at = now() - interval '1 second' "
        "WHERE analysis_id = %s", (ANALYSIS_ID,),
    )
    _set_labels(monkeypatch, [None])
    ai = FakeAi(_report(visit))
    with pytest.raises(AppError) as error:
        _generate(records, visit, ai)
    assert error.value.error_code == "WORKER_LEASE_EXPIRED"
    assert ai.report_requests == []
    assert _saved_rows(records, visit) == NOTHING_SAVED
