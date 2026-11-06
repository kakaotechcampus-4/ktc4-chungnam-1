import pytest

from common.speaker_context import speaker_context


@pytest.mark.parametrize("labels,expected", [
    (["SPEAKER_00", "SPEAKER_01"], 2),
    (["SPEAKER_00"], 1),
    (["SPEAKER_00"], 2),
    ([None], 2),
    (["SPEAKER_00", None], 2),
    ([" ", "SPEAKER_00"], 1),
    (["SPEAKER_00", "SPEAKER_01"], None),
    ([], None),
])
def test_context_does_not_gate_candidates_or_invent_roles(labels, expected):
    context = speaker_context(labels, expected)
    assert "life_fact_proposals_allowed" not in context
    assert context["expected_participant_count"] == expected
    assert context["speaker_roles_verified"] is False
