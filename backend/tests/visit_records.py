"""작업 C(평가와 리포트) 테스트가 같이 쓰는 앱과 합성 데이터 준비.

계정, 프로필, 카드 묶음, 회차, 음성 분석 작업, 리포트와 변경 제안을 raw SQL로
만든다. 값은 모두 합성 데이터다. 인증은 `get_current_account`를 바꿔 끼워 건너뛴다.
"""

from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID, uuid4

from fastapi import FastAPI
from httpx import Response
from psycopg.types.json import Jsonb

from app.api.deps import get_current_account, get_image_storage
from app.core.config import Settings, get_settings
from app.core.database import connect
from app.main import create_app
from app.services.accounts import Account
from app.services.image_storage import ImageDownload
from tests.support import request, run

MISSING_ID = "00000000-0000-4000-8000-000000000999"
SHA256 = "a" * 64


class FakeImageStorage:
    def __init__(self) -> None:
        self.downloads: list[str] = []

    async def create_download(self, *, object_key: str) -> ImageDownload:
        self.downloads.append(object_key)
        return ImageDownload(
            url="https://bucket.s3.ap-northeast-2.amazonaws.com/synthetic.jpg",
            expires_at=datetime(2026, 8, 21, 6, 0, tzinfo=UTC),
        )


@dataclass
class Visit:
    """회차 하나와 그 카드. `card_ids`는 position 순서다."""

    profile_id: UUID
    session_id: UUID
    set_id: UUID
    card_ids: list[UUID]
    topic_ids: list[UUID]
    selected: list[UUID] = field(default_factory=list)


