"""음성 분석 한 건의 처리 기록(로그 한 줄).

PM 결정(2026-11-09): 음성 분석이 끝나거나 실패하면 그 작업의 처리 규모를 숫자로 한 줄 남긴다.
전사가 녹음보다 일찍 끊겼는지(마지막 구간이 끝난 시각과 녹음 길이), 이야기 후보가 몇 개 나와 몇 개
남았는지를 운영 로그만으로 보려는 것이다.

- 남기는 것: 작업 ID, STT 서버(`primary`, `backup`), 녹음 길이(초), 전사 구간 수와 글자 수, 마지막
  구간이 끝난 시각(초), 서로 다른 화자 라벨 수, 리포트 본문 글자 수, 이야기 후보 수(모델이 낸 수와
  남은 수), 분류별 수, 아픈 기억 표시 수, 주제 조정 수(모델이 낸 수와 남은 수), 모델과 프롬프트 판,
  토큰 수, 결과(`outcome`)와 실패 코드.
- 남기지 않는 것: 전사, 리포트 본문, 제목, 이유, 이름 같은 글. 화자 라벨도 개수만 남긴다.
- 모르는 값은 `null`이다. 리포트만 다시 만드는 작업(`generatingReport` 이어받기)은 저장된 전사를
  쓰므로 STT 서버가 `null`이고, STT에서 실패하면 리포트 쪽 값이 `null`이다. 모델이 낸 수는 ai 패키지를
  감싼 생성 함수만 알려 준다.
- "남은 수"는 AI 쪽에서 거르고 자른 뒤 8-3 결과에 담긴 수다. `outcome`이 `completed`일 때만 그대로
  저장됐다는 뜻이다.

`outcome`
- `completed`: 리포트까지 저장하고 작업을 끝냈다.
- `sttCompleted`: 리포트 생성기 없이 돌린 worker(`--stt-only`)라 전사에서 멈췄다.
- `stopped`: 다른 처리(임대 만료 정리 등)가 먼저 끝낸 작업이라 이어 가지 않았다.
- `failed`: 처리 중 오류로 작업을 실패로 남긴다. `error_code`가 작업의 실패 코드다.
"""

from __future__ import annotations

import logging
from collections import Counter
from dataclasses import asdict, dataclass
from typing import Literal

from app.schemas.speech_analysis import SpeechAnalysisResult
from app.schemas.visit_report_generation import VisitReportResult

logger = logging.getLogger("saerok.speech_analysis")

Outcome = Literal["completed", "sttCompleted", "stopped", "failed"]


def _seconds(milliseconds: int) -> float:
    return round(milliseconds / 1000, 1)


@dataclass
class SpeechAnalysisStats:
    """작업 하나를 처리하는 동안 숫자를 모은다. 글은 받아도 길이와 개수만 남긴다."""

    analysis_id: str
    stt_server: str | None = None
    audio_seconds: float | None = None
    transcript_segments: int | None = None
    transcript_chars: int | None = None
    last_segment_end_seconds: float | None = None
    speaker_labels: int | None = None
    report_body_chars: int | None = None
    life_story_proposals_returned: int | None = None
    life_story_proposals_kept: int | None = None
    story_categories: dict[str, int] | None = None
    sensitive_proposals: int | None = None
    topic_proposals_returned: int | None = None
    topic_proposals_kept: int | None = None
    model: str | None = None
    prompt_version: str | None = None
    token_usage: dict[str, int] | None = None

    def record_transcript(self, speech: SpeechAnalysisResult) -> None:
        segments = speech.segments
        self.stt_server = speech.stt_server
        self.audio_seconds = _seconds(speech.duration_ms)
        self.transcript_segments = len(segments)
        self.transcript_chars = sum(len(segment.text) for segment in segments)
        self.last_segment_end_seconds = (
            _seconds(max(segment.end_ms for segment in segments)) if segments else None
        )
        self.speaker_labels = len(
            {segment.speaker_label for segment in segments if segment.speaker_label is not None}
        )

    def record_report(self, result: VisitReportResult) -> None:
        """8-3 결과를 받은 직전에 부른다. 검증이나 저장에서 실패해도 받은 결과의 숫자는 남는다."""
        proposals = result.life_fact_proposals
        counts = result.counts
        self.report_body_chars = len(result.body)
        self.life_story_proposals_returned = counts.life_fact_proposals_returned
        self.life_story_proposals_kept = len(proposals)
        self.story_categories = dict(
            sorted(Counter(proposal.story_category for proposal in proposals).items())
        )
        self.sensitive_proposals = sum(proposal.sensitive for proposal in proposals)
        self.topic_proposals_returned = counts.topic_proposals_returned
        self.topic_proposals_kept = len(result.topic_proposals)
        self.model = result.model
        self.prompt_version = result.prompt_version
        self.token_usage = dict(counts.token_usage) or None

    def emit(self, outcome: Outcome, *, error_code: str | None = None) -> None:
        logger.info(
            "speech_analysis_finished",
            extra={"outcome": outcome, "error_code": error_code, **asdict(self)},
        )
