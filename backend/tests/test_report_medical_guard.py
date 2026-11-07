import pytest

from app.core.errors import AppError
from tests.test_visit_report_generator import (
    FakeAi, NOTHING_SAVED, _evaluated, _generate, _report, _saved_rows,
)
from tests.visit_records import Records


@pytest.mark.parametrize("field", ["body", "title", "cardSummaries", "lifeFactProposals", "topicProposals"])
def test_unsafe_claim_stops_entire_report_before_any_save(migrated_database_url, field):
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    result = _report(visit)
    unsafe = "새록은 치매를 치료합니다."
    if field in {"body", "title"}:
        result[field] = unsafe
    elif field == "cardSummaries":
        result[field][0]["summary"] = unsafe
    else:
        result[field][0]["reason"] = unsafe
    with pytest.raises(AppError) as caught:
        _generate(records, visit, FakeAi(result))
    assert caught.value.error_code == "UNSAFE_MEDICAL_CLAIM"
    assert _saved_rows(records, visit) == NOTHING_SAVED


def test_hospital_visit_can_be_reported_without_claiming_treatment(migrated_database_url):
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    result = _report(visit, body="병원에 다녀왔다는 이야기를 나눴습니다. 치매 약을 먹고 있다고 말했습니다.")
    _generate(records, visit, FakeAi(result))
    assert _saved_rows(records, visit)["report"]["generated"]


def test_quoted_elder_speech_about_treatment_is_saved(migrated_database_url):
    """어르신의 말을 옮긴 문장은 효과 주장으로 보지 않는다(멘토 리뷰 11/5)."""
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    result = _report(visit, body='어르신께서 "치매는 치료할 수 있다더라"고 말씀하셨어요. 텔레비전에서 본 이야기라고 하셨습니다.')
    _generate(records, visit, FakeAi(result))
    assert _saved_rows(records, visit)["report"]["generated"]
