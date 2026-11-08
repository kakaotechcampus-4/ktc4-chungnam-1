"""리포트 생성에서 LLM 없이 확인할 수 있는 것: #106 규칙으로 요약 거르기, 모르는 모델 거절, 응답 합치기."""

from datetime import date

import pytest

from common.visit_report import (
    ProposalResult,
    ReportCard,
    ReportCardTopic,
    ReportEvaluation,
    ReportProfileFacts,
    ReportResult,
    Transcript,
    TranscriptSegment,
    VisitReportError,
    VisitReportRequest,
    card_refs,
    combine,
    llm_payload,
)
from report_generation import generate_report
from report_generation.generate import _Report, _Summary, _summaries


def request(*reactions) -> VisitReportRequest:
    cards = [ReportCard(card_id=f"id-{i}", card_title=f"카드{i}", topic=ReportCardTopic(topic_id=f"t{i}", title=f"주제{i}"),
                        reaction=r) for i, r in enumerate(reactions, 1)]
    return VisitReportRequest(
        analysis_id="a1", visit_date=date(2026, 10, 10),
        evaluation=ReportEvaluation(conversation_satisfaction=4, care_recipient_reaction="calm", free_note=None),
        cards=cards, profile_facts=ReportProfileFacts(occupation=None, hometown=None, hobby=None, family=None),
        life_facts=[], transcript=Transcript(duration_ms=1000, segments=[
            TranscriptSegment(start_ms=0, end_ms=500, speaker_label="SPEAKER_02", text="합성 발화"),
            TranscriptSegment(start_ms=500, end_ms=1000, speaker_label=None, text="(잘 안 들림)")]))


def test_summaries_follow_106_rules():
    req = request("positive", "notUsed", None, "negative")
    out = _Report(title="t", body="b", card_summaries=[
        _Summary(card="c1", summary="좋았음"), _Summary(card="c1", summary="두 번째"),   # 같은 카드 두 번째는 버림
        _Summary(card="c2", summary="안 씀"), _Summary(card="c3", summary="반응 없음"),   # notUsed·무응답은 버림
        _Summary(card="c4", summary="아쉬웠음"), _Summary(card="c9", summary="없는 카드"), _Summary(card="c4 ", summary=" ")])
    kept = _summaries(out, req, card_refs(req))
    assert [(s.card_id, s.summary) for s in kept] == [("id-1", "좋았음"), ("id-4", "아쉬웠음")]


def test_payload_hides_card_ids_and_keeps_null_speaker():
    req = request("positive")
    text = llm_payload(req, card_refs(req), with_facts=False)
    assert "id-1" not in text and '"card": "c1"' in text and '"speaker": null' in text and "SPEAKER_02" in text


def test_unknown_model_is_rejected():
    with pytest.raises(VisitReportError) as e:
        generate_report(request("positive"), model="unknown-model", api_key="x")
    assert e.value.code == "INVALID_REQUEST"


def test_combine_makes_106_response():
    r = ReportResult(model="gpt-5.6-luna", prompt_version="report-1", title="t", body="b", card_summaries=[])
    p = ProposalResult(model="gpt-5.6-luna", prompt_version="proposals-1", life_fact_proposals=[], topic_proposals=[])
    out = combine("a1", r, p).model_dump(by_alias=True)
    assert out["analysisId"] == "a1" and out["promptVersion"] == "report-1+proposals-1"
    assert set(out) == {"schemaVersion", "analysisId", "model", "promptVersion", "title", "body", "cardSummaries",
                        "lifeFactProposals", "topicProposals"}


def test_prompt_keeps_processing_words_out_of_the_report():
    """11/8 운영 시험: '전사에는 ~ 확인되지 않아', '보호자 소감에는 ~ 적혀 있습니다'가 리포트에 나옴.
    실제 모델 동작이 아니라 프롬프트 문구만 확인함."""
    from report_generation.generate import PROMPT

    text = PROMPT.read_text(encoding="utf-8")
    assert "화자 정보가 불충분하다는 사실을 숨기지 않는다" not in text
    assert "처리 과정을 가리키는 말을 쓰지 않는다" in text
    assert "소감을 본문에 다시 옮겨 적지 않고" in text
    assert "보호자는 기본적으로 어르신의 자녀" in text
    # 11/8 실제 모델 비교: '아버지' 예시만 두면 '엄마'라고 부른 대화에서도 어르신을 '아버지'로 씀
    assert "보호자가 '아버지'라고 부른 분은 리포트에서도 '아버지'다" not in text
    assert "보호자가 어르신을 부른 호칭을 따르고" in text
    assert "부른 호칭이 없으면 '어르신'이라고 쓴다" in text
    assert "카드 요약에는 반응만 짧게 쓴다" in text
