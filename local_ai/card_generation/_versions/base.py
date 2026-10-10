"""판 하나가 갖는 값의 형식. 판마다 프롬프트와 정해 둔 값이 함께 바뀜."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class SelectionRules:
    """③ 선정 규칙. 판마다 값을 정함."""
    card_count: int        # 12장. API 명세 4절(#87)
    min_new: int           # 새 이야기를 먼저 잡아 두는 장수
    temperature: float     # 낮으면 점수 높은 주제로 쏠림, 높으면 고르게 뽑힘

    def __post_init__(self) -> None:
        """temperature가 0 이하면 softmax를 계산할 수 없어 막음."""
        if self.temperature <= 0:
            raise ValueError("temperature는 0보다 커야 한다")


@dataclass(frozen=True)
class Version:
    """판 하나. 프롬프트 폴더와 정해 둔 값을 묶음. backend가 보낸 promptVersion이 number와 같은 판을 씀."""
    number: int            # backend가 보내는 promptVersion
    prompts: Path
    min_candidates: int    # 에이전트가 내는 후보 수 하한
    max_candidates: int
    min_topics: int        # 후보 안의 서로 다른 주제 수
    max_per_topic: int     # 한 주제에 낼 수 있는 후보 수
    min_new_topics: int    # 기존 주제에 연결하지 않은 새 주제 수
    decay: float           # 면회 한 번이 지날 때마다 결정의 무게에 곱하는 값
    selection: SelectionRules

    def _read(self, name: str) -> str:
        """이 판의 prompts 폴더에서 파일 하나를 읽음."""
        return (self.prompts / name).read_text()

    def agent_prompt(self) -> str:
        """① 조사 에이전트의 시스템 프롬프트. same_story.md와 새 주제 최소 수를 끼워 넣음."""
        return self._read("agent.md").replace("{same_story}", self._read("same_story.md").strip()) \
            .replace("{min_new_topics}", str(self.min_new_topics))

    def match_prompt(self) -> str:
        """② 연결 판정의 시스템 프롬프트. same_story.md를 끼워 넣음."""
        return self._read("match.md").replace("{same_story}", self._read("same_story.md").strip())

    def writing_prompt(self) -> str:
        """④ 문안 작성의 시스템 프롬프트."""
        return self._read("writing_topics.md")
