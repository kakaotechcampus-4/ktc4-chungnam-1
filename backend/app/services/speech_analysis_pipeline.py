from __future__ import annotations

from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from typing import Any, Protocol
from uuid import uuid4

from fastapi import UploadFile

from app.clients.ai_server import AiServerClient
from app.core.database import DbConnection
from app.core.errors import AppError
from app.schemas.speech_analysis import SpeechAnalysisRequest, SpeechAnalysisResult
from app.services.accounts import Account, REQUIRED_CONSENTS
from app.services.audio_storage import AudioStorage
from app.services.audio_validation import validate_visit_audio
from app.services.speech_analysis_jobs import (
    SpeechAnalysisJob,
    SpeechAnalysisJobRepository,
    SpeechAnalysisStatus,
)
from app.workers.base import OpenConnection, Worker


class ReportGenerator(Protocol):
    async def generate(
        self,
        connection: DbConnection,
        *,
        session_id: str,
        speech: SpeechAnalysisResult,
    ) -> None:
        """리포트를 생성하고 저장한 뒤 반환한다.

        8-3 AI 호출은 트랜잭션 밖에서 하고, 리포트와 변경 제안 저장만 트랜잭션으로 묶는다.
        """

        ...


# worker는 작업마다 연결을 열고, 그 연결로 작업 저장소를 만든다.
JobsFor = Callable[[DbConnection], SpeechAnalysisJobRepository]


class SpeechAnalysisSubmissionService:
    def __init__(
        self,
        *,
        jobs: SpeechAnalysisJobRepository,
        audio_storage: AudioStorage,
        max_audio_bytes: int,
        retention_seconds: int,
        object_prefix: str,
    ) -> None:
        self._jobs = jobs
        self._audio_storage = audio_storage
        self._max_audio_bytes = max_audio_bytes
        self._retention_seconds = retention_seconds
        self._object_prefix = object_prefix.strip("/")

    async def submit(
        self,
        *,
        account: Account,
        session_id: str,
        participant_count: int,
        audio: UploadFile,
    ) -> SpeechAnalysisJob:
        self._assert_account_consents(account)
        await self._jobs.assert_session_access(
            account_id=account.account_id,
            session_id=session_id,
        )
        validated = await validate_visit_audio(
            audio,
            max_size_bytes=self._max_audio_bytes,
        )

        analysis_id = str(uuid4())
        object_key = f"{self._object_prefix}/{analysis_id}.wav"
        job = SpeechAnalysisJob(
            analysis_id=analysis_id,
            session_id=session_id,
            status=SpeechAnalysisStatus.UPLOADING,
            participant_count=participant_count,
            object_key=object_key,
            data_expires_at=datetime.now(UTC)
            + timedelta(seconds=self._retention_seconds),
        )
        reserved, created = await self._jobs.reserve(job)
        if not created:
            if reserved.status == SpeechAnalysisStatus.UPLOADING:
                raise AppError(
                    status_code=409,
                    error_code="ANALYSIS_SUBMISSION_IN_PROGRESS",
                    message="이 면회의 음성을 이미 전송하고 있습니다.",
                    retryable=True,
                )
            if reserved.status == SpeechAnalysisStatus.FAILED:
                raise AppError(
                    status_code=409,
                    error_code="ANALYSIS_ALREADY_FAILED",
                    message="이 면회의 음성 분석 작업이 이미 실패했습니다.",
                )
            if reserved.status == SpeechAnalysisStatus.COMPLETED:
                raise AppError(
                    status_code=409,
                    error_code="ANALYSIS_ALREADY_COMPLETED",
                    message="이 면회의 리포트가 이미 만들어졌습니다.",
                )
            return reserved

        try:
            await self._audio_storage.upload(
                object_key=job.object_key,
                file=audio.file,
            )
            return await self._jobs.mark_queued(
                analysis_id=job.analysis_id,
                size_bytes=validated.size_bytes,
                sha256=validated.sha256,
            )
        except AppError:
            await self._fail_upload(job)
            raise
        except Exception as error:
            await self._fail_upload(job)
            raise AppError(
                status_code=503,
                error_code="AUDIO_STORAGE_UNAVAILABLE",
                message="음성 파일을 안전하게 저장하지 못했습니다.",
                retryable=True,
            ) from error

    async def get(
        self,
        *,
        account: Account,
        analysis_id: str,
    ) -> SpeechAnalysisJob:
        job = await self._jobs.get_for_account(
            analysis_id=analysis_id,
            account_id=account.account_id,
        )
        if job is None:
            raise AppError(
                status_code=404,
                error_code="SPEECH_ANALYSIS_NOT_FOUND",
                message="음성 분석 작업을 찾을 수 없습니다.",
            )
        return job

    async def _fail_upload(self, job: SpeechAnalysisJob) -> None:
        try:
            await self._audio_storage.delete(object_key=job.object_key)
        except Exception:
            # 오류 응답이나 로그에 객체 키를 넣지 않는다. 24시간 Lifecycle이
            # 최종 삭제 상한을 보장해야 한다.
            pass
        # 202로 접수하기 전 실패이므로 작업을 남겨 완료된 제출처럼 보이게 하지
        # 않는다. 같은 로컬 원본으로 안전하게 다시 제출할 수 있어야 한다.
        await self._jobs.discard_upload(analysis_id=job.analysis_id)

    @staticmethod
    def _assert_account_consents(account: Account) -> None:
        if any(
            not account.consents.get(name)
            or not account.consents[name].granted
            for name in REQUIRED_CONSENTS
        ):
            raise AppError(
                status_code=403,
                error_code="SPEECH_PROCESSING_CONSENT_REQUIRED",
                message="음성 처리에 필요한 동의를 확인할 수 없습니다.",
            )


