from __future__ import annotations

import asyncio
import logging
import shutil
import tempfile
import time
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any, Protocol
from uuid import uuid4

from fastapi import UploadFile

from app.clients.ai_server import AiServerClient
from app.core.database import DbConnection
from app.core.errors import AppError
from app.schemas.speech_analysis import (
    SpeechAnalysisRequest,
    SpeechAnalysisResult,
    SttServer,
)
from app.services.accounts import Account, REQUIRED_CONSENTS
from app.services.audio_split import (
    PART_SECONDS,
    SAMPLE_RATE,
    AudioPart,
    may_need_split,
    plan_parts,
    write_part,
)
from app.services.audio_storage import AudioStorage
from app.services.audio_validation import validate_visit_audio
from app.services.report_notifications import ReportNotifier
from app.services.speech_analysis_jobs import (
    SpeechAnalysisJob,
    SpeechAnalysisJobRepository,
    SpeechAnalysisStatus,
)
from app.services.speech_analysis_stats import Outcome, SpeechAnalysisStats
from app.services.transcript_filters import drop_known_hallucinations
from app.workers.base import OpenConnection, Worker

# STT 서버는 처리 기한(`dataExpiresAt`)이 자기 시각 + 24시간을 넘으면 거절한다
# (`stt-server/src/stt_server/stt/service.py`). 기한은 접수할 때 정하고 STT는 그 뒤에 받으므로,
# STT 서버 시계가 조금만 늦어도 24시간 그대로는 거절된다. 시계 차이를 감안해 5분을 남긴다.
STT_MAX_DATA_SECONDS = 24 * 60 * 60 - 5 * 60
# 긴 녹음을 나누는 동안 원본과 조각을 두는 임시 디렉터리 이름의 앞부분.
WORK_DIR_PREFIX = "saerok-speech-"

logger = logging.getLogger("saerok.speech_analysis")


class _Requeued(Exception):
    """종료 요청으로 조각 사이에서 멈추고 작업을 대기열에 되돌렸다."""


class _LeaseLost(Exception):
    """조각 사이에 임대를 늘리지 못했다. 다른 처리가 작업을 이미 끝냈다."""


