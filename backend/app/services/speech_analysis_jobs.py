from __future__ import annotations

import asyncio
from collections.abc import Mapping
from dataclasses import dataclass, field, replace
from datetime import UTC, datetime, timedelta
from enum import StrEnum
from typing import Any, Protocol
from uuid import UUID, uuid4

from psycopg.types.json import Jsonb

from app.core.database import DbConnection
from app.core.errors import AppError
from app.workers.base import LEASE_EXPIRED_ERROR

# 전사문은 리포트 생성을 다시 시도할 때 STT를 반복하지 않도록 작업에 임시 저장한다.
# 최초 STT 저장 시 만료 시각을 정하며 실패나 리포트 재요청으로 기한을 연장하지 않는다.
# 완료 시 즉시 지우며, 실패 시에는 남은 기한 동안만 재처리에 쓴다(2026-11-03 PM 승인).
# 만료분의 실제 삭제는 expire_transcripts 또는 상태 전이에서 실행된다. worker가
# 중단되거나 다른 작업을 처리 중이면 정리가 늦어질 수 있어 별도 삭제 지연 감시가 필요하다.
# 리포트 생성(외부 ML 전송)은 남은 기한이 생성 단계 임대 시간 이상일 때만 시작한다. 임대는
# 생성 제한 시간보다 60초 이상 길어야 worker가 시작하므로 생성이 기한을 넘겨 이어지지 않는다.
TRANSCRIPT_RETENTION_SECONDS = 24 * 60 * 60
# 면회 회차당 리포트 재요청(6-5) 수의 기본값. API는 설정 `SAEROK_REPORT_RETRIES_PER_SESSION`을
# 넘긴다(2026-11-09 PM 결정). 재요청마다 전사를 외부 ML로 다시 보내므로 횟수를 둔다.
REPORT_RETRIES_PER_SESSION = 3


class SpeechAnalysisStatus(StrEnum):
    UPLOADING = "uploading"
    QUEUED = "queued"
    TRANSCRIBING = "transcribing"
    STT_COMPLETED = "sttCompleted"
    GENERATING_REPORT = "generatingReport"
    COMPLETED = "completed"
    FAILED = "failed"


# 끝난 작업은 다시 바꾸지 않는다. 늦게 끝난 처리가 먼저 남은 결과나 실패 코드를 덮지 않게 한다.
_FINISHED = {SpeechAnalysisStatus.COMPLETED, SpeechAnalysisStatus.FAILED}


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
    transcript: dict[str, Any] | None = field(default=None, repr=False)
    transcript_expires_at: datetime | None = None


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

    async def retry_report(
        self, *, analysis_id: str, account_id: str,
        max_retries: int = REPORT_RETRIES_PER_SESSION,
    ) -> SpeechAnalysisJob: ...

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

    async def claim_next(self, *, lease_seconds: int, include_reports: bool = False) -> SpeechAnalysisJob | None: ...

    async def mark_generating_report(self, *, analysis_id: str) -> bool:
        """끝나지 않은 작업을 `generatingReport`로 바꾼다. 바꿨으면 `True`.

        PostgreSQL 저장소는 남은 전사 기한이 임대 시간보다 짧으면 바꾸지 않는다.
        """
        ...

    async def mark_stt_completed(
        self, *, analysis_id: str, transcript: Mapping[str, Any], hand_off: bool = False
    ) -> bool:
        """`transcribing` 작업만 `sttCompleted`로 바꾸고 전사문을 남긴다. 바꿨으면 `True`.

        `hand_off`면 같은 worker가 리포트 생성을 이어 간다는 인계 임대를 둔다. 그 안에
        리포트 생성을 시작하지 못하고 멈춘 작업은 다른 worker가 `claim_next`로 이어받는다.
        """
        ...

    async def mark_completed(self, *, analysis_id: str) -> None: ...

    async def mark_failed(self, *, analysis_id: str, error_code: str) -> None: ...

    async def mark_audio_deleted(self, *, analysis_id: str) -> None: ...

    async def queue_audio_deletion(self, *, analysis_id: str, object_key: str) -> None:
        """원본 키를 S3 삭제 대기열에 남긴다. 이미 있으면 그대로 둔다.

        키는 부르는 쪽이 아는 값을 받는다. 계정이나 프로필 삭제, 업로드 중 임대 만료로 작업
        행이 먼저 지워졌어도 남겨야 하기 때문이다. 행이 남아 원본 삭제를 기록한 경우만 건너뛴다.
        """
        ...

    async def extend_lease(self, *, analysis_id: str) -> bool:
        """`transcribing` 작업의 임대를 지금부터 임대 시간만큼 늘린다. 늘렸으면 `True`.

        30분 조각을 하나씩 STT에 보내기 전에 부른다. 임대가 이미 끝났거나(임대 정리가 실패로
        끝냄) 작업 행이 없으면 늘리지 않는다.
        """
        ...

    async def requeue(self, *, analysis_id: str) -> bool:
        """임대가 남은 `transcribing` 작업을 `queued`로 되돌린다. 되돌렸으면 `True`.

        worker가 종료 요청을 받았을 때 조각 사이에서만 부른다. 원본은 지우지 않으며 다음
        worker가 처음 조각부터 다시 전사한다.
        """
        ...

    async def queue_part_deletion(self, *, object_key: str, defer: bool) -> None:
        """STT 조각의 키를 S3 삭제 대기열에 넣는다. 이미 있으면 삭제 가능 시각만 바꾼다.

        `defer`면 임대 시간 뒤부터 지우게 한다(조각을 올리기 전 사전 등록). 아니면 바로
        지울 수 있게 한다(STT가 끝난 뒤).
        """
        ...

    async def forget_part_deletion(self, *, object_key: str) -> None:
        """S3에서 조각을 지운 뒤 대기열에서 뺀다."""
        ...

    async def expire_transcripts(self) -> int:
        """보관 기한이 지난 전사문을 지우고 그 작업을 실패로 바꾼다.

        리포트 생성을 기다리는 `sttCompleted` 작업은 남은 기한이 임대 시간보다 짧아
        생성을 시작할 수 없게 되면 같은 방식으로 끝낸다.
        """
        ...

    async def expire_leases(self) -> int:
        """임대 시간 안에 끝나지 않은 작업을 정리한다."""
        ...