class SpeechAnalysisQueue:
    """음성 분석 작업 대기열. worker 공통 골격(`app/workers/base.py`)이 쓴다."""

    name = "speech_analysis"
    unexpected_error_code = "SPEECH_ANALYSIS_FAILED"

    def __init__(self, *, jobs_for: JobsFor, audio_storage: AudioStorage) -> None:
        self._jobs_for = jobs_for
        self._audio_storage = audio_storage

    async def expire_leases(self, connection: DbConnection) -> int:
        jobs = self._jobs_for(connection)
        return await jobs.expire_transcripts() + await jobs.expire_leases()

    async def claim(
        self, connection: DbConnection, *, lease_seconds: int
    ) -> SpeechAnalysisJob | None:
        return await self._jobs_for(connection).claim_next(lease_seconds=lease_seconds)

    async def fail(
        self, connection: DbConnection, job: SpeechAnalysisJob, *, error_code: str
    ) -> None:
        jobs = self._jobs_for(connection)
        try:
            await _delete_audio(jobs, self._audio_storage, job)
        except AppError:
            # Lifecycle이 24시간 상한을 보장한다. 원래 처리 오류를 삭제 오류로
            # 덮어쓰지 않되 삭제 실패는 worker 운영 지표에서 별도로 확인한다.
            pass
        await jobs.mark_failed(analysis_id=job.analysis_id, error_code=error_code)


class SpeechAnalysisProcessor:
    """작업 하나를 STT하고 원본을 지운 뒤, 리포트 생성기가 있으면 리포트까지 만든다."""

    def __init__(
        self,
        *,
        jobs_for: JobsFor,
        audio_storage: AudioStorage,
        ai_server: AiServerClient,
        report_generator: ReportGenerator | None = None,
    ) -> None:
        self._jobs_for = jobs_for
        self._audio_storage = audio_storage
        self._ai_server = ai_server
        self._report_generator = report_generator

    async def __call__(self, connection: DbConnection, job: SpeechAnalysisJob) -> None:
        jobs = self._jobs_for(connection)
        speech = await self._transcribe(job)
        await _delete_audio(jobs, self._audio_storage, job)
        await jobs.mark_stt_completed(
            analysis_id=job.analysis_id,
            transcript=_transcript_for_report(speech),
        )
        if self._report_generator is None:
            return
        await jobs.mark_generating_report(analysis_id=job.analysis_id)
        await self._report_generator.generate(
            connection, session_id=job.session_id, speech=speech
        )
        await jobs.mark_completed(analysis_id=job.analysis_id)

    async def _transcribe(self, job: SpeechAnalysisJob) -> SpeechAnalysisResult:
        if job.size_bytes is None or job.sha256 is None:
            raise AppError(
                status_code=500,
                error_code="INVALID_ANALYSIS_JOB",
                message="음성 분석 작업 정보가 완전하지 않습니다.",
            )
        download = await self._audio_storage.create_download(
            object_key=job.object_key,
            expires_at=job.data_expires_at,
        )
        payload = SpeechAnalysisRequest(
            schemaVersion=1,
            analysisId=job.analysis_id,
            language="ko",
            speakerCount=job.participant_count,
            audioSource={
                "type": "s3PresignedGet",
                "downloadUrl": download.url,
                "downloadUrlExpiresAt": download.expires_at,
                "sizeBytes": job.size_bytes,
                "sha256": job.sha256,
            },
            dataExpiresAt=job.data_expires_at,
        )
        return await self._ai_server.analyze_speech(payload)


def create_speech_worker(
    *,
    jobs_for: JobsFor,
    audio_storage: AudioStorage,
    ai_server: AiServerClient,
    open_connection: OpenConnection,
    lease_seconds: int,
    report_generator: ReportGenerator | None = None,
) -> Worker[SpeechAnalysisJob]:
    return Worker(
        queue=SpeechAnalysisQueue(jobs_for=jobs_for, audio_storage=audio_storage),
        process=SpeechAnalysisProcessor(
            jobs_for=jobs_for,
            audio_storage=audio_storage,
            ai_server=ai_server,
            report_generator=report_generator,
        ),
        open_connection=open_connection,
        lease_seconds=lease_seconds,
    )


async def _delete_audio(
    jobs: SpeechAnalysisJobRepository,
    audio_storage: AudioStorage,
    job: SpeechAnalysisJob,
) -> None:
    try:
        await audio_storage.delete(object_key=job.object_key)
    except Exception as error:
        raise AppError(
            status_code=503,
            error_code="AUDIO_DELETE_FAILED",
            message="임시 음성 파일을 삭제하지 못했습니다.",
            retryable=True,
        ) from error
    await jobs.mark_audio_deleted(analysis_id=job.analysis_id)


def _transcript_for_report(speech: SpeechAnalysisResult) -> dict[str, Any]:
    # 리포트 생성 요청(API 8-3)의 transcript 형식만 남긴다. 전체 문장, 단어별
    # 시각과 확률은 저장하지 않는다.
    return {
        "durationMs": speech.duration_ms,
        "segments": [
            {
                "startMs": segment.start_ms,
                "endMs": segment.end_ms,
                "speakerLabel": segment.speaker_label,
                "text": segment.text,
            }
            for segment in speech.segments
        ],
    }
