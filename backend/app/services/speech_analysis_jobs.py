from __future__ import annotations

import asyncio
from collections.abc import Mapping
from dataclasses import dataclass, replace
from datetime import UTC, datetime, timedelta
from enum import StrEnum
from typing import Any, Protocol
from uuid import UUID

from psycopg.types.json import Jsonb

from app.core.database import DbConnection
from app.core.errors import AppError
from app.workers.base import LEASE_EXPIRED_ERROR

# 전사문은 리포트 생성을 다시 시도할 때 STT를 반복하지 않도록 작업에 임시 저장한다.
# 리포트를 저장하면 지우고, 늦어도 STT 완료 후 이 시간이 지나면 지운다(API 8-1).
TRANSCRIPT_RETENTION_SECONDS = 24 * 60 * 60


class SpeechAnalysisStatus(StrEnum):
    UPLOADING = "uploading"
    QUEUED = "queued"
    TRANSCRIBING = "transcribing"
    STT_COMPLETED = "sttCompleted"
    GENERATING_REPORT = "generatingReport"
    COMPLETED = "completed"
    FAILED = "failed"


@dataclass(frozen=True)
class SpeechAnalysisJob:
    analysis_id: str
    session_id: str
    status: SpeechAnalysisStatus
    participant_count: int
    object_key: str
    data_expires_at: datetime
    size_bytes: int | None = None
    sha256: str | None = None
    error_code: str | None = None
    audio_deleted_at: datetime | None = None
    stt_completed_at: datetime | None = None


class SpeechAnalysisJobRepository(Protocol):
    async def assert_session_access(
        self,
        *,
        account_id: str,
        session_id: str,
    ) -> None: ...

    async def reserve(
        self,
        job: SpeechAnalysisJob,
    ) -> tuple[SpeechAnalysisJob, bool]: ...

    async def mark_queued(
        self,
        *,
        analysis_id: str,
        size_bytes: int,
        sha256: str,
    ) -> SpeechAnalysisJob: ...

    async def discard_upload(self, *, analysis_id: str) -> None: ...

    async def get_for_account(
        self,
        *,
        analysis_id: str,
        account_id: str,
    ) -> SpeechAnalysisJob | None: ...

    async def claim_next(self, *, lease_seconds: int) -> SpeechAnalysisJob | None: ...

    async def mark_generating_report(self, *, analysis_id: str) -> None: ...

    async def mark_stt_completed(
        self, *, analysis_id: str, transcript: Mapping[str, Any]
    ) -> None: ...

    async def mark_completed(self, *, analysis_id: str) -> None: ...

    async def mark_failed(self, *, analysis_id: str, error_code: str) -> None: ...

    async def mark_audio_deleted(self, *, analysis_id: str) -> None: ...

    async def expire_transcripts(self) -> int:
        """보관 기한이 지난 전사문을 지우고 그 작업을 실패로 바꾼다."""
        ...

    async def expire_leases(self) -> int:
        """임대 시간 안에 끝나지 않은 작업을 정리한다."""
        ...


