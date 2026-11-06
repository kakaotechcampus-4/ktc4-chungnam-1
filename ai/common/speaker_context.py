"""라벨 누락을 계산한다. 라벨만으로 보호자와 어르신의 역할을 정하지 않는다."""

from collections.abc import Sequence


def speaker_context(labels: Sequence[str | None], expected: int | None) -> dict:
    normalized = [label.strip() if label else None for label in labels]
    known = {label for label in normalized if label}
    unassigned = any(not label for label in normalized)
    fewer = expected is not None and len(known) < expected
    return {
        "expected_participant_count": expected,
        "observed_speaker_label_count": len(known),
        "has_unassigned_speech": unassigned,
        "fewer_labels_than_expected": fewer,
        "speaker_roles_verified": False,
    }
