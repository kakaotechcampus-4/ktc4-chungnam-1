"""화자 라벨에 관계없이 생성하며 빈 전사와 임대 만료는 거절한다."""

import pytest

from app.core.errors import AppError
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


@pytest.mark.parametrize("labels,participants", [
    (["SPEAKER_00", "SPEAKER_01"], 2), (["SPEAKER_00"], 1),
    (["SPEAKER_00"], 2), (["SPEAKER_00", "SPEAKER_00"], 3),
    ([None], 2), ([""], 2), (["  "], 2),
    (["SPEAKER_00", None], 2), (["SPEAKER_00", "SPEAKER_01", None], 3),
])
def test_labels_do_not_block_generation(
    migrated_database_url, monkeypatch, labels, participants,
):
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    _generating_job(records, visit)
    records.execute("UPDATE speech_analysis_jobs SET participant_count = %s WHERE analysis_id = %s",
                    (participants, ANALYSIS_ID))
    before = records.query(
        "SELECT evaluation_satisfaction, evaluation_reaction, evaluation_note, evaluated_at "
        "FROM visit_sessions WHERE session_id = %s", (visit.session_id,),
    )
    _set_labels(monkeypatch, labels)
    calls = _connected(monkeypatch)
    _generate_with(records, visit, _connected_generator())
    assert [call["kind"] for call in calls] == ["report", "proposals"]
    saved = _saved_rows(records, visit)
    assert len(saved["life_fact_proposals"]) == 1
    assert len(saved["topic_proposals"]) == 1
    assert saved["report"]["generated"] is True
    assert saved["report"]["report_title"] == "합성 리포트 제목"
    assert len(saved["summaries"]) == 1
    assert records.scalar("SELECT count(*) FROM life_facts") == 0
    job = records.query(
        "SELECT status, transcript FROM speech_analysis_jobs WHERE analysis_id = %s",
        (ANALYSIS_ID,),
    )[0]
    assert job == {"status": "completed", "transcript": None}
    assert records.query(
        "SELECT evaluation_satisfaction, evaluation_reaction, evaluation_note, evaluated_at "
        "FROM visit_sessions WHERE session_id = %s", (visit.session_id,),
    ) == before
    user_id = records.scalar(
        "SELECT user_id FROM profiles WHERE profile_id = %s", (visit.profile_id,),
    )
    response = records.call(user_id, "GET", f"/api/v1/visit-sessions/{visit.session_id}/report")
    assert response.status_code == 200
    assert response.json()["title"] == saved["report"]["report_title"]
    assert len(response.json()["cardSummaries"]) == 1
    proposals = records.call(user_id, "GET", f"/api/v1/visit-sessions/{visit.session_id}/proposals")
    assert proposals.status_code == 200
    assert len(proposals.json()["lifeFactProposals"]) == 1
    assert len(proposals.json()["topicProposals"]) == 1


def test_empty_transcript_is_rejected(migrated_database_url, monkeypatch):
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    _set_labels(monkeypatch, [])
    ai = FakeAi(_report(visit))
    with pytest.raises(AppError) as error:
        _generate(records, visit, ai)
    assert error.value.error_code == "EMPTY_TRANSCRIPT"
    assert ai.report_requests == []
    assert _saved_rows(records, visit) == NOTHING_SAVED


def test_generation_still_requires_live_worker_lease(migrated_database_url, monkeypatch):
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
    assert len(ai.report_requests) == 1
    assert _saved_rows(records, visit) == NOTHING_SAVED


@pytest.mark.parametrize("labels,participants", [
    ([None], 2), ([""], 2), (["  "], 2),
    (["SPEAKER_00", None], 2), (["SPEAKER_00"], 3),
])
def test_generation_without_database_does_not_gate_on_labels(monkeypatch, labels, participants):
    from uuid import UUID
    from unittest.mock import AsyncMock

    from app.schemas.visit_report_generation import VisitReportRequest, VisitReportResult
    from app.services import visit_report_generator as generator

    request = VisitReportRequest.model_validate({
        "analysisId": ANALYSIS_ID, "visitDate": "2026-11-06",
        "participantCount": participants, "cards": [], "lifeFacts": [],
        "evaluation": {
            "conversationSatisfaction": 4, "careRecipientReaction": "pleased",
            "freeNote": None,
        },
        "profileFacts": {"occupation": None, "hometown": None, "hobby": None, "family": None},
        "transcript": {
            "durationMs": 1000,
            "segments": [
                {"startMs": 0, "endMs": 1000, "text": "합성 발화 구간", "speakerLabel": label}
                for label in labels
            ],
        },
    })
    result = VisitReportResult.model_validate({
        "schemaVersion": 1, "analysisId": ANALYSIS_ID,
        "model": "synthetic-model", "promptVersion": "test",
        "title": "합성 리포트", "body": "합성 대화 요약",
        "cardSummaries": [], "lifeFactProposals": [], "topicProposals": [],
    })
    build = AsyncMock(return_value=(UUID(ANALYSIS_ID), request))
    save = AsyncMock()
    monkeypatch.setattr(generator, "build_request", build)
    monkeypatch.setattr(generator, "save_report", save)
    calls = []

    def generate(received, deadline):
        calls.append(received)
        return result

    run(generator.VisitReportGenerator(generate=generate, time_limit_seconds=30).generate(
        None, session_id=ANALYSIS_ID, speech=None,
    ))
    assert calls == [request]
    save.assert_awaited_once_with(None, UUID(ANALYSIS_ID), UUID(ANALYSIS_ID), request, result)
