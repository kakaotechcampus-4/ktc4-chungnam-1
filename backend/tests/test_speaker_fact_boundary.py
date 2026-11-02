import pytest

from app.core.errors import AppError
from tests import test_visit_report_generator as report_tests
from tests.test_visit_report_generator import (
    FakeAi, NOTHING_SAVED, _evaluated, _generate, _report, _saved_rows,
)
from tests.visit_records import Records


@pytest.mark.parametrize("labels", [["SPEAKER_00"], [None], [""], ["SPEAKER_00", None]])
def test_ambiguous_speaker_fact_is_not_saved(migrated_database_url, monkeypatch, labels):
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    original = report_tests._speech

    def ambiguous(analysis_id=report_tests.ANALYSIS_ID):
        speech = original(analysis_id)
        segment = speech.segments[0]
        return speech.model_copy(update={"segments": [
            segment.model_copy(update={"speaker_label": label}) for label in labels
        ]})

    monkeypatch.setattr(report_tests, "_speech", ambiguous)
    with pytest.raises(AppError) as error:
        _generate(records, visit, FakeAi(_report(visit)))
    assert error.value.error_code == "UNVERIFIED_SPEAKER_FACT"
    assert _saved_rows(records, visit) == NOTHING_SAVED


def test_report_without_new_facts_does_not_fail_for_one_label(migrated_database_url, monkeypatch):
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    original = report_tests._speech

    def one_label(analysis_id=report_tests.ANALYSIS_ID):
        speech = original(analysis_id)
        return speech.model_copy(update={"segments": speech.segments[:1]})

    monkeypatch.setattr(report_tests, "_speech", one_label)
    _generate(records, visit, FakeAi(_report(
        visit, lifeFactProposals=[], topicProposals=[],
        body="두 사람이 함께 있었지만 발화 라벨은 하나여서 누가 한 말인지 확인하지 못했습니다.",
    )))
    saved = _saved_rows(records, visit)
    assert saved["report"]["generated"] is True
    assert saved["life_fact_proposals"] == []
