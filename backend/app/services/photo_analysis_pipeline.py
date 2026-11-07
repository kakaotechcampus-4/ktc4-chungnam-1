"""사진 대기열을 설명 생성 함수에 연결한다. 외부 호출 중 DB 트랜잭션을 잡지 않는다."""
import asyncio
from collections.abc import Callable
from datetime import UTC, datetime

from photo_analysis import PhotoDescription
from photo_analysis.generate import PROMPT_VERSION

from app.core.database import DbConnection
from app.core.errors import AppError
from app.services.card_sets import lock_profile
from app.services.image_storage import ImageStorage
from app.services.photo_analysis_jobs import PhotoAnalysisJob

AnalyzePhoto = Callable[[str], PhotoDescription]


class PhotoAnalysisProcessor:
    def __init__(self, *, storage: ImageStorage, analyze: AnalyzePhoto,
                 model: str, timeout_seconds: float):
        self.storage = storage
        self.analyze = analyze
        self.model = model
        self.timeout_seconds = timeout_seconds

    async def __call__(self, connection: DbConnection, job: PhotoAnalysisJob) -> None:
        active = await (await connection.execute(
            "SELECT 1 FROM photos WHERE photo_id=%s AND profile_id=%s "
            "AND session_id IS NULL AND analysis_status='processing' "
            "AND attempt_count=%s AND lease_expires_at > clock_timestamp()",
            (job.photo_id, job.profile_id, job.attempt_count),
        )).fetchone()
        if active is None:
            return
        try:
            async with asyncio.timeout(self.timeout_seconds):
                download = await self.storage.create_download(object_key=job.s3_object_key)
                if download.expires_at <= datetime.now(UTC):
                    raise AppError(status_code=503, error_code="IMAGE_URL_EXPIRED",
                                   message="사진 조회 주소가 만료됐습니다.")
                # 스레드가 늦게 끝나도 DB를 직접 수정하지 못한다.
                result = await asyncio.to_thread(self.analyze, download.url)
                result = PhotoDescription.model_validate(result)
        except TimeoutError:
            raise AppError(status_code=503, error_code="IMAGE_ANALYSIS_TIMEOUT",
                           message="사진 분석 시간이 초과됐습니다.") from None
        async with connection.transaction():
            # 카드 저장, 수정과 같은 순서로 프로필을 먼저 잠근다.
            await lock_profile(connection, job.profile_id)
            changed = await connection.execute(
                "UPDATE photos SET analysis_status='completed', description=%s, model=%s, "
                "prompt_version=%s, error_code=NULL, lease_expires_at=NULL "
                "WHERE photo_id=%s AND profile_id=%s AND session_id IS NULL "
                "AND analysis_status='processing' AND attempt_count=%s "
                "AND lease_expires_at > clock_timestamp() RETURNING user_description",
                (result.description, self.model, PROMPT_VERSION, job.photo_id,
                 job.profile_id, job.attempt_count),
            )
            row = await changed.fetchone()
            if row is None:
                return  # 삭제됐거나 임대를 잃은 작업의 늦은 결과
            if row["user_description"] is None:
                await connection.execute(
                    "UPDATE card_sets SET stale_at=now() WHERE profile_id=%s "
                    "AND status='completed' AND session_id IS NULL AND stale_at IS NULL",
                    (job.profile_id,),
                )