class Records:
    """임시 DB에 합성 데이터를 넣고 API를 부른다."""

    def __init__(self, database_url: str) -> None:
        self.database_url = database_url
        self.storage = FakeImageStorage()
        self._account: Account | None = None
        settings = Settings(database_url=database_url, session_secret="s" * 32)
        self.app: FastAPI = create_app()
        self.app.dependency_overrides[get_settings] = lambda: settings
        self.app.dependency_overrides[get_image_storage] = lambda: self.storage

        async def current_account() -> Account:
            assert self._account is not None
            return self._account

        self.app.dependency_overrides[get_current_account] = current_account

    def call(self, account_id: UUID, method: str, path: str, *, json=None) -> Response:
        self._account = Account(
            account_id=str(account_id),
            provider="google",
            social_id="synthetic-sub",
            display_name="합성 보호자",
            email=None,
            consent_version="2026-09-06",
            consents={},
            created_at=datetime(2026, 8, 1, tzinfo=UTC),
        )
        return request(self.app, method, path, json=json)

    def query(self, sql: str, params: tuple = ()) -> list[dict[str, Any]]:
        async def scenario():
            async with connect(self.database_url) as connection:
                cursor = await connection.execute(sql, params)
                return await cursor.fetchall()

        return run(scenario())

    def execute(self, sql: str, params: tuple = ()) -> None:
        async def scenario():
            async with connect(self.database_url) as connection:
                await connection.execute(sql, params)

        run(scenario())

    def scalar(self, sql: str, params: tuple = ()) -> Any:
        return next(iter(self.query(sql, params)[0].values()))

    def account(self) -> tuple[UUID, UUID]:
        """계정과 프로필 하나를 만들어 `(user_id, profile_id)`를 돌려준다."""
        user_id = self.scalar(
            "INSERT INTO users (google_sub) VALUES (%s) RETURNING user_id",
            (f"synthetic-{uuid4().hex}",),
        )
        profile_id = self.scalar(
            "INSERT INTO profiles (user_id, name, gender, birth_date, "
            "condition_stage, occupation, hobby) "
            "VALUES (%s, '합성 이름', 'female', '1943-03-12', 'unknown', "
            "'합성 직업 이야기', '합성 취미 이야기') RETURNING profile_id",
            (user_id,),
        )
        return user_id, profile_id

    def visit(
        self,
        profile_id: UUID,
        *,
        cards: int = 3,
        selected: int = 2,
        started_at: datetime | None = None,
    ) -> Visit:
        """완료된 카드 묶음과 그 묶음을 쓴 회차를 만든다. 앞의 `selected`장을 고른다."""
        session_id = self.scalar(
            "INSERT INTO visit_sessions (profile_id, started_at) "
            "VALUES (%s, %s) RETURNING session_id",
            (profile_id, started_at or datetime.now(UTC)),
        )
        set_id = self.scalar(
            "INSERT INTO card_sets (profile_id, session_id, status, model, "
            "prompt_version, generation_log) "
            "VALUES (%s, %s, 'completed', 'synthetic-model', 'card-v1', %s) "
            "RETURNING set_id",
            (profile_id, session_id, Jsonb({"input": {}})),
        )
        visit = Visit(profile_id, session_id, set_id, [], [])
        for position in range(1, cards + 1):
            topic_id = self.scalar(
                "INSERT INTO profile_topics (profile_id, title, description) "
                "VALUES (%s, %s, %s) RETURNING topic_id",
                (profile_id, f"합성 주제 {position}", f"합성 주제 설명 {position}"),
            )
            card_id = self.scalar(
                "INSERT INTO conversation_cards (set_id, profile_id, topic_id, "
                "card_title, position, description, primary_question, "
                "follow_up_questions, evidence_source, selected) "
                "VALUES (%s, %s, %s, %s, %s, '합성 설명', '합성 질문', "
                "ARRAY['합성 꼬리 질문'], 'none', %s) RETURNING card_id",
                (
                    set_id,
                    profile_id,
                    topic_id,
                    f"합성 카드 {position}",
                    position,
                    position <= selected,
                ),
            )
            visit.card_ids.append(card_id)
            visit.topic_ids.append(topic_id)
            if position <= selected:
                visit.selected.append(card_id)
        return visit

    def evaluate(
        self,
        visit: Visit,
        *,
        satisfaction: int = 4,
        reactions: dict[UUID, str | None] | None = None,
    ) -> None:
        """평가를 DB에 바로 넣는다. `reactions`는 카드별 `review_reaction`이다."""
        self.execute(
            "UPDATE visit_sessions SET evaluation_satisfaction = %s, "
            "evaluation_reaction = 'pleased', evaluated_at = now() "
            "WHERE session_id = %s",
            (satisfaction, visit.session_id),
        )
        for card_id, reaction in (reactions or {}).items():
            self.execute(
                "UPDATE conversation_cards SET review_reaction = %s WHERE card_id = %s",
                (reaction, card_id),
            )

    def job(
        self,
        session_id: UUID,
        status: str,
        *,
        participant_count: int = 2,
        accepted: bool = True,
        created_at: datetime | None = None,
    ) -> UUID:
        """음성 분석 작업 하나. `accepted=False`면 업로드 단계의 작업이다."""
        analysis_id = uuid4()
        uploaded = accepted and status != "uploading"
        leased = status in {"uploading", "transcribing", "generatingReport"}
        transcript = status in {"sttCompleted", "generatingReport"}
        self.execute(
            "INSERT INTO speech_analysis_jobs (analysis_id, session_id, status, "
            "participant_count, s3_object_key, size_bytes, sha256, data_expires_at, "
            "lease_expires_at, error_code, transcript, transcript_expires_at, "
            "created_at) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
            (
                analysis_id,
                session_id,
                status,
                participant_count,
                f"synthetic/{analysis_id}.wav",
                100 if uploaded else None,
                SHA256 if uploaded else None,
                datetime.now(UTC) + timedelta(days=1),
                datetime.now(UTC) + timedelta(hours=1) if leased else None,
                "SYNTHETIC_FAILURE" if status == "failed" else None,
                Jsonb({"durationMs": 0, "segments": []}) if transcript else None,
                datetime.now(UTC) + timedelta(days=1) if transcript else None,
                created_at or datetime.now(UTC),
            ),
        )
        return analysis_id

    def report(self, visit: Visit, *, summaries: dict[UUID, str] | None = None) -> None:
        """평가된 회차에 리포트를 넣는다."""
        self.execute(
            "UPDATE visit_sessions SET report_title = '합성 리포트 제목', "
            "report_body = '합성 리포트 본문', report_model = 'synthetic-model', "
            "report_prompt_version = 'report-v1', report_generated_at = now() "
            "WHERE session_id = %s",
            (visit.session_id,),
        )
        for card_id, summary in (summaries or {}).items():
            self.execute(
                "UPDATE conversation_cards SET report_summary = %s WHERE card_id = %s",
                (summary, card_id),
            )

    def life_fact_proposal(self, visit: Visit, *, title: str = "합성 제안") -> UUID:
        return self.scalar(
            "INSERT INTO life_fact_proposals (session_id, profile_id, title, content, "
            "reason) VALUES (%s, %s, %s, '합성 제안 내용', '합성 이유') "
            "RETURNING proposal_id",
            (visit.session_id, visit.profile_id, title),
        )

    def topic_proposal(self, visit: Visit, card_index: int, action: str = "more") -> UUID:
        return self.scalar(
            "INSERT INTO topic_proposals (session_id, profile_id, card_id, topic_id, "
            "suggested_action, reason) VALUES (%s, %s, %s, %s, %s, '합성 이유') "
            "RETURNING proposal_id",
            (
                visit.session_id,
                visit.profile_id,
                visit.card_ids[card_index],
                visit.topic_ids[card_index],
                action,
            ),
        )