class InMemorySpeechAnalysisJobRepository:
    """합성 데이터 테스트와 로컬 계약 검증용 저장소.

    `allow_session` 으로 등록한 회차는 그 계정이 소유하고 보호자 평가를 마친 회차로
    본다. 전사문은 보관하지 않는다.
    """

    def __init__(self) -> None:
        self._jobs: dict[str, SpeechAnalysisJob] = {}
        self._by_session: dict[str, str] = {}
        self._sessions: dict[str, str] = {}
        self._lock = asyncio.Lock()

    def allow_session(self, *, account_id: str, session_id: str) -> None:
        self._sessions[session_id] = account_id

    async def assert_session_access(
        self,
        *,
        account_id: str,
        session_id: str,
    ) -> None:
        if self._sessions.get(session_id) != account_id:
            raise AppError(
                status_code=404,
                error_code="VISIT_SESSION_NOT_FOUND",
                message="면회 기록을 찾을 수 없습니다.",
            )

    async def reserve(
        self,
        job: SpeechAnalysisJob,
    ) -> tuple[SpeechAnalysisJob, bool]:
        async with self._lock:
            existing_id = self._by_session.get(job.session_id)
            if existing_id is not None:
                return self._jobs[existing_id], False
            self._jobs[job.analysis_id] = job
            self._by_session[job.session_id] = job.analysis_id
            return job, True

    async def mark_queued(
        self,
        *,
        analysis_id: str,
        size_bytes: int,
        sha256: str,
    ) -> SpeechAnalysisJob:
        job = replace(
            self._jobs[analysis_id],
            status=SpeechAnalysisStatus.QUEUED,
            size_bytes=size_bytes,
            sha256=sha256,
        )
        self._jobs[analysis_id] = job
        return job

    async def discard_upload(self, *, analysis_id: str) -> None:
        job = self._jobs.get(analysis_id)
        if job is None or job.status != SpeechAnalysisStatus.UPLOADING:
            return
        self._jobs.pop(analysis_id, None)
        self._by_session.pop(job.session_id, None)

    async def get_for_account(
        self,
        *,
        analysis_id: str,
        account_id: str,
    ) -> SpeechAnalysisJob | None:
        job = self._jobs.get(analysis_id)
        if job is None or self._sessions.get(job.session_id) != account_id:
            return None
        return job

    async def claim_next(self, *, lease_seconds: int) -> SpeechAnalysisJob | None:
        del lease_seconds
        async with self._lock:
            job = next(
                (
                    item
                    for item in self._jobs.values()
                    if item.status == SpeechAnalysisStatus.QUEUED
                ),
                None,
            )
            if job is None:
                return None
            claimed = replace(job, status=SpeechAnalysisStatus.TRANSCRIBING)
            self._jobs[job.analysis_id] = claimed
            return claimed

    async def mark_generating_report(self, *, analysis_id: str) -> None:
        self._set_status(analysis_id, SpeechAnalysisStatus.GENERATING_REPORT)

    async def mark_stt_completed(
        self, *, analysis_id: str, transcript: Mapping[str, Any]
    ) -> None:
        del transcript
        self._jobs[analysis_id] = replace(
            self._jobs[analysis_id],
            status=SpeechAnalysisStatus.STT_COMPLETED,
            stt_completed_at=datetime.now(UTC),
        )

    async def mark_completed(self, *, analysis_id: str) -> None:
        self._set_status(analysis_id, SpeechAnalysisStatus.COMPLETED)

    async def mark_failed(self, *, analysis_id: str, error_code: str) -> None:
        self._jobs[analysis_id] = replace(
            self._jobs[analysis_id],
            status=SpeechAnalysisStatus.FAILED,
            error_code=error_code,
        )

    async def mark_audio_deleted(self, *, analysis_id: str) -> None:
        self._jobs[analysis_id] = replace(
            self._jobs[analysis_id],
            audio_deleted_at=datetime.now(UTC),
        )

    async def expire_transcripts(self) -> int:
        return 0

    async def expire_leases(self) -> int:
        return 0

    def _set_status(
        self,
        analysis_id: str,
        status: SpeechAnalysisStatus,
    ) -> None:
        self._jobs[analysis_id] = replace(self._jobs[analysis_id], status=status)


