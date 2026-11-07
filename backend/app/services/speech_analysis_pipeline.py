from __future__ import annotations

import logging
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
from app.services.report_notifications import ReportNotifier
from app.services.speech_analysis_jobs import (
    SpeechAnalysisJob,
    SpeechAnalysisJobRepository,
    SpeechAnalysisStatus,
)
from app.services.transcript_filters import drop_known_hallucinations
from app.workers.base import OpenConnection, Worker

# STT 서버는 처리 기한(`dataExpiresAt`)이 자기 시각 + 24시간을 넘으면 거절한다
# (`stt-server/src/stt_server/stt/service.py`). 기한은 접수할 때 정하고 STT는 그 뒤에 받으므로,
# STT 서버 시계가 조금만 늦어도 24시간 그대로는 거절된다. 시계 차이를 감안해 5분을 남긴다.
STT_MAX_DATA_SECONDS = 24 * 60 * 60 - 5 * 60

logger = logging.getLogger("saerok.speech_analysis")


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
        # 설정이 더 길어도(최대 86400초) STT가 받는 기한을 넘기지 않는다. 원본 삭제가 그만큼 앞당겨질 뿐이다.
        self._retention_seconds = min(retention_seconds, STT_MAX_DATA_SECONDS)
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
                    error_code="REPORT_RETRY_AVAILABLE",
                    message="전사가 남아 있습니다. 녹음을 다시 보내지 말고 리포트를 다시 요청해 주세요.",
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
        await _delete_audio_or_queue(self._jobs, self._audio_storage, job)
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

    def __init__(self, *, jobs_for: JobsFor, audio_storage: AudioStorage,
                 resume_reports: bool = False) -> None:
        self._jobs_for = jobs_for
        self._audio_storage = audio_storage
        self._resume_reports = resume_reports

    async def expire_leases(self, connection: DbConnection) -> int:
        jobs = self._jobs_for(connection)
        return await jobs.expire_transcripts() + await jobs.expire_leases()

    async def claim(
        self, connection: DbConnection, *, lease_seconds: int
    ) -> SpeechAnalysisJob | None:
        return await self._jobs_for(connection).claim_next(
            lease_seconds=lease_seconds, include_reports=self._resume_reports,
        )

    async def fail(
        self, connection: DbConnection, job: SpeechAnalysisJob, *, error_code: str
    ) -> None:
        jobs = self._jobs_for(connection)
        await _delete_audio_or_queue(jobs, self._audio_storage, job)
        await jobs.mark_failed(analysis_id=job.analysis_id, error_code=error_code)


