import pytest

from card_generation._steps.research.store import _Decision, _topic_state


def test_no_decision_is_zero():
    assert _topic_state([], 0.7) == (0.0, False)


def test_more_decays_by_visits():
    score, excluded = _topic_state([_Decision("more", 2), _Decision("more", 1)], 0.7)
    assert score == pytest.approx(0.49 + 0.7) and excluded is False


def test_one_less_fades_toward_zero():
    assert [_topic_state([_Decision("less", n)], 0.7)[0] for n in range(3)] == pytest.approx([-1.0, -0.7, -0.49])


def test_exclude_wins_over_score():
    assert _topic_state([_Decision("more", 1), _Decision("more", 0), _Decision("exclude", 0)], 0.7) == (0.0, True)


def test_sum_not_mean():
    assert _topic_state([_Decision("more", 0)] * 5, 0.7)[0] > _topic_state([_Decision("more", 0)], 0.7)[0]