class PostgresSpeechAnalysisJobRepository:
    """PostgreSQL 행 잠금으로 작업을 하나씩 임대하는 저장소.

    바깥에서 받은 비동기 연결을 쓴다(API는 `DbConnectionDep`, worker는 골격이 연다).
    연결은 autocommit이므로 여러 문장을 함께 반영할 때만 트랜잭션 블록으로 묶는다.
    """

    def __init__(self, connection: DbConnection, *, lease_seconds: int) -> None:
        self._connection = connection
        # 업로드와 리포트 생성 단계의 작업 임대 시간. 전사 단계는 worker가 정한다.
        self._lease_seconds = lease_seconds

    async def assert_session_access(
        self,
        *,
        account_id: str,
        session_id: str,
    ) -> None:
        try:
            owner_id = UUID(account_id)
            visit_id = UUID(session_id)
        except ValueError as error:
            raise _session_not_found() from error

        cursor = await self._connection.execute(
            """
            SELECT visit.evaluated_at
              FROM visit_sessions AS visit
              JOIN profiles AS profile ON profile.profile_id = visit.profile_id
             WHERE visit.session_id = %s AND profile.user_id = %s
            """,
            (visit_id, owner_id),
        )
        session = await cursor.fetchone()
        if session is None:
            raise _session_not_found()
        if session["evaluated_at"] is None:
            raise AppError(
                status_code=409,
                error_code="EVALUATION_REQUIRED",
                message="보호자 평가를 먼저 제출해 주세요.",
            )

    async def reserve(
        self,
        job: SpeechAnalysisJob,
    ) -> tuple[SpeechAnalysisJob, bool]:
        session_id = UUID(job.session_id)
        async with self._connection.transaction():
            # 접수 후 실패한 회차는 다시 받지 않는다. 업로드 단계의 실패는 작업을
            # 지우므로(`discard_upload`) 남은 실패 작업은 모두 접수된 작업이다.
            cursor = await self._connection.execute(
                """
                SELECT * FROM speech_analysis_jobs
                 WHERE session_id = %s AND status = 'failed'
                   AND size_bytes IS NOT NULL
                 ORDER BY created_at DESC
                 LIMIT 1
                """,
                (session_id,),
            )
            failed = await cursor.fetchone()
            if failed is not None:
                return self._from_row(failed), False
            cursor = await self._connection.execute(
                """
                INSERT INTO speech_analysis_jobs
                    (analysis_id, session_id, status, participant_count,
                     s3_object_key, data_expires_at, lease_expires_at)
                VALUES (%s, %s, 'uploading', %s, %s, %s,
                        now() + (%s * interval '1 second'))
                ON CONFLICT (session_id) WHERE status <> 'failed' DO NOTHING
                RETURNING *
                """,
                (
                    UUID(job.analysis_id),
                    session_id,
                    job.participant_count,
                    job.object_key,
                    job.data_expires_at,
                    self._lease_seconds,
                ),
            )
            row = await cursor.fetchone()
            if row is not None:
                return self._from_row(row), True
            cursor = await self._connection.execute(
                """
                SELECT * FROM speech_analysis_jobs
                 WHERE session_id = %s AND status <> 'failed'
                """,
                (session_id,),
            )
            existing = await cursor.fetchone()
        if existing is None:
            # 충돌한 작업이 그 사이 실패로 바뀐 경우다. 접수했다고 꾸미지 않는다.
            raise RuntimeError("충돌한 음성 분석 작업을 다시 읽지 못했습니다.")
        return self._from_row(existing), False

    async def mark_queued(
        self,
        *,
        analysis_id: str,
        size_bytes: int,
        sha256: str,
    ) -> SpeechAnalysisJob:
        cursor = await self._connection.execute(
            """
            UPDATE speech_analysis_jobs
               SET status = 'queued', size_bytes = %s, sha256 = %s,
                   lease_expires_at = NULL, updated_at = now()
             WHERE analysis_id = %s AND status = 'uploading'
            RETURNING *
            """,
            (size_bytes, sha256, UUID(analysis_id)),
        )
        row = await cursor.fetchone()
        if row is None:
            raise RuntimeError("업로드 중인 음성 분석 작업을 찾을 수 없습니다.")
        return self._from_row(row)

    async def get_for_account(
        self,
        *,
        analysis_id: str,
        account_id: str,
    ) -> SpeechAnalysisJob | None:
        try:
            analysis_uuid = UUID(analysis_id)
            account_uuid = UUID(account_id)
        except ValueError:
            return None
        cursor = await self._connection.execute(
            """
            SELECT job.*
              FROM speech_analysis_jobs AS job
              JOIN visit_sessions AS visit ON visit.session_id = job.session_id
              JOIN profiles AS profile ON profile.profile_id = visit.profile_id
             WHERE job.analysis_id = %s AND profile.user_id = %s
            """,
            (analysis_uuid, account_uuid),
        )
        row = await cursor.fetchone()
        return self._from_row(row) if row is not None else None

    async def discard_upload(self, *, analysis_id: str) -> None:
        await self._connection.execute(
            """
            DELETE FROM speech_analysis_jobs
             WHERE analysis_id = %s AND status = 'uploading'
            """,
            (UUID(analysis_id),),
        )

    async def claim_next(self, *, lease_seconds: int) -> SpeechAnalysisJob | None:
        cursor = await self._connection.execute(
            """
            WITH candidate AS (
                SELECT analysis_id
                  FROM speech_analysis_jobs
                 WHERE status = 'queued'
                 ORDER BY created_at
                 FOR UPDATE SKIP LOCKED
                 LIMIT 1
            )
            UPDATE speech_analysis_jobs AS job
               SET status = 'transcribing',
                   attempt_count = attempt_count + 1,
                   lease_expires_at = now() + (%s * interval '1 second'),
                   updated_at = now()
              FROM candidate
             WHERE job.analysis_id = candidate.analysis_id
            RETURNING job.*
            """,
            (lease_seconds,),
        )
        row = await cursor.fetchone()
        return self._from_row(row) if row is not None else None

    async def mark_generating_report(self, *, analysis_id: str) -> None:
        await self._set_status(
            analysis_id, SpeechAnalysisStatus.GENERATING_REPORT, None
        )

    async def mark_stt_completed(
        self, *, analysis_id: str, transcript: Mapping[str, Any]
    ) -> None:
        await self._connection.execute(
            """
            UPDATE speech_analysis_jobs
               SET status = 'sttCompleted', stt_completed_at = now(),
                   transcript = %s,
                   transcript_expires_at = now() + (%s * interval '1 second'),
                   lease_expires_at = NULL, updated_at = now()
             WHERE analysis_id = %s AND status = 'transcribing'
            """,
            (
                Jsonb(dict(transcript)),
                TRANSCRIPT_RETENTION_SECONDS,
                UUID(analysis_id),
            ),
        )

    async def mark_completed(self, *, analysis_id: str) -> None:
        await self._set_status(analysis_id, SpeechAnalysisStatus.COMPLETED, None)

    async def mark_failed(self, *, analysis_id: str, error_code: str) -> None:
        await self._set_status(analysis_id, SpeechAnalysisStatus.FAILED, error_code)

    async def _set_status(
        self,
        analysis_id: str,
        status: SpeechAnalysisStatus,
        error_code: str | None,
    ) -> None:
        # 회차 상태는 저장하지 않고 작업 상태로 계산하므로 회차는 바꾸지 않는다.
        # 리포트 생성 단계는 임대가 필요하고, 끝난 작업에는 전사문을 남기지 않는다.
        await self._connection.execute(
            """
            UPDATE speech_analysis_jobs
               SET status = %(status)s::text, error_code = %(error_code)s,
                   lease_expires_at = CASE
                       WHEN %(status)s::text = 'generatingReport'
                       THEN now() + (%(lease_seconds)s * interval '1 second')
                   END,
                   transcript = CASE
                       WHEN %(status)s::text IN ('completed', 'failed') THEN NULL
                       ELSE transcript
                   END,
                   transcript_deleted_at = CASE
                       WHEN %(status)s::text IN ('completed', 'failed')
                            AND transcript IS NOT NULL THEN now()
                       ELSE transcript_deleted_at
                   END,
                   completed_at = CASE
                       WHEN %(status)s::text IN ('completed', 'failed') THEN now()
                       ELSE completed_at
                   END,
                   updated_at = now()
             WHERE analysis_id = %(analysis_id)s
            """,
            {
                "status": status.value,
                "error_code": error_code,
                "lease_seconds": self._lease_seconds,
                "analysis_id": UUID(analysis_id),
            },
        )

    async def mark_audio_deleted(self, *, analysis_id: str) -> None:
        await self._connection.execute(
            """
            UPDATE speech_analysis_jobs
               SET audio_deleted_at = now(), updated_at = now()
             WHERE analysis_id = %s
            """,
            (UUID(analysis_id),),
        )

    async def expire_transcripts(self) -> int:
        # 리포트를 저장하기 전에 보관 기한이 지났다. 전사문 없이는 리포트를 만들 수
        # 없으므로 작업을 실패로 끝낸다.
        cursor = await self._connection.execute(
            """
            UPDATE speech_analysis_jobs
               SET status = 'failed', error_code = 'TRANSCRIPT_EXPIRED',
                   transcript = NULL, transcript_deleted_at = now(),
                   lease_expires_at = NULL, completed_at = now(),
                   updated_at = now()
             WHERE transcript IS NOT NULL AND transcript_expires_at <= now()
            """
        )
        return cursor.rowcount

    async def expire_leases(self) -> int:
        async with self._connection.transaction():
            # 업로드 중에 멈춘 작업은 접수 전 실패와 같으므로 지운다. 같은 음성을 다시
            # 제출할 수 있고, trigger가 원본 키를 S3 삭제 대기열에 넣는다.
            uploading = await self._connection.execute(
                """
                DELETE FROM speech_analysis_jobs
                 WHERE status = 'uploading' AND lease_expires_at <= now()
                """
            )
            # 처리 중에 멈춘 작업은 실패로 끝낸다. 남은 원본은 S3 Lifecycle이 지운다.
            processing = await self._connection.execute(
                """
                UPDATE speech_analysis_jobs
                   SET status = 'failed', error_code = %s,
                       transcript = NULL,
                       transcript_deleted_at = CASE
                           WHEN transcript IS NOT NULL THEN now()
                           ELSE transcript_deleted_at
                       END,
                       lease_expires_at = NULL, completed_at = now(),
                       updated_at = now()
                 WHERE status IN ('transcribing', 'generatingReport')
                   AND lease_expires_at <= now()
                """,
                (LEASE_EXPIRED_ERROR,),
            )
        return uploading.rowcount + processing.rowcount

    @staticmethod
    def _from_row(row: Mapping[str, Any]) -> SpeechAnalysisJob:
        return SpeechAnalysisJob(
            analysis_id=str(row["analysis_id"]),
            session_id=str(row["session_id"]),
            status=SpeechAnalysisStatus(row["status"]),
            participant_count=row["participant_count"],
            object_key=row["s3_object_key"],
            data_expires_at=row["data_expires_at"],
            size_bytes=row["size_bytes"],
            sha256=row["sha256"],
            error_code=row["error_code"],
            audio_deleted_at=row["audio_deleted_at"],
            stt_completed_at=row["stt_completed_at"],
        )


def _session_not_found() -> AppError:
    return AppError(
        status_code=404,
        error_code="VISIT_SESSION_NOT_FOUND",
        message="면회 기록을 찾을 수 없습니다.",
    )
