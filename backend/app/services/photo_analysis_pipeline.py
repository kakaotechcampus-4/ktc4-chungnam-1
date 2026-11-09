"""사진 대기열을 설명 생성 함수에 연결한다. 외부 호출 중 DB 트랜잭션을 잡지 않는다."""
import asyncio
from collections.abc import Callable
from datetime import UTC, datetime

from photo_analysis import PhotoDescription
from photo_analysis.generate import PROMPT_VERSION
from psycopg.errors import LockNotAvailable, QueryCanceled

from app.core.database import DbConnection
from app.core.errors import AppError
from app.services.card_sets import lock_profile
from app.services.image_storage import ImageStorage
from app.services.photo_analysis_jobs import PhotoAnalysisJob

AnalyzePhoto = Callable[[str], PhotoDescription]

# 계정의 현재 동의에서 AI 이미지 분석이 켜져 있다. 대기열이 가져갈 때와 같은 조건이다.
_PHOTO_ANALYSIS_CONSENTED = (
    "EXISTS (SELECT 1 FROM profiles pr JOIN current_consents c ON c.user_id = pr.user_id "
    "WHERE pr.profile_id = photos.profile_id AND c.photo_analysis)"
)


async def _release_without_consent(connection: DbConnection, job: PhotoAnalysisJob) -> bool:
    """동의를 거둔 계정의 작업을 결과 없이 `pending`으로 되돌린다. 되돌렸으면 `True`다.

    프로필을 잠근 트랜잭션 안에서 부른다. 다시 동의하면 대기열이 그 사진을 다시 가져간다.
    """
    cursor = await connection.execute(
        "UPDATE photos SET analysis_status='pending', lease_expires_at=NULL "
        "WHERE photo_id=%s AND analysis_status='processing' AND attempt_count=%s "
        "AND NOT " + _PHOTO_ANALYSIS_CONSENTED + " RETURNING photo_id",
        (job.photo_id, job.attempt_count),
    )
    return await cursor.fetchone() is not None


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
        deadline = asyncio.get_running_loop().time() + self.timeout_seconds
        try:
            async with asyncio.timeout_at(deadline):
                download = await self.storage.create_download(object_key=job.s3_object_key)
                if download.expires_at <= datetime.now(UTC):
                    raise AppError(status_code=503, error_code="IMAGE_URL_EXPIRED",
                                   message="사진 조회 주소가 만료됐습니다.")
            # DB 트랜잭션 진입 중 Task를 취소하면 psycopg의 트랜잭션 정리가 끝나지 않아
            # 실패 기록까지 잃을 수 있다. DB 대기는 서버의 제한 시간으로 끝내고 롤백한다.
            remaining_ms = int((deadline - asyncio.get_running_loop().time()) * 1000)
            if remaining_ms <= 0:
                raise TimeoutError
            async with connection.transaction():
                await connection.execute(
                    "SELECT set_config('lock_timeout', %s, true), "
                    "set_config('statement_timeout', %s, true)",
                    (f"{remaining_ms}ms", f"{remaining_ms}ms"),
                )
                await lock_profile(connection, job.profile_id)
                if await _release_without_consent(connection, job):
                    return
            if asyncio.get_running_loop().time() >= deadline:
                raise TimeoutError
            async with asyncio.timeout_at(deadline):
                # 스레드가 늦게 끝나도 DB를 직접 수정하지 못한다.
                result = await asyncio.to_thread(self.analyze, download.url)
                result = PhotoDescription.model_validate(result)
        except (TimeoutError, LockNotAvailable, QueryCanceled):
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
                "AND lease_expires_at > clock_timestamp() "
                "AND " + _PHOTO_ANALYSIS_CONSENTED + " RETURNING photo_id",
                (result.description, self.model, PROMPT_VERSION, job.photo_id,
                 job.profile_id, job.attempt_count),
            )
            row = await changed.fetchone()
            if row is None:
                # 업체를 부른 뒤 동의를 거뒀으면 결과를 버리고 대기로 되돌린다. 다시 동의하면
                # 분석한다. 삭제됐거나 임대를 잃은 작업의 늦은 결과는 그대로 버린다.
                await _release_without_consent(connection, job)
                return
            # 분석이 끝난 사진은 새 카드 재료다. 사진을 새로 올릴 때처럼 이미 만든 카드
            # 묶음을 다시 만들 대상으로 바꾸지 않고 다음 카드부터 쓴다. 온보딩 마치기에서
            # 만든 첫 묶음이 분석 완료 때문에 늘 `needsRefresh`가 되던 문제를 막는다.
