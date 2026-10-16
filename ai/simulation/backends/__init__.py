"""시뮬레이터의 백엔드 역할. 추천을 부르고 PR #84 테이블에 쓰는 일을 맡는다.

실제 서비스에서는 backend가 할 일. card_generation은 DB를 읽거나 쓰지 않고, 카드 묶음·카드·결정 저장은 여기서 함.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

import psycopg

from common.llm import ChatConfig

OWN = "profile_id = %(pid)s"


class Backend:
    name: str
    label: str
    recommend_errors: tuple[type[Exception], ...] = ()
    snapshot_tables: list[tuple[str, tuple[str, ...], str]] = []
    prompt_files: dict[str, str] = {}  # 화면 이름 → 프로젝트 기준 경로

    def prepare(self, conn: psycopg.Connection) -> None:
        """실행 전에 필요한 테이블을 만든다."""

    def store(self, conn: psycopg.Connection, pid: str) -> Any:
        raise NotImplementedError

    def recommend(self, url: str, pid: str, config: ChatConfig, model) -> tuple[list[dict[str, Any]], dict[str, Any]]:
        raise NotImplementedError

    def card_names(self, card: dict[str, Any]) -> list[str]:
        """보호자 화면에서 카드에 보이는 주제·요소 이름."""
        raise NotImplementedError

    def output_card(self, card: dict[str, Any]) -> dict[str, Any]:
        """실시간 화면에 보낼 카드의 주제·요소 표시."""
        raise NotImplementedError

    def attach_cards(self, rw: psycopg.Connection, session: Any, cards: list[dict[str, Any]], summaries: dict[int, str]) -> None:
        raise NotImplementedError

    def apply_adjustment(self, rw: psycopg.Connection, pid: str, session: Any, decided_at: datetime,
                         card: dict[str, Any], t: dict[str, Any], d) -> dict[str, Any] | None:
        """주제 조정 하나를 저장한다. 보호자가 빼면 None."""
        raise NotImplementedError

    def strip(self, card: dict[str, Any]) -> dict[str, Any]:
        """결과 JSON에 남길 카드(내부 ID 뺌)."""
        raise NotImplementedError

    def state(self, url: str, pid: str) -> dict[str, Any]:
        raise NotImplementedError

    def size_units(self, run: dict[str, Any]) -> list[dict[str, Any]]:
        """주제 크기 평가에 넣을 단위(title, description, visits, actions)."""
        raise NotImplementedError


def get_backend(name: str) -> Backend:
    if name == "topics":
        from .topics import TopicsBackend
        return TopicsBackend()
    raise ValueError("추천 판은 topics뿐이다")


def recommender_of(run: dict[str, Any]) -> str:
    """결과 JSON이 어느 판인지. 요소판을 지운 뒤로는 topics뿐이다."""
    return run.get("recommender") or "topics"
