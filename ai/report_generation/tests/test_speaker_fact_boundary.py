import pytest

from common.speaker_context import speaker_context


@pytest.mark.parametrize("labels,expected,allowed", [
    (["SPEAKER_00", "SPEAKER_01"], 2, True),
    (["SPEAKER_00"], 1, True),
    (["SPEAKER_00"], 2, False),
    ([None], 2, False),
    (["SPEAKER_00", None], 2, False),
    ([" ", "SPEAKER_00"], 1, False),
    (["SPEAKER_00", "SPEAKER_01"], None, True),
    ([], None, False),
])
def test_candidate_gate_does_not_invent_speaker_roles(labels, expected, allowed):
    context = speaker_context(labels, expected)
    assert context["life_fact_proposals_allowed"] is allowed
    assert context["speaker_roles_verified"] is False