class InMemorySpeechAnalysisJobRepository:
    """합성 데이터 테스트와 로컬 계약 검증용 저장소.

    `allow_session` 으로 등록한 회차는 그 계정이 소유하고 보호자 평가를 마친 회차로
    본다. 합성 전사문은 테스트 메모리에만 보관한다.
    """

    def __init__(self) -> None:
        self._jobs: dict[str, SpeechAnalysisJob] = {}
        self._by_session: dict[str, str] = {}
        self._sessions: dict[str, str] = {}
        self.pending_audio_deletions: set[str] = set()
        self._report_retries: set[str] = set()
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
                existing = self._jobs[existing_id]
                # PostgreSQL 저장소와 같이 기한이 지난 전사는 남아 있어도 재제출을 막지 않는다.
                if existing.status != SpeechAnalysisStatus.FAILED or _has_reusable_transcript(existing):
                    return existing, False
            self._jobs[job.analysis_id] = job
            self._by_session[job.session_id] = job.analysis_id
            return job, True

    async def retry_report(
        self, *, analysis_id: str, account_id: str,
        max_retries: int = REPORT_RETRIES_PER_SESSION,
    ) -> SpeechAnalysisJob:
        old = await self.get_for_account(analysis_id=analysis_id, account_id=account_id)
        if old is None:
            raise AppError(status_code=404, error_code="SPEECH_ANALYSIS_NOT_FOUND",
                           message="음성 분석 작업을 찾을 수 없습니다.")
        async with self._lock:
            current = self._jobs[self._by_session[old.session_id]]
            if current.status == SpeechAnalysisStatus.COMPLETED:
                raise AppError(status_code=409, error_code="ANALYSIS_ALREADY_COMPLETED",
                               message="리포트가 이미 만들어졌습니다.")
            if current.status == SpeechAnalysisStatus.UPLOADING:
                raise AppError(status_code=409, error_code="ANALYSIS_SUBMISSION_IN_PROGRESS",
                               message="녹음을 전송하고 있습니다.", retryable=True)
            if current.status != SpeechAnalysisStatus.FAILED:
                return current
            # 횟수는 남은 전사를 다시 쓸 때만 센다. 전사가 없으면 한도와 관계없이 녹음 재제출을 안내한다.
            if not _has_reusable_transcript(old):
                raise _recording_required()
            retries = sum(1 for retry_id in self._report_retries
                          if self._jobs[retry_id].session_id == old.session_id)
            if retries >= max_retries:
                raise _retry_limit_exceeded()
            new = replace(old, analysis_id=str(uuid4()), status=SpeechAnalysisStatus.STT_COMPLETED,
                          error_code=None)
            self._jobs[old.analysis_id] = replace(old, transcript=None)
            self._jobs[new.analysis_id] = new
            self._report_retries.add(new.analysis_id)
            self._by_session[new.session_id] = new.analysis_id
            return new

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

    async def claim_next(self, *, lease_seconds: int, include_reports: bool = False) -> SpeechAnalysisJob | None:
        # 리포트 생성은 임대가 끝나기 전에 전사 기한이 오지 않을 때만 시작한다.
        report_start_limit = datetime.now(UTC) + timedelta(seconds=lease_seconds)
        async with self._lock:
            job = next(
                (
                    item
                    for item in self._jobs.values()
                    if item.status == SpeechAnalysisStatus.QUEUED or (
                        include_reports and item.status == SpeechAnalysisStatus.STT_COMPLETED
                        and item.analysis_id in self._report_retries
                        and item.transcript_expires_at is not None
                        and item.transcript_expires_at > report_start_limit
                    )
                ),
                None,
            )
            if job is None:
                return None
            claimed = replace(job, status=(SpeechAnalysisStatus.GENERATING_REPORT
                if job.status == SpeechAnalysisStatus.STT_COMPLETED else SpeechAnalysisStatus.TRANSCRIBING))
            self._jobs[job.analysis_id] = claimed
            return claimed

    async def mark_generating_report(self, *, analysis_id: str) -> bool:
        if self._jobs[analysis_id].status in _FINISHED:
            return False
        self._set_status(analysis_id, SpeechAnalysisStatus.GENERATING_REPORT)
        return True

    async def mark_stt_completed(
        self, *, analysis_id: str, transcript: Mapping[str, Any], hand_off: bool = False
    ) -> bool:
        # 메모리 저장소는 임대를 다루지 않으므로(`expire_leases`와 같다) 인계 임대도 두지 않는다.
        del hand_off
        if self._jobs[analysis_id].status != SpeechAnalysisStatus.TRANSCRIBING:
            return False
        self._jobs[analysis_id] = replace(
            self._jobs[analysis_id],
            status=SpeechAnalysisStatus.STT_COMPLETED,
            stt_completed_at=datetime.now(UTC),
            transcript=dict(transcript),
            transcript_expires_at=datetime.now(UTC) + timedelta(seconds=TRANSCRIPT_RETENTION_SECONDS),
        )
        return True

    async def mark_completed(self, *, analysis_id: str) -> None:
        if self._jobs[analysis_id].status != SpeechAnalysisStatus.GENERATING_REPORT:
            return
        self._set_status(analysis_id, SpeechAnalysisStatus.COMPLETED)

    async def mark_failed(self, *, analysis_id: str, error_code: str) -> None:
        if self._jobs[analysis_id].status in _FINISHED:
            return
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
        self.pending_audio_deletions.discard(self._jobs[analysis_id].object_key)

    async def queue_audio_deletion(self, *, analysis_id: str, object_key: str) -> None:
        job = self._jobs.get(analysis_id)
        if job is None or job.audio_deleted_at is None:
            self.pending_audio_deletions.add(object_key)

    async def extend_lease(self, *, analysis_id: str) -> bool:
        # 메모리 저장소는 임대 시각을 두지 않으므로 상태만 본다.
        job = self._jobs.get(analysis_id)
        return job is not None and job.status == SpeechAnalysisStatus.TRANSCRIBING

    async def requeue(self, *, analysis_id: str) -> bool:
        job = self._jobs.get(analysis_id)
        if job is None or job.status != SpeechAnalysisStatus.TRANSCRIBING:
            return False
        self._jobs[analysis_id] = replace(job, status=SpeechAnalysisStatus.QUEUED)
        return True

    async def queue_part_deletion(self, *, object_key: str, defer: bool) -> None:
        del defer
        self.pending_audio_deletions.add(object_key)

    async def forget_part_deletion(self, *, object_key: str) -> None:
        self.pending_audio_deletions.discard(object_key)

    async def expire_transcripts(self) -> int:
        return 0

    async def expire_leases(self) -> int:
        return 0

    def _set_status(
        self,
        analysis_id: str,
        status: SpeechAnalysisStatus,
    ) -> None:
        self._jobs[analysis_id] = replace(
            self._jobs[analysis_id], status=status,
            transcript=None if status == SpeechAnalysisStatus.COMPLETED else self._jobs[analysis_id].transcript,
        )


