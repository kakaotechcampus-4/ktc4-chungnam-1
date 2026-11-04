import importlib
import json

import pytest

from common.visit_report import VisitReportError, card_refs, llm_payload
from report_generation.tests.test_report import request


def context(req):
    return json.loads(llm_payload(req, card_refs(req), False))["transcript_context"]


def test_unknown_expected_count_is_not_assumed_to_be_two():
    result = context(request())
    assert result["expected_participant_count"] is None
    assert result["fewer_labels_than_expected"] is False
    assert result["speaker_roles_verified"] is False


def test_two_participants_with_one_label_is_marked_ambiguous():
    req = request().model_copy(update={"participant_count": 2})
    result = context(req)
    assert result["observed_speaker_label_count"] == 1
    assert result["fewer_labels_than_expected"] is True
    assert result["has_unassigned_speech"] is True


def test_single_expected_participant_is_not_a_diarization_failure():
    req = request().model_copy(update={"participant_count": 1})
    assert context(req)["fewer_labels_than_expected"] is False
    assert context(req)["speaker_roles_verified"] is False


def test_two_labels_do_not_verify_roles():
    req = request().model_copy(update={"participant_count": 2})
    req.transcript.segments[1].speaker_label = "SPEAKER_01"
    result = context(req)
    assert result["observed_speaker_label_count"] == 2
    assert result["fewer_labels_than_expected"] is False
    assert result["speaker_roles_verified"] is False


@pytest.mark.parametrize("module_name", ["report_generation.generate", "proposal_generation.generate"])
@pytest.mark.parametrize("text", [None, " \n "])
def test_empty_transcript_does_not_construct_model_client(monkeypatch, module_name, text):
    module = importlib.import_module(module_name)
    req = request()
    if text is None:
        req.transcript.segments = []
    else:
        for segment in req.transcript.segments:
            segment.text = text

    def unexpected(*args, **kwargs):
        pytest.fail("빈 전사로 모델 클라이언트를 만들면 안 됩니다.")

    monkeypatch.setattr(module, "chat_model", unexpected)
    generate = module.generate_report if module_name.startswith("report") else module.generate_proposals
    with pytest.raises(VisitReportError) as exc:
        generate(req, model="gpt-5.6-luna", api_key="synthetic")
    assert exc.value.code == "INVALID_REQUEST"