class ReportGenerator(Protocol):
    async def generate(
        self,
        connection: DbConnection,
        *,
        session_id: str,
        speech: SpeechAnalysisResult,
        stats: SpeechAnalysisStats,
    ) -> None:
        """리포트를 생성하고 저장한 뒤 반환한다.

        8-3 AI 호출은 트랜잭션 밖에서 하고, 리포트와 변경 제안 저장만 트랜잭션으로 묶는다.
        받은 결과의 숫자는 `stats`에 적는다(`SpeechAnalysisStats.record_report`).
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
                 resume_reports: bool = False,
                 report_notifier: ReportNotifier | None = None) -> None:
        self._jobs_for = jobs_for
        self._audio_storage = audio_storage
        self._resume_reports = resume_reports
        self._report_notifier = report_notifier

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
        # 실패가 커밋된 뒤에 알린다. 알림 쪽이 작업이 실제로 `failed`인지 다시 확인하므로,
        # 다른 처리가 먼저 완료로 끝낸 작업에는 보내지 않는다. 실패해도 예외를 내지 않는다.
        if self._report_notifier is not None:
            await self._report_notifier.report_failed(
                connection, analysis_id=job.analysis_id
            )


class SpeechAnalysisProcessor:
    """전사를 저장하고 원본 삭제를 시도한다. 삭제 재처리는 리포트와 분리한다.

    30분(`part_seconds`)을 넘는 녹음은 조각으로 나눠 차례로 전사한 뒤 합친다
    (2026-11-10 PM 결정, `_transcribe_parts`). 그 이하는 원본 하나로 한 번 부른다.
    """

    def __init__(
        self,
        *,
        jobs_for: JobsFor,
        audio_storage: AudioStorage,
        ai_server: AiServerClient,
        report_generator: ReportGenerator | None = None,
        report_notifier: ReportNotifier | None = None,
        part_seconds: int = PART_SECONDS,
        stop_requested: Callable[[], bool] | None = None,
        stale_work_dir_seconds: float = 2 * 60 * 60,
    ) -> None:
        self._jobs_for = jobs_for
        self._audio_storage = audio_storage
        self._ai_server = ai_server
        self._report_generator = report_generator
        self._report_notifier = report_notifier
        self._part_seconds = part_seconds
        self._stale_work_dir_seconds = stale_work_dir_seconds
        # worker가 종료 요청을 받았는지. 조각 사이에서만 본다.
        self._stop_requested = stop_requested or (lambda: False)

    async def __call__(self, connection: DbConnection, job: SpeechAnalysisJob) -> None:
        """작업 하나를 처리하고, 끝나거나 실패하면 처리 기록을 한 줄 남긴다(`speech_analysis_stats`).

        예외는 그대로 올려 worker 골격이 작업을 실패로 남기게 한다. 실패 코드는 골격과 같은 규칙
        (`AppError`면 그 코드, 아니면 대기열의 기본 코드)으로 적는다.
        """
        stats = SpeechAnalysisStats(analysis_id=job.analysis_id)
        try:
            outcome = await self._process(connection, job, stats)
        except AppError as error:
            usage = getattr(error, "token_usage", None)
            if usage:
                stats.token_usage = dict(usage)
            stats.emit("failed", error_code=error.error_code)
            raise
        except Exception:
            stats.emit("failed", error_code=SpeechAnalysisQueue.unexpected_error_code)
            raise
        stats.emit(outcome)

    async def _process(
        self, connection: DbConnection, job: SpeechAnalysisJob, stats: SpeechAnalysisStats
    ) -> Outcome:
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
            stats.record_transcript(speech)
            if not any(segment.text.strip() for segment in speech.segments):
                raise AppError(status_code=422, error_code="EMPTY_TRANSCRIPT",
                               message="다시 분석할 발화를 확인하지 못했습니다.")
            if job.audio_deleted_at is None:
                # STT 직후 멈춘 작업을 이어받았다면 원본 삭제 요청이 빠졌을 수 있다. 리포트만
                # 만드는 경로에서는 S3를 부르지 않고 삭제 대기열에만 남긴다. 요청이 이미 있으면
                # 그대로 둔다.
                await jobs.queue_audio_deletion(
                    analysis_id=job.analysis_id, object_key=job.object_key
                )
            await self._report_generator.generate(
                connection, session_id=job.session_id, speech=speech, stats=stats
            )
            await self._complete(connection, jobs, job)
            return "completed"
        try:
            speech = await self._transcribe(jobs, job, stats)
        except _Requeued:
            # 원본은 남긴다. 다음 worker가 같은 작업을 처음 조각부터 다시 전사한다.
            logger.info(
                "speech_analysis_requeued analysis_id=%s parts_done=%s",
                job.analysis_id, stats.stt_parts or 0,
            )
            return "requeued"
        except _LeaseLost:
            # 임대 정리나 작업 행 삭제가 먼저 끝냈다. 원본 삭제 요청은 그쪽도 남기지만
            # 전사 저장 뒤 멈춘 경우와 같이 여기서도 삭제를 시도한다.
            await _delete_audio_or_queue(jobs, self._audio_storage, job)
            _log_stopped(job, stage=SpeechAnalysisStatus.TRANSCRIBING)
            return "stopped"
        # 처리 중 임대가 만료되면 임대 정리가 작업을 이미 실패로 끝냈다. 그 작업의
        # 전사문은 저장하지 않고 리포트 생성(외부 전송)도 시작하지 않는다.
        # 리포트까지 이어 갈 때만 인계 임대를 둔다. 아래 리포트 시작 전에 worker가 멈추면
        # 임대가 끝난 뒤 다른 worker가 이어받는다. 이미 이어받은 작업이면 이 worker가 늦게
        # 돌아와도 `mark_generating_report`가 거절해 리포트를 두 번 만들지 않는다.
        stored = await jobs.mark_stt_completed(
            analysis_id=job.analysis_id,
            transcript=_transcript_for_report(speech),
            hand_off=self._report_generator is not None,
        )
        # 삭제 요청을 DB에 먼저 남긴다. S3 삭제만 실패했다면 전사는 보존하고
        # 리포트 생성을 계속한다. 이미 끝난 작업의 원본도 정리 대상이다.
        await _delete_audio_or_queue(jobs, self._audio_storage, job)
        if not stored:
            _log_stopped(job, stage=SpeechAnalysisStatus.STT_COMPLETED)
            return "stopped"
        if self._report_generator is None:
            return "sttCompleted"
        if not await jobs.mark_generating_report(analysis_id=job.analysis_id):
            _log_stopped(job, stage=SpeechAnalysisStatus.GENERATING_REPORT)
            return "stopped"
        await self._report_generator.generate(
            connection, session_id=job.session_id, speech=speech, stats=stats
        )
        await self._complete(connection, jobs, job)
        return "completed"

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

    async def _transcribe(
        self,
        jobs: SpeechAnalysisJobRepository,
        job: SpeechAnalysisJob,
        stats: SpeechAnalysisStats,
    ) -> SpeechAnalysisResult:
        if job.size_bytes is None or job.sha256 is None:
            raise AppError(
                status_code=500,
                error_code="INVALID_ANALYSIS_JOB",
                message="음성 분석 작업 정보가 완전하지 않습니다.",
            )
        if not may_need_split(job.size_bytes, part_seconds=self._part_seconds):
            # 30분 이하임이 크기로 확실하면 내려받지 않고 지금까지처럼 원본 하나로 부른다.
            result = await self._analyze(
                job, object_key=job.object_key, size_bytes=job.size_bytes,
                sha256=job.sha256, stats=stats,
            )
        else:
            result = await self._transcribe_parts(jobs, job, stats)
        # 무음에서 STT가 지어내는 알려진 문장("다음 영상에서 만나요" 등)은 대화가 아니다.
        # 조각으로 나눴으면 합친 결과에 적용한다. 조각 경계에 걸친 문장도 이어서 본다.
        result = drop_known_hallucinations(result)
        stats.record_transcript(result)
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

    async def _analyze(
        self,
        job: SpeechAnalysisJob,
        *,
        object_key: str,
        size_bytes: int,
        sha256: str,
        stats: SpeechAnalysisStats,
    ) -> SpeechAnalysisResult:
        """S3 객체 하나(원본 또는 조각)를 STT에 보낸다. 호출마다 AI 서버의 제한 시간이 따로 적용된다."""
        download = await self._audio_storage.create_download(
            object_key=object_key,
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
                "sizeBytes": size_bytes,
                "sha256": sha256,
            },
            dataExpiresAt=job.data_expires_at,
        )
        try:
            return await self._ai_server.analyze_speech(payload)
        except AppError as error:
            stats.stt_server = getattr(error, "stt_server", None)
            raise

    async def _transcribe_parts(
        self,
        jobs: SpeechAnalysisJobRepository,
        job: SpeechAnalysisJob,
        stats: SpeechAnalysisStats,
    ) -> SpeechAnalysisResult:
        """원본을 임시 파일로 받아 헤더의 실제 길이를 보고, 넘으면 조각마다 차례로 전사한다.

        조각은 원본과 같은 버킷과 접두사(같은 Lifecycle)에 올리고 STT가 끝나거나 실패하면 바로
        지운다. 올리기 전에 삭제 대기열에 넣어 두므로 worker가 중간에 멈춰도 남지 않는다.
        임시 파일은 이 함수가 끝나면 디렉터리째 지운다. 경로와 키는 로그에 남기지 않는다.
        """
        # 크기와 해시가 있는 작업만 온다(`_transcribe`가 먼저 확인한다).
        await asyncio.to_thread(
            remove_stale_work_dirs, older_than_seconds=self._stale_work_dir_seconds
        )
        with tempfile.TemporaryDirectory(prefix=WORK_DIR_PREFIX) as directory:
            original = Path(directory) / "original.wav"
            with original.open("wb") as file:
                await self._audio_storage.download(object_key=job.object_key, file=file)
            parts = await asyncio.to_thread(
                plan_parts, original, part_seconds=self._part_seconds
            )
            if len(parts) == 1:
                # data 뒤 메타데이터 청크 때문에 크기만 컸다. 원본 하나로 부른다.
                return await self._analyze(
                    job, object_key=job.object_key, size_bytes=job.size_bytes,
                    sha256=job.sha256, stats=stats,
                )
            results: list[tuple[AudioPart, SpeechAnalysisResult]] = []
            for part in parts:
                await self._before_part(jobs, job)
                part_path = Path(directory) / "part.wav"
                try:
                    written = await asyncio.to_thread(write_part, original, part, part_path)
                    result = await self._analyze_part(
                        jobs, job, object_key=part_object_key(job),
                        path=part_path, size_bytes=written.size_bytes,
                        sha256=written.sha256, audio_seconds=part.seconds, stats=stats,
                    )
                finally:
                    part_path.unlink(missing_ok=True)
                results.append((part, result))
            return merge_part_results(
                job.analysis_id, results,
                duration_ms=parts[-1].end_frame * 1000 // SAMPLE_RATE,
            )

    async def _before_part(
        self, jobs: SpeechAnalysisJobRepository, job: SpeechAnalysisJob
    ) -> None:
        # 종료 요청을 받았으면 다음 조각을 시작하지 않고 작업을 대기열에 되돌린다. 그래서
        # 종료를 기다리는 시간은 진행 중인 조각 하나와 (마지막 조각이었다면) 리포트 생성까지다.
        if self._stop_requested():
            if await jobs.requeue(analysis_id=job.analysis_id):
                raise _Requeued
            raise _LeaseLost
        # 조각마다 임대를 다시 늘린다. 조각 하나(업로드, STT 제한 시간, 삭제)는 임대 안에
        # 끝나야 하며 worker 시작 때 그 조건을 본다(`app/workers/speech_analysis.py`).
        if not await jobs.extend_lease(analysis_id=job.analysis_id):
            raise _LeaseLost

    async def _analyze_part(
        self,
        jobs: SpeechAnalysisJobRepository,
        job: SpeechAnalysisJob,
        *,
        object_key: str,
        path: Path,
        size_bytes: int,
        sha256: str,
        audio_seconds: float,
        stats: SpeechAnalysisStats,
    ) -> SpeechAnalysisResult:
        # 올리기 전에 삭제 대기열에 넣는다. 임대 시간이 지나기 전에는 삭제 실행기가 건너뛴다.
        await jobs.queue_part_deletion(object_key=object_key, defer=True)
        uploading = asyncio.create_task(self._upload_part(object_key=object_key, path=path))
        try:
            await asyncio.shield(uploading)
            # 처리 기록의 조각별 시간은 STT 호출만 잰다(업로드와 삭제 제외).
            started = time.monotonic()
            try:
                return await self._analyze(
                    job, object_key=object_key, size_bytes=size_bytes, sha256=sha256,
                    stats=stats,
                )
            finally:
                stats.record_part(
                    audio_seconds=audio_seconds, elapsed_seconds=time.monotonic() - started
                )
        except asyncio.CancelledError:
            # S3 업로드는 스레드에서 돌아 작업을 취소해도 끝까지 간다. 끝나기 전에 지우면 끝난
            # 업로드가 조각을 다시 만들므로 끝나기를 기다린다(짧은 음성 전사와 같다).
            await asyncio.wait([uploading])
            raise
        finally:
            # 종료 중 업로드 작업까지 취소됐으면 스레드가 아직 올리고 있을 수 있다. 그때는 지우지
            # 않고 올리기 전에 넣은 요청(임대 시간 뒤)을 삭제 실행기에 맡긴다.
            if uploading.done() and not uploading.cancelled():
                await self._delete_part(jobs, job, object_key)

    async def _upload_part(self, *, object_key: str, path: Path) -> None:
        with path.open("rb") as file:
            await self._audio_storage.upload(object_key=object_key, file=file)

    async def _delete_part(
        self, jobs: SpeechAnalysisJobRepository, job: SpeechAnalysisJob, object_key: str
    ) -> None:
        """조각을 지운다. 여기서는 예외를 내지 않는다(전사 결과나 원래 오류를 가리지 않게).

        S3 삭제가 실패하면 대기열에 남은 요청을 삭제 실행기가 처리한다. 지운 뒤에만 대기열에서
        뺀다(원본의 `mark_audio_deleted`와 같다).
        """
        try:
            await jobs.queue_part_deletion(object_key=object_key, defer=False)
        except Exception:
            # 올리기 전 넣은 요청이 남아 임대 시간 뒤 지울 수 있다.
            logger.warning("speech_part_deletion_schedule_failed analysis_id=%s", job.analysis_id)
        try:
            await self._audio_storage.delete(object_key=object_key)
        except Exception:
            logger.warning("speech_part_deletion_pending analysis_id=%s", job.analysis_id)
            return
        try:
            await jobs.forget_part_deletion(object_key=object_key)
        except Exception:
            # 이미 지운 객체다. 삭제 실행기가 HeadObject 404를 확인하고 요청을 뺀다.
            logger.warning("speech_part_deletion_unrecorded analysis_id=%s", job.analysis_id)


def remove_stale_work_dirs(*, older_than_seconds: float, root: Path | None = None) -> int:
    """강제 종료로 남은 조각 작업 디렉터리(원본 녹음 사본)를 지우고 지운 수를 돌려준다.

    정상 경로는 `TemporaryDirectory`가 지우지만 SIGKILL이나 전원 차단이면 남는다. compose의
    `restart: unless-stopped`는 컨테이너를 다시 만들지 않으므로 /tmp도 그대로 남는다. 같은
    호스트의 다른 worker가 쓰는 디렉터리는 조각마다 파일을 새로 만들어 수정 시각이 바뀌므로
    `older_than_seconds`(임대 두 번보다 길게)보다 오래된 것만 지운다. 경로는 로그에 남기지 않는다.
    """
    base = root or Path(tempfile.gettempdir())
    cutoff = time.time() - older_than_seconds
    removed = 0
    for path in base.glob(f"{WORK_DIR_PREFIX}*"):
        try:
            if path.is_dir() and path.stat().st_mtime < cutoff:
                shutil.rmtree(path)
                removed += 1
        except OSError:
            logger.warning("speech_work_dir_cleanup_failed")
    if removed:
        logger.info("speech_work_dirs_removed count=%s", removed)
    return removed


def part_object_key(job: SpeechAnalysisJob) -> str:
    """원본과 같은 접두사 아래 `<UUID>.wav`. 업로드마다 새 UUID다.

    삭제 실행기는 접두사 아래 UUID 형식의 WAV만 버킷을 알아본다(`storage_deletion.resolve_target`).
    다시 시도해도 같은 이름이면 앞 시도에서 지우지 못한 같은 키의 삭제 요청이 새로 올린 조각을
    STT가 받는 동안 지울 수 있으므로 작업 ID에서 만들지 않는다. 이름을 다시 읽는 곳은 없다.
    """
    head, slash, _ = job.object_key.rpartition("/")
    return f"{head}{slash}{uuid4()}.wav"


def merge_part_results(
    analysis_id: str,
    parts: list[tuple[AudioPart, SpeechAnalysisResult]],
    *,
    duration_ms: int,
) -> SpeechAnalysisResult:
    """조각별 STT 결과를 원본 시각으로 옮겨 하나로 합친다. 구간 순서는 조각 순서 그대로다.

    화자 라벨은 조각마다 따로 붙인다(`SPEAKER_00` → `PART2_SPEAKER_00`). 화자 분리는 조각
    파일마다 따로 돌아 `SPEAKER_00`이 조각마다 같은 사람이라는 보장이 없다. 계약도 라벨을
    "파일 안의 화자 군집"으로 정한다(data-contracts). 리포트와 변경 제안 프롬프트는 같은 라벨을
    같은 사람의 단서로 읽으므로, 그대로 두면 앞 조각의 어르신 말과 뒤 조각의 보호자 말을 한
    사람의 말로 묶어 이야기 후보를 잘못 귀속할 수 있다. 라벨 수가 입력 인원보다 많아지는 것은
    프롬프트가 이미 다루는 경우다("라벨 수는 실제 사람 수의 증명이 아니다"). `null`은 그대로 둔다.
    """
    segments = []
    for number, (part, result) in enumerate(parts, 1):
        offset = part.start_ms
        for segment in result.segments:
            label = segment.speaker_label
            segments.append(segment.model_copy(update={
                "start_ms": segment.start_ms + offset,
                "end_ms": segment.end_ms + offset,
                "speaker_label": f"PART{number}_{label}" if label is not None else None,
                "words": [
                    word.model_copy(update={
                        "start_ms": word.start_ms + offset,
                        "end_ms": word.end_ms + offset,
                    })
                    for word in segment.words
                ],
            }))
    merged = SpeechAnalysisResult(
        schemaVersion=1,
        analysisId=analysis_id,
        language="ko",
        durationMs=duration_ms,
        text=" ".join(
            result.text.strip() for _, result in parts if result.text.strip()
        ),
        segments=segments,
    )
    servers = {result.stt_server for _, result in parts}
    server: SttServer | None = (
        "backup" if "backup" in servers else "primary" if "primary" in servers else None
    )
    return merged.served_by(server) if server is not None else merged


def create_speech_worker(
    *,
    jobs_for: JobsFor,
    audio_storage: AudioStorage,
    ai_server: AiServerClient,
    open_connection: OpenConnection,
    lease_seconds: int,
    report_generator: ReportGenerator | None = None,
    report_notifier: ReportNotifier | None = None,
    part_seconds: int = PART_SECONDS,
) -> Worker[SpeechAnalysisJob]:
    worker: Worker[SpeechAnalysisJob]
    worker = Worker(
        queue=SpeechAnalysisQueue(jobs_for=jobs_for, audio_storage=audio_storage,
                                  resume_reports=report_generator is not None,
                                  report_notifier=report_notifier),
        process=SpeechAnalysisProcessor(
            jobs_for=jobs_for,
            audio_storage=audio_storage,
            ai_server=ai_server,
            report_generator=report_generator,
            report_notifier=report_notifier,
            part_seconds=part_seconds,
            # 조각 사이에서 종료 요청을 확인한다. worker는 아래에서 만든다.
            stop_requested=lambda: worker.stopping,
            stale_work_dir_seconds=3 * lease_seconds,
        ),
        open_connection=open_connection,
        lease_seconds=lease_seconds,
    )
    return worker


async def _delete_audio_or_queue(
    jobs: SpeechAnalysisJobRepository,
    audio_storage: AudioStorage,
    job: SpeechAnalysisJob,
) -> None:
    if job.audio_deleted_at is not None:
        return
    # DB 기록 실패는 삼키지 않는다. 삭제 대기열에 남겼다고 확인하지 못한 상태를
    # 정상적인 삭제 재처리 접수로 취급할 수 없다. 작업 행이 이미 지워졌어도(업로드 중
    # 임대 만료, 계정이나 프로필 삭제) 남도록 알고 있는 원본 키를 넘긴다.
    await jobs.queue_audio_deletion(
        analysis_id=job.analysis_id, object_key=job.object_key
    )
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