class PostgresSpeechAnalysisJobRepository:
    """PostgreSQL 행 잠금으로 작업을 하나씩 임대하는 저장소.

    바깥에서 받은 비동기 연결을 쓴다(API는 `DbConnectionDep`, worker는 골격이 연다).
    연결은 autocommit이므로 여러 문장을 함께 반영할 때만 트랜잭션 블록으로 묶는다.
    """

    def __init__(self, connection: DbConnection, *, lease_seconds: int) -> None:
        self._connection = connection
        # 업로드, STT 뒤 인계와 리포트 생성 단계의 작업 임대 시간. 전사 단계는 worker가 정한다.
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
            # 재제출과 리포트 재요청을 회차별로 직렬화한다.
            await self._connection.execute(
                "SELECT 1 FROM visit_sessions WHERE session_id=%s FOR UPDATE", (session_id,)
            )
            # 전사가 아직 남아 있다면 다시 STT에 보내지 않고 리포트 재요청을 안내한다.
            cursor = await self._connection.execute(
                """
                SELECT * FROM speech_analysis_jobs
                 WHERE session_id = %s AND status = 'failed'
                   AND transcript IS NOT NULL AND transcript_expires_at > clock_timestamp()
                   AND NOT EXISTS (
                       SELECT 1 FROM speech_analysis_jobs active
                        WHERE active.session_id=%s AND active.status <> 'failed'
                   )
                 ORDER BY created_at DESC
                 LIMIT 1
                """,
                (session_id, session_id),
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

    async def retry_report(
        self, *, analysis_id: str, account_id: str,
        max_retries: int = REPORT_RETRIES_PER_SESSION,
    ) -> SpeechAnalysisJob:
        old = await self.get_for_account(analysis_id=analysis_id, account_id=account_id)
        if old is None:
            raise AppError(status_code=404, error_code="SPEECH_ANALYSIS_NOT_FOUND",
                           message="음성 분석 작업을 찾을 수 없습니다.")
        await self.assert_session_access(account_id=account_id, session_id=old.session_id)
        async with self._connection.transaction():
            await self._connection.execute(
                "SELECT 1 FROM visit_sessions WHERE session_id=%s FOR UPDATE", (UUID(old.session_id),)
            )
            active = await (await self._connection.execute(
                "SELECT * FROM speech_analysis_jobs WHERE session_id=%s AND status <> 'failed'",
                (UUID(old.session_id),),
            )).fetchone()
            if active is not None:
                if active["status"] == "uploading":
                    raise AppError(status_code=409, error_code="ANALYSIS_SUBMISSION_IN_PROGRESS",
                                   message="녹음을 전송하고 있습니다.", retryable=True)
                if active["status"] == "completed":
                    raise AppError(status_code=409, error_code="ANALYSIS_ALREADY_COMPLETED",
                                   message="리포트가 이미 만들어졌습니다.")
                return self._from_row(active)
            previous_retry = await (await self._connection.execute(
                "SELECT 1 FROM speech_analysis_jobs WHERE retry_of_analysis_id=%s",
                (UUID(analysis_id),),
            )).fetchone()
            if previous_retry:
                raise AppError(status_code=409, error_code="ANALYSIS_ALREADY_FAILED",
                               message="재요청한 작업도 종료됐습니다. 최신 처리 상태를 확인해 주세요.")
            # 횟수는 남은 전사를 다시 쓸 때만 센다. 전사가 없거나 기한이 지났으면 한도와 관계없이
            # 녹음 재제출(6-2)을 안내한다. 6-2로 새로 받은 작업은 재요청이 아니므로 세지 않는다.
            reusable = await (await self._connection.execute(
                "SELECT 1 FROM speech_analysis_jobs WHERE analysis_id=%s AND status='failed' "
                "AND transcript IS NOT NULL AND transcript_expires_at > clock_timestamp()",
                (UUID(analysis_id),),
            )).fetchone()
            if reusable is None:
                raise _recording_required()
            # 회차 행을 잠근 뒤 세므로 동시 재요청에도 횟수를 넘지 않는다. 처리 중인 재요청을
            # 다시 보낸 경우는 위에서 그 작업을 돌려주므로 세지 않는다.
            retries = await (await self._connection.execute(
                "SELECT count(*) AS n FROM speech_analysis_jobs "
                "WHERE session_id=%s AND retry_of_analysis_id IS NOT NULL",
                (UUID(old.session_id),),
            )).fetchone()
            if retries["n"] >= max_retries:
                raise _retry_limit_exceeded()
            # 보관 기한은 연장하지 않는다. 새 ID로 분리해 이전 작업의 늦은 결과를 막는다.
            new_id = uuid4()
            row = await (await self._connection.execute(
                "INSERT INTO speech_analysis_jobs "
                "(analysis_id,session_id,status,participant_count,s3_object_key,data_expires_at,"
                "size_bytes,sha256,audio_deleted_at,stt_completed_at,transcript,transcript_expires_at,retry_of_analysis_id) "
                "SELECT %s,session_id,'sttCompleted',participant_count,s3_object_key,data_expires_at,"
                "size_bytes,sha256,audio_deleted_at,stt_completed_at,transcript,transcript_expires_at,analysis_id "
                "FROM speech_analysis_jobs WHERE analysis_id=%s AND status='failed' "
                "AND transcript IS NOT NULL AND transcript_expires_at > clock_timestamp() RETURNING *",
                (new_id, UUID(analysis_id)),
            )).fetchone()
            if row is None:
                # 위에서 확인한 뒤 이 문장 사이에 기한이 지난 경우다.
                raise _recording_required()
            await self._connection.execute(
                "UPDATE speech_analysis_jobs SET transcript=NULL, transcript_deleted_at=now(), updated_at=now() "
                "WHERE analysis_id=%s", (UUID(analysis_id),),
            )
        return self._from_row(row)

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

    async def claim_next(self, *, lease_seconds: int, include_reports: bool = False) -> SpeechAnalysisJob | None:
        # `sttCompleted`는 리포트 재요청 작업이면 바로, STT를 마친 worker가 인계 임대 안에
        # 리포트 생성을 시작하지 못하고 멈춘 작업이면 그 임대가 끝난 뒤 가져간다. STT 단독
        # 실행으로 멈춘 작업은 인계 임대가 없어 가져가지 않는다. 어느 쪽이든 임대(생성 제한
        # 시간 + 저장 여유 이상)가 끝나기 전에 전사 기한이 오지 않을 때만 가져간다. 시작할 수
        # 없게 된 작업은 expire_transcripts가 끝낸다.
        cursor = await self._connection.execute(
            """
            WITH candidate AS (
                SELECT analysis_id
                  FROM speech_analysis_jobs
                 WHERE status = 'queued' OR (
                     %s AND status = 'sttCompleted'
                     AND (retry_of_analysis_id IS NOT NULL OR lease_expires_at <= now())
                     AND transcript_expires_at > clock_timestamp() + (%s * interval '1 second')
                 )
                 ORDER BY created_at
                 FOR UPDATE SKIP LOCKED
                 LIMIT 1
            )
            UPDATE speech_analysis_jobs AS job
               SET status = CASE WHEN job.status='sttCompleted' THEN 'generatingReport' ELSE 'transcribing' END,
                   attempt_count = attempt_count + 1,
                   lease_expires_at = now() + (%s * interval '1 second'),
                   updated_at = now()
              FROM candidate
             WHERE job.analysis_id = candidate.analysis_id
            RETURNING job.*
            """,
            (include_reports, lease_seconds, lease_seconds),
        )
        row = await cursor.fetchone()
        return self._from_row(row) if row is not None else None

    async def mark_generating_report(self, *, analysis_id: str) -> bool:
        return await self._set_status(
            analysis_id, SpeechAnalysisStatus.GENERATING_REPORT, None
        )

    async def mark_stt_completed(
        self, *, analysis_id: str, transcript: Mapping[str, Any], hand_off: bool = False
    ) -> bool:
        # 인계 임대는 전사 저장과 같은 문장에서 정한다. 따로 정하면 그 사이에 멈춘 작업을
        # 이어받을 수 없다. STT 뒤 리포트 시작 전까지는 원본 삭제 요청만 하므로 리포트
        # 단계와 같은 임대 시간이면 충분하다.
        cursor = await self._connection.execute(
            """
            UPDATE speech_analysis_jobs
               SET status = 'sttCompleted', stt_completed_at = now(),
                   transcript = %s,
                   transcript_expires_at = now() + (%s * interval '1 second'),
                   lease_expires_at = CASE
                       WHEN %s THEN now() + (%s * interval '1 second')
                   END,
                   updated_at = now()
             WHERE analysis_id = %s AND status = 'transcribing'
               AND lease_expires_at > clock_timestamp()
            """,
            (
                Jsonb(dict(transcript)),
                TRANSCRIPT_RETENTION_SECONDS,
                hand_off,
                self._lease_seconds,
                UUID(analysis_id),
            ),
        )
        return cursor.rowcount > 0

    async def mark_completed(self, *, analysis_id: str) -> None:
        # 리포트 생성기는 저장 트랜잭션에서 이미 완료 처리하므로 보통 바뀌는 행이 없다.
        await complete_job(self._connection, analysis_id=analysis_id)

    async def mark_failed(self, *, analysis_id: str, error_code: str) -> None:
        await self._set_status(analysis_id, SpeechAnalysisStatus.FAILED, error_code)

    async def _set_status(
        self,
        analysis_id: str,
        status: SpeechAnalysisStatus,
        error_code: str | None,
    ) -> bool:
        return await _update_status(
            self._connection,
            analysis_id=analysis_id,
            status=status,
            error_code=error_code,
            lease_seconds=self._lease_seconds,
        )

    async def mark_audio_deleted(self, *, analysis_id: str) -> None:
        async with self._connection.transaction():
            await self._connection.execute(
                """
                UPDATE speech_analysis_jobs
                   SET audio_deleted_at = now(), updated_at = now()
                 WHERE analysis_id = %s
                """,
                (UUID(analysis_id),),
            )
            await self._connection.execute(
                """
                DELETE FROM storage_deletion_request_queue
                 WHERE s3_object_key = (
                     SELECT s3_object_key FROM speech_analysis_jobs
                      WHERE analysis_id = %s
                 )
                """,
                (UUID(analysis_id),),
            )

    async def queue_audio_deletion(self, *, analysis_id: str, object_key: str) -> None:
        # 키를 작업 행에서 읽지 않는다. 행이 이미 지워졌다면(계정이나 프로필 삭제, 업로드 중
        # 임대 만료) 아무것도 넣지 못해, 뒤늦게 끝난 업로드의 원본이 대기열 밖에 남는다.
        await self._connection.execute(
            """
            INSERT INTO storage_deletion_request_queue (s3_object_key)
            SELECT %s
             WHERE NOT EXISTS (
                 SELECT 1 FROM speech_analysis_jobs
                  WHERE analysis_id = %s AND audio_deleted_at IS NOT NULL
             )
            ON CONFLICT (s3_object_key) DO NOTHING
            """,
            (object_key, UUID(analysis_id)),
        )

    async def extend_lease(self, *, analysis_id: str) -> bool:
        # 끝난 임대는 늘리지 않는다. 임대 정리가 아직 돌지 않았어도 다른 worker가 그 작업을
        # 실패로 끝낼 수 있는 상태이므로 이어 가지 않는다.
        cursor = await self._connection.execute(
            """
            UPDATE speech_analysis_jobs
               SET lease_expires_at = now() + (%s * interval '1 second'),
                   updated_at = now()
             WHERE analysis_id = %s AND status = 'transcribing'
               AND lease_expires_at > clock_timestamp()
            """,
            (self._lease_seconds, UUID(analysis_id)),
        )
        return cursor.rowcount > 0

    async def requeue(self, *, analysis_id: str) -> bool:
        # 접수한 원본과 크기, 해시는 그대로 두고 상태와 임대만 되돌린다. claim_next는 오래된
        # 작업부터 가져가므로 다음 worker가 이 작업을 먼저 이어 간다.
        cursor = await self._connection.execute(
            """
            UPDATE speech_analysis_jobs
               SET status = 'queued', lease_expires_at = NULL, updated_at = now()
             WHERE analysis_id = %s AND status = 'transcribing'
               AND lease_expires_at > clock_timestamp()
            """,
            (UUID(analysis_id),),
        )
        return cursor.rowcount > 0

    async def queue_part_deletion(self, *, object_key: str, defer: bool) -> None:
        # 조각 키는 작업 행에 없으므로 행 삭제 trigger와 임대 정리가 대기열에 넣지 못한다.
        # 올리기 전에 넣어 두고, 처리 중 조기 삭제는 not_before로 막는다(짧은 음성 전사와 같다).
        # 임대가 끝나면 그 작업은 더 진행하지 않으므로 그때부터 지워도 된다.
        await self._connection.execute(
            """
            INSERT INTO storage_deletion_request_queue (s3_object_key, not_before)
            VALUES (%s, now() + (%s * interval '1 second'))
            ON CONFLICT (s3_object_key) DO UPDATE SET not_before = EXCLUDED.not_before
            """,
            (object_key, self._lease_seconds if defer else 0),
        )

    async def forget_part_deletion(self, *, object_key: str) -> None:
        await self._connection.execute(
            "DELETE FROM storage_deletion_request_queue WHERE s3_object_key = %s",
            (object_key,),
        )

    async def expire_transcripts(self) -> int:
        # 이미 failed인 작업도 포함한다. 재시도하지 않고 남겨 둔 전사가 누락되면 안 된다.
        # worker가 작업을 가져오기 전에 호출한다. DB 자체 TTL이나 상시 타이머는 아니다.
        # 생성을 기다리는 sttCompleted 작업은 남은 기한이 임대보다 짧으면 claim_next와
        # mark_generating_report가 시작하지 않으므로, 처리 중으로 남기지 않고 여기서 끝낸다.
        cursor = await self._connection.execute(
            """
            UPDATE speech_analysis_jobs
               SET status = 'failed', error_code = 'TRANSCRIPT_EXPIRED',
                   transcript = NULL, transcript_deleted_at = now(),
                   lease_expires_at = NULL, completed_at = now(),
                   updated_at = now()
             WHERE transcript IS NOT NULL AND (
                   transcript_expires_at <= now()
                   OR (status = 'sttCompleted'
                       AND transcript_expires_at <= now() + (%s * interval '1 second'))
             )
            """,
            (self._lease_seconds,),
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
            # 처리 중에 멈춘 작업은 실패로 끝내고 원본 삭제 요청을 함께 남긴다.
            # Lifecycle의 일 단위 만료만으로 정확한 삭제 시각을 보장할 수 없다.
            # 전사 유지와 삭제 시각 기록은 한 번 읽은 시각(`clock`)으로 정한다. 이유는
            # `_update_status`와 같다.
            processing = await self._connection.execute(
                """
                WITH clock AS MATERIALIZED (
                    SELECT clock_timestamp() AS checked_at
                ), expired AS (
                UPDATE speech_analysis_jobs
                   SET status = 'failed', error_code = %s,
                       transcript = CASE WHEN transcript_expires_at > clock.checked_at THEN transcript END,
                       transcript_deleted_at = CASE
                           WHEN transcript IS NOT NULL AND transcript_expires_at <= clock.checked_at THEN now()
                           ELSE transcript_deleted_at
                       END,
                       lease_expires_at = NULL, completed_at = now(),
                       updated_at = now()
                  FROM clock
                 WHERE status IN ('transcribing', 'generatingReport')
                   AND lease_expires_at <= now()
                RETURNING s3_object_key, audio_deleted_at
                ), requested AS (
                    INSERT INTO storage_deletion_request_queue (s3_object_key)
                    SELECT s3_object_key FROM expired WHERE audio_deleted_at IS NULL
                    ON CONFLICT (s3_object_key) DO NOTHING
                )
                SELECT count(*) AS expired_count FROM expired
                """,
                (LEASE_EXPIRED_ERROR,),
            )
            expired_row = await processing.fetchone()
        return uploading.rowcount + expired_row["expired_count"]

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
            transcript=row["transcript"],
            transcript_expires_at=row["transcript_expires_at"],
        )


async def complete_job(connection: DbConnection, *, analysis_id: str) -> bool:
    """`generatingReport` 작업만 `completed`로 바꾸고 전사문을 지운다. 바꿨으면 `True`.

    리포트 생성기가 리포트 저장과 같은 트랜잭션에서 부른다.
    """
    return await _update_status(
        connection,
        analysis_id=analysis_id,
        status=SpeechAnalysisStatus.COMPLETED,
        error_code=None,
        lease_seconds=0,
    )


async def _update_status(
    connection: DbConnection,
    *,
    analysis_id: str,
    status: SpeechAnalysisStatus,
    error_code: str | None,
    lease_seconds: int,
) -> bool:
    # 회차 상태는 저장하지 않고 작업 상태로 계산하므로 회차는 바꾸지 않는다.
    # 완료한 리포트의 전사는 지운다. 생성 실패 시 기존 보관 기한까지만 남긴다.
    # `completed`는 `generatingReport`에서만, 끝난 작업(`completed`, `failed`)은 바꾸지 않는다.
    # `generatingReport`는 새 임대가 끝나기 전에 전사 기한이 오지 않을 때만 시작한다.
    # 기한 비교는 모두 한 번 읽은 시각(`clock`)으로 한다. clock_timestamp()를 식마다 부르면
    # 그 사이에 기한이 지나 전사는 남고 삭제 시각만 채워져 CHECK에 걸릴 수 있다.
    cursor = await connection.execute(
        """
        WITH clock AS MATERIALIZED (SELECT clock_timestamp() AS checked_at)
        UPDATE speech_analysis_jobs
           SET status = %(status)s::text, error_code = %(error_code)s,
               lease_expires_at = CASE
                   WHEN %(status)s::text = 'generatingReport'
                   THEN now() + (%(lease_seconds)s * interval '1 second')
               END,
               transcript = CASE
                   WHEN %(status)s::text = 'completed' OR transcript_expires_at <= clock.checked_at THEN NULL
                   ELSE transcript
               END,
               transcript_deleted_at = CASE
                   WHEN (%(status)s::text = 'completed' OR transcript_expires_at <= clock.checked_at)
                        AND transcript IS NOT NULL THEN now()
                   ELSE transcript_deleted_at
               END,
               completed_at = CASE
                   WHEN %(status)s::text IN ('completed', 'failed') THEN now()
                   ELSE completed_at
               END,
               updated_at = now()
          FROM clock
         WHERE analysis_id = %(analysis_id)s
           AND status NOT IN ('completed', 'failed')
           AND (%(status)s::text <> 'completed' OR status = 'generatingReport')
           AND (%(status)s::text <> 'generatingReport' OR (
               status='sttCompleted'
               AND transcript_expires_at
                   > clock.checked_at + (%(lease_seconds)s * interval '1 second')
           ))
        """,
        {
            "status": status.value,
            "error_code": error_code,
            "lease_seconds": lease_seconds,
            "analysis_id": UUID(analysis_id),
        },
    )
    return cursor.rowcount > 0


def _has_reusable_transcript(job: SpeechAnalysisJob) -> bool:
    """메모리 저장소에서 리포트 재요청에 다시 쓸 전사가 남았는지. PostgreSQL 저장소는 같은 조건을 SQL로 본다."""
    return (job.transcript is not None and job.transcript_expires_at is not None
            and job.transcript_expires_at > datetime.now(UTC))


def _recording_required() -> AppError:
    return AppError(status_code=409, error_code="RECORDING_REQUIRED",
                    message="분석에 쓸 전사가 남아 있지 않습니다. 기기의 녹음을 다시 보내 주세요.")


def _retry_limit_exceeded() -> AppError:
    return AppError(status_code=409, error_code="REPORT_RETRY_LIMIT_EXCEEDED",
                    message=("이 면회의 리포트 재요청 횟수를 모두 사용했습니다. 남은 전사의 보관 기한이 "
                             "지나면 기기의 녹음을 다시 보내 요청할 수 있습니다."))


def _session_not_found() -> AppError:
    return AppError(
        status_code=404,
        error_code="VISIT_SESSION_NOT_FOUND",
        message="면회 기록을 찾을 수 없습니다.",
    )
