from __future__ import annotations

import asyncio
from dataclasses import dataclass, replace
from datetime import UTC, datetime, timedelta
from enum import StrEnum
from typing import Protocol
from uuid import UUID

import psycopg
from psycopg.rows import dict_row

from app.core.errors import AppError


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

    async def mark_stt_completed(self, *, analysis_id: str) -> None: ...

    async def mark_completed(self, *, analysis_id: str) -> None: ...

    async def mark_failed(self, *, analysis_id: str, error_code: str) -> None: ...

    async def mark_audio_deleted(self, *, analysis_id: str) -> None: ...


class InMemorySpeechAnalysisJobRepository:
    """합성 데이터 테스트와 로컬 계약 검증용 저장소."""

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

    async def mark_stt_completed(self, *, analysis_id: str) -> None:
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

    def _set_status(
        self,
        analysis_id: str,
        status: SpeechAnalysisStatus,
    ) -> None:
        self._jobs[analysis_id] = replace(self._jobs[analysis_id], status=status)


class PostgresSpeechAnalysisJobRepository:
    """PostgreSQL 행 잠금으로 작업을 하나씩 임대하는 저장소."""

    def __init__(self, database_url: str) -> None:
        self._dsn = database_url.replace(
            "postgresql+psycopg://", "postgresql://"
        )

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
            raise AppError(
                status_code=404,
                error_code="VISIT_SESSION_NOT_FOUND",
                message="면회 기록을 찾을 수 없습니다.",
            ) from error

        found = await asyncio.to_thread(self._session_is_allowed, owner_id, visit_id)
        if not found:
            raise AppError(
                status_code=404,
                error_code="VISIT_SESSION_NOT_FOUND",
                message="면회 기록을 찾을 수 없습니다.",
            )

    def _session_is_allowed(self, account_id: UUID, session_id: UUID) -> bool:
        with psycopg.connect(self._dsn) as connection:
            row = connection.execute(
                """
                SELECT 1
                  FROM visit_sessions AS visit
                  JOIN profiles AS profile ON profile.profile_id = visit.profile_id
                 WHERE visit.session_id = %s
                   AND profile.user_id = %s
                   AND (
                       visit.session_status = 'ended'
                       OR EXISTS (
                           SELECT 1 FROM speech_analysis_jobs AS existing_job
                            WHERE existing_job.session_id = visit.session_id
                       )
                   )
                   AND visit.recording_authorization_granted = true
                   AND EXISTS (
                       SELECT 1 FROM session_consents AS consent
                        WHERE consent.session_id = visit.session_id
                          AND consent.consent_type = 'careRecipientConfirmation'
                          AND consent.granted = true
                   )
                """,
                (session_id, account_id),
            ).fetchone()
        return row is not None

    async def reserve(
        self,
        job: SpeechAnalysisJob,
    ) -> tuple[SpeechAnalysisJob, bool]:
        return await asyncio.to_thread(self._reserve, job)

    def _reserve(
        self,
        job: SpeechAnalysisJob,
    ) -> tuple[SpeechAnalysisJob, bool]:
        with psycopg.connect(self._dsn, row_factory=dict_row) as connection:
            row = connection.execute(
                """
                INSERT INTO speech_analysis_jobs
                    (analysis_id, session_id, status, participant_count,
                     s3_object_key, data_expires_at)
                VALUES (%s, %s, 'uploading', %s, %s, %s)
                ON CONFLICT (session_id) DO NOTHING
                RETURNING *
                """,
                (
                    UUID(job.analysis_id),
                    UUID(job.session_id),
                    job.participant_count,
                    job.object_key,
                    job.data_expires_at,
                ),
            ).fetchone()
            if row is not None:
                connection.commit()
                return self._from_row(row), True
            existing = connection.execute(
                "SELECT * FROM speech_analysis_jobs WHERE session_id = %s",
                (UUID(job.session_id),),
            ).fetchone()
        return self._from_row(existing), False

    async def mark_queued(
        self,
        *,
        analysis_id: str,
        size_bytes: int,
        sha256: str,
    ) -> SpeechAnalysisJob:
        return await asyncio.to_thread(
            self._mark_queued, analysis_id, size_bytes, sha256
        )

    def _mark_queued(
        self,
        analysis_id: str,
        size_bytes: int,
        sha256: str,
    ) -> SpeechAnalysisJob:
        with psycopg.connect(self._dsn, row_factory=dict_row) as connection:
            row = connection.execute(
                """
                UPDATE speech_analysis_jobs
                   SET status = 'queued', size_bytes = %s, sha256 = %s,
                       updated_at = now()
                 WHERE analysis_id = %s AND status = 'uploading'
                RETURNING *
                """,
                (size_bytes, sha256, UUID(analysis_id)),
            ).fetchone()
            if row is None:
                raise RuntimeError("업로드 중인 음성 분석 작업을 찾을 수 없습니다.")
            connection.execute(
                """
                UPDATE visit_sessions
                   SET session_status = 'processing', participant_count = %s
                 WHERE session_id = %s
                """,
                (row["participant_count"], row["session_id"]),
            )
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
        return await asyncio.to_thread(
            self._get_for_account, analysis_uuid, account_uuid
        )

    def _get_for_account(
        self,
        analysis_id: UUID,
        account_id: UUID,
    ) -> SpeechAnalysisJob | None:
        with psycopg.connect(self._dsn, row_factory=dict_row) as connection:
            row = connection.execute(
                """
                SELECT job.*
                  FROM speech_analysis_jobs AS job
                  JOIN visit_sessions AS visit ON visit.session_id = job.session_id
                  JOIN profiles AS profile ON profile.profile_id = visit.profile_id
                 WHERE job.analysis_id = %s AND profile.user_id = %s
                """,
                (analysis_id, account_id),
            ).fetchone()
        return self._from_row(row) if row is not None else None

    async def discard_upload(self, *, analysis_id: str) -> None:
        await asyncio.to_thread(self._discard_upload, analysis_id)

    def _discard_upload(self, analysis_id: str) -> None:
        with psycopg.connect(self._dsn) as connection:
            connection.execute(
                """
                DELETE FROM speech_analysis_jobs
                 WHERE analysis_id = %s AND status = 'uploading'
                """,
                (UUID(analysis_id),),
            )

    async def claim_next(self, *, lease_seconds: int) -> SpeechAnalysisJob | None:
        return await asyncio.to_thread(self._claim_next, lease_seconds)

    def _claim_next(self, lease_seconds: int) -> SpeechAnalysisJob | None:
        with psycopg.connect(self._dsn, row_factory=dict_row) as connection:
            row = connection.execute(
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
            ).fetchone()
        return self._from_row(row) if row is not None else None

    async def mark_generating_report(self, *, analysis_id: str) -> None:
        await asyncio.to_thread(
            self._set_status,
            analysis_id,
            SpeechAnalysisStatus.GENERATING_REPORT,
            None,
        )

    async def mark_stt_completed(self, *, analysis_id: str) -> None:
        await asyncio.to_thread(self._mark_stt_completed, analysis_id)

    def _mark_stt_completed(self, analysis_id: str) -> None:
        with psycopg.connect(self._dsn) as connection:
            connection.execute(
                """
                UPDATE speech_analysis_jobs
                   SET status = 'sttCompleted', stt_completed_at = now(),
                       lease_expires_at = NULL, updated_at = now()
                 WHERE analysis_id = %s AND status = 'transcribing'
                """,
                (UUID(analysis_id),),
            )

    async def mark_completed(self, *, analysis_id: str) -> None:
        await asyncio.to_thread(
            self._set_status,
            analysis_id,
            SpeechAnalysisStatus.COMPLETED,
            None,
        )

    async def mark_failed(self, *, analysis_id: str, error_code: str) -> None:
        await asyncio.to_thread(
            self._set_status,
            analysis_id,
            SpeechAnalysisStatus.FAILED,
            error_code,
        )

    def _set_status(
        self,
        analysis_id: str,
        status: SpeechAnalysisStatus,
        error_code: str | None,
    ) -> None:
        with psycopg.connect(self._dsn) as connection:
            row = connection.execute(
                """
                UPDATE speech_analysis_jobs
                   SET status = %s, error_code = %s, lease_expires_at = NULL,
                       completed_at = CASE WHEN %s IN ('completed', 'failed')
                                           THEN now() ELSE completed_at END,
                       updated_at = now()
                 WHERE analysis_id = %s
                RETURNING session_id
                """,
                (status.value, error_code, status.value, UUID(analysis_id)),
            ).fetchone()
            if row is None:
                return
            if status in {SpeechAnalysisStatus.COMPLETED, SpeechAnalysisStatus.FAILED}:
                session_status = (
                    "completed"
                    if status == SpeechAnalysisStatus.COMPLETED
                    else "failed"
                )
                connection.execute(
                    "UPDATE visit_sessions SET session_status = %s WHERE session_id = %s",
                    (session_status, row[0]),
                )

    async def mark_audio_deleted(self, *, analysis_id: str) -> None:
        await asyncio.to_thread(self._mark_audio_deleted, analysis_id)

    def _mark_audio_deleted(self, analysis_id: str) -> None:
        with psycopg.connect(self._dsn) as connection:
            connection.execute(
                """
                UPDATE speech_analysis_jobs
                   SET audio_deleted_at = now(), updated_at = now()
                 WHERE analysis_id = %s
                """,
                (UUID(analysis_id),),
            )

    @staticmethod
    def _from_row(row: dict) -> SpeechAnalysisJob:
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