class SpeechAnalysisProcessor:
    """전사를 저장하고 원본 삭제를 시도한다. 삭제 재처리는 리포트와 분리한다."""

    def __init__(
        self,
        *,
        jobs_for: JobsFor,
        audio_storage: AudioStorage,
        ai_server: AiServerClient,
        report_generator: ReportGenerator | None = None,
        report_notifier: ReportNotifier | None = None,
    ) -> None:
        self._jobs_for = jobs_for
        self._audio_storage = audio_storage
        self._ai_server = ai_server
        self._report_generator = report_generator
        self._report_notifier = report_notifier

    async def __call__(self, connection: DbConnection, job: SpeechAnalysisJob) -> None:
        jobs = self._jobs_for(connection)
        if job.status == SpeechAnalysisStatus.GENERATING_REPORT:
            if self._report_generator is None:
                raise AppError(status_code=503, error_code="REPORT_GENERATOR_UNAVAILABLE",
                               message="리포트 생성기가 준비되지 않았습니다.")
            transcript = job.transcript or {}
            speech = SpeechAnalysisResult.model_validate({
                "schemaVersion": 1, "analysisId": job.analysis_id, "language": "ko",
                "durationMs": transcript.get("durationMs", 0),
                "text": "",
                "segments": [
                    {**segment, "words": []} for segment in transcript.get("segments", [])
                ],
            })
            if not any(segment.text.strip() for segment in speech.segments):
                raise AppError(status_code=422, error_code="EMPTY_TRANSCRIPT",
                               message="다시 분석할 발화를 확인하지 못했습니다.")
            await self._report_generator.generate(connection, session_id=job.session_id, speech=speech)
            await self._complete(connection, jobs, job)
            return
        speech = await self._transcribe(job)
        # 처리 중 임대가 만료되면 임대 정리가 작업을 이미 실패로 끝냈다. 그 작업의
        # 전사문은 저장하지 않고 리포트 생성(외부 전송)도 시작하지 않는다.
        stored = await jobs.mark_stt_completed(
            analysis_id=job.analysis_id,
            transcript=_transcript_for_report(speech),
        )
        # 삭제 요청을 DB에 먼저 남긴다. S3 삭제만 실패했다면 전사는 보존하고
        # 리포트 생성을 계속한다. 이미 끝난 작업의 원본도 정리 대상이다.
        await _delete_audio_or_queue(jobs, self._audio_storage, job)
        if not stored:
            _log_stopped(job, stage=SpeechAnalysisStatus.STT_COMPLETED)
            return
        if self._report_generator is None:
            return
        if not await jobs.mark_generating_report(analysis_id=job.analysis_id):
            _log_stopped(job, stage=SpeechAnalysisStatus.GENERATING_REPORT)
            return
        await self._report_generator.generate(
            connection, session_id=job.session_id, speech=speech
        )
        await self._complete(connection, jobs, job)

    async def _complete(
        self,
        connection: DbConnection,
        jobs: SpeechAnalysisJobRepository,
        job: SpeechAnalysisJob,
    ) -> None:
        await jobs.mark_completed(analysis_id=job.analysis_id)
        # 완료가 커밋된 뒤에 알린다. 앱이 알림을 받고 바로 리포트를 읽을 수 있어야 한다.
        # 알림 쪽이 작업이 실제로 완료됐는지 다시 확인하고, 실패해도 예외를 내지 않는다.
        if self._report_notifier is not None:
            await self._report_notifier.report_ready(
                connection, analysis_id=job.analysis_id
            )

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
        result = await self._ai_server.analyze_speech(payload)
        # 무음에서 STT가 지어내는 알려진 문장("다음 영상에서 만나요" 등)은 대화가 아니다.
        result = drop_known_hallucinations(result)
        # 리포트는 전체 text가 아니라 segments만 받는다. 빈 구간 목록이나 공백뿐인
        # 전사로 보호자 소감만 사용해 녹음 분석 결과를 만들어서는 안 된다.
        if not any(segment.text.strip() for segment in result.segments):
            raise AppError(
                status_code=422,
                error_code="EMPTY_TRANSCRIPT",
                message="녹음에서 분석할 발화를 확인하지 못했습니다.",
                retryable=False,
            )
        return result


def create_speech_worker(
    *,
    jobs_for: JobsFor,
    audio_storage: AudioStorage,
    ai_server: AiServerClient,
    open_connection: OpenConnection,
    lease_seconds: int,
    report_generator: ReportGenerator | None = None,
    report_notifier: ReportNotifier | None = None,
) -> Worker[SpeechAnalysisJob]:
    return Worker(
        queue=SpeechAnalysisQueue(jobs_for=jobs_for, audio_storage=audio_storage,
                                  resume_reports=report_generator is not None),
        process=SpeechAnalysisProcessor(
            jobs_for=jobs_for,
            audio_storage=audio_storage,
            ai_server=ai_server,
            report_generator=report_generator,
            report_notifier=report_notifier,
        ),
        open_connection=open_connection,
        lease_seconds=lease_seconds,
    )


async def _delete_audio_or_queue(
    jobs: SpeechAnalysisJobRepository,
    audio_storage: AudioStorage,
    job: SpeechAnalysisJob,
) -> None:
    if job.audio_deleted_at is not None:
        return
    # DB 기록 실패는 삼키지 않는다. 삭제 대기열에 남겼다고 확인하지 못한 상태를
    # 정상적인 삭제 재처리 접수로 취급할 수 없다.
    await jobs.queue_audio_deletion(analysis_id=job.analysis_id)
    try:
        await audio_storage.delete(object_key=job.object_key)
    except Exception:
        logger.warning("audio_deletion_pending analysis_id=%s", job.analysis_id)
        return
    await jobs.mark_audio_deleted(analysis_id=job.analysis_id)


def _log_stopped(job: SpeechAnalysisJob, *, stage: SpeechAnalysisStatus) -> None:
    # 다른 처리(임대 만료 정리 등)가 먼저 끝낸 작업이라 후속 처리를 멈췄다. 정리 로그는
    # 건수만 남기므로 작업 ID와 멈춘 단계를 여기서 남긴다. 예상된 중단이라 info다.
    # 전사문, 객체 키와 음성 주소는 넣지 않는다.
    logger.info(
        "speech_analysis_stopped analysis_id=%s stage=%s", job.analysis_id, stage
    )


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
