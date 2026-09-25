from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import Protocol
from uuid import uuid4

from fastapi import UploadFile

from app.clients.ai_server import AiServerClient
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


class ReportGenerator(Protocol):
    async def generate(
        self,
        *,
        session_id: str,
        speech: SpeechAnalysisResult,
    ) -> None:
        """리포트를 생성하고 저장한 뒤 반환한다."""

        ...


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


class SpeechAnalysisWorker:
    def __init__(
        self,
        *,
        jobs: SpeechAnalysisJobRepository,
        audio_storage: AudioStorage,
        ai_server: AiServerClient,
        report_generator: ReportGenerator | None = None,
        lease_seconds: int,
    ) -> None:
        self._jobs = jobs
        self._audio_storage = audio_storage
        self._ai_server = ai_server
        self._report_generator = report_generator
        self._lease_seconds = lease_seconds

    async def run_once(self) -> bool:
        job = await self._jobs.claim_next(lease_seconds=self._lease_seconds)
        if job is None:
            return False

        try:
            speech = await self._transcribe(job)
            await self._delete_audio(job)
            await self._jobs.mark_stt_completed(analysis_id=job.analysis_id)
            if self._report_generator is None:
                return True
            await self._jobs.mark_generating_report(analysis_id=job.analysis_id)
            await self._report_generator.generate(
                session_id=job.session_id,
                speech=speech,
            )
            await self._jobs.mark_completed(analysis_id=job.analysis_id)
        except AppError as error:
            await self._delete_audio_after_failure(job)
            await self._jobs.mark_failed(
                analysis_id=job.analysis_id,
                error_code=error.error_code,
            )
        except Exception:
            await self._delete_audio_after_failure(job)
            await self._jobs.mark_failed(
                analysis_id=job.analysis_id,
                error_code="SPEECH_ANALYSIS_FAILED",
            )
        return True

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

    async def _delete_audio(self, job: SpeechAnalysisJob) -> None:
        try:
            await self._audio_storage.delete(object_key=job.object_key)
        except Exception as error:
            raise AppError(
                status_code=503,
                error_code="AUDIO_DELETE_FAILED",
                message="임시 음성 파일을 삭제하지 못했습니다.",
                retryable=True,
            ) from error
        await self._jobs.mark_audio_deleted(analysis_id=job.analysis_id)

    async def _delete_audio_after_failure(self, job: SpeechAnalysisJob) -> None:
        try:
            await self._delete_audio(job)
        except AppError:
            # Lifecycle이 24시간 상한을 보장한다. 원래 처리 오류를 삭제 오류로
            # 덮어쓰지 않되 삭제 실패는 worker 운영 지표에서 별도로 확인한다.
            pass
