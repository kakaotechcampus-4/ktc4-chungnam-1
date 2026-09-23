from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass
import unicodedata

from ai.stt.schemas import (
    AsrResult,
    AsrWord,
    DiarizationResult,
    DiarizationSegment,
    SpeakerTranscriptSegment,
    SpeechAnalysisResult,
)


@dataclass(frozen=True)
class _AlignmentUnit:
    """화자 구간에 배정할 최소 전사 단위."""

    start_ms: int
    end_ms: int
    text: str
    source_segment_index: int
    source_order: int
    word: AsrWord | None

    @property
    def is_segment_fallback(self) -> bool:
        return self.word is None


@dataclass
class _SegmentBuilder:
    key: tuple[object, ...]
    speaker_label: str | None
    units: list[_AlignmentUnit]


def align_asr_and_diarization(
    asr_result: AsrResult,
    diarization_result: DiarizationResult,
) -> SpeechAnalysisResult:
    """ASR 단어를 가장 오래 겹치는 exclusive 화자 구간에 배정한다.

    단어 타임스탬프가 없는 ASR 구간은 구간 전체를 하나의 fallback 단위로
    정렬한다. 서로 다른 화자와 같은 시간만큼 겹치거나 어떤 화자 구간과도
    겹치지 않는 단위에는 화자를 임의로 지정하지 않는다.
    """

    units = _build_alignment_units(asr_result)
    exclusive_segments = sorted(
        diarization_result.exclusive_segments,
        key=lambda segment: (segment.start_ms, segment.end_ms, segment.speaker),
    )
    assignments = _assign_units(units, exclusive_segments)
    builders: list[_SegmentBuilder] = []

    for unit, assigned_index in zip(units, assignments, strict=True):
        speaker_label = (
            exclusive_segments[assigned_index].speaker
            if assigned_index is not None
            else None
        )
        key = _group_key(unit, assigned_index)

        if not builders or builders[-1].key != key:
            builders.append(
                _SegmentBuilder(
                    key=key,
                    speaker_label=speaker_label,
                    units=[unit],
                )
            )
        else:
            builders[-1].units.append(unit)

    return SpeechAnalysisResult(
        analysisId=asr_result.analysis_id,
        language=asr_result.language,
        durationMs=asr_result.duration_ms,
        text=asr_result.text,
        segments=[_build_speaker_segment(builder) for builder in builders],
    )


def _build_alignment_units(asr_result: AsrResult) -> list[_AlignmentUnit]:
    units: list[_AlignmentUnit] = []
    source_order = 0

    for segment_index, segment in enumerate(asr_result.segments):
        if segment.words:
            for word in segment.words:
                units.append(
                    _AlignmentUnit(
                        start_ms=word.start_ms,
                        end_ms=word.end_ms,
                        text=word.text.strip(),
                        source_segment_index=segment_index,
                        source_order=source_order,
                        word=word,
                    )
                )
                source_order += 1
        elif segment.text.strip():
            units.append(
                _AlignmentUnit(
                    start_ms=segment.start_ms,
                    end_ms=segment.end_ms,
                    text=segment.text.strip(),
                    source_segment_index=segment_index,
                    source_order=source_order,
                    word=None,
                )
            )
            source_order += 1

    return sorted(
        units,
        key=lambda unit: (unit.start_ms, unit.end_ms, unit.source_order),
    )


def _assign_units(
    units: list[_AlignmentUnit],
    diarization_segments: list[DiarizationSegment],
) -> list[int | None]:
    assignments: list[int | None] = []
    first_candidate = 0

    for unit in units:
        while (
            first_candidate < len(diarization_segments)
            and diarization_segments[first_candidate].end_ms <= unit.start_ms
        ):
            first_candidate += 1

        best_overlap_ms = 0
        best_indices: list[int] = []
        candidate_index = first_candidate

        while candidate_index < len(diarization_segments):
            segment = diarization_segments[candidate_index]
            if segment.start_ms >= unit.end_ms:
                break

            overlap_ms = max(
                0,
                min(unit.end_ms, segment.end_ms)
                - max(unit.start_ms, segment.start_ms),
            )
            if overlap_ms > best_overlap_ms:
                best_overlap_ms = overlap_ms
                best_indices = [candidate_index]
            elif overlap_ms > 0 and overlap_ms == best_overlap_ms:
                best_indices.append(candidate_index)
            candidate_index += 1

        if not best_indices:
            assignments.append(None)
            continue

        best_speakers = {
            diarization_segments[index].speaker for index in best_indices
        }
        assignments.append(best_indices[0] if len(best_speakers) == 1 else None)

    return assignments


def _group_key(
    unit: _AlignmentUnit,
    assigned_index: int | None,
) -> tuple[object, ...]:
    if assigned_index is None:
        return ("unassigned", unit.source_segment_index)
    if unit.is_segment_fallback:
        return ("fallback", assigned_index, unit.source_segment_index)
    return ("diarization", assigned_index)


def _build_speaker_segment(builder: _SegmentBuilder) -> SpeakerTranscriptSegment:
    units = builder.units
    return SpeakerTranscriptSegment(
        startMs=min(unit.start_ms for unit in units),
        endMs=max(unit.end_ms for unit in units),
        speakerLabel=builder.speaker_label,
        text=_join_text(unit.text for unit in units),
        words=[unit.word for unit in units if unit.word is not None],
    )


def _join_text(parts: Iterable[str]) -> str:
    result = ""
    opening_punctuation = {"(", "[", "{", "‘", "“"}

    for raw_part in parts:
        part = str(raw_part).strip()
        if not part:
            continue
        if not result:
            result = part
            continue

        first_category = unicodedata.category(part[0])
        has_no_leading_space = (
            first_category.startswith("P")
            and part[0] not in opening_punctuation
        )
        if has_no_leading_space or result[-1] in opening_punctuation:
            result += part
        else:
            result += f" {part}"

    return result
