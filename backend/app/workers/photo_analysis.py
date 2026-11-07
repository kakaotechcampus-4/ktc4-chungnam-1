"""합성 사진용 실행 진입점. 실제 사용자 동의 연결 전 운영 실행은 허용하지 않는다."""
import argparse

from common.llm import ENDPOINTS
from photo_analysis import PhotoAnalysisError, analyze_photo

from app.core.config import Settings
from app.core.database import connect
from app.core.errors import AppError
from app.services.image_storage import S3ImageStorage
from app.services.photo_analysis_jobs import PhotoAnalysisQueue
from app.services.photo_analysis_pipeline import PhotoAnalysisProcessor
from app.workers.base import Worker, run_worker_main


def create_worker(settings: Settings, *, synthetic_test_data: bool = False):
    if settings.environment == "production" or not synthetic_test_data:
        raise RuntimeError("사진 분석은 현재 별도 테스트 DB의 합성 사진만 실행할 수 있습니다.")
    if not settings.database_url or not settings.image_s3_bucket or not settings.ml_api_key.get_secret_value():
        raise RuntimeError("사진 분석에는 DB, 사진 버킷과 ML API 설정이 필요합니다.")
    model = settings.photo_analysis_model or settings.report_generation_model
    if model not in ENDPOINTS:
        raise RuntimeError("등록되지 않은 사진 분석 모델입니다.")
    if settings.photo_analysis_timeout_seconds + 60 > settings.photo_analysis_lease_seconds:
        raise RuntimeError("사진 분석 임대 시간은 전체 제한 시간보다 60초 이상 길어야 합니다.")
    if settings.image_presigned_ttl_seconds < settings.photo_analysis_timeout_seconds + 60:
        raise RuntimeError("사진 조회 주소의 유효 시간이 분석 제한 시간보다 짧습니다.")
    storage = S3ImageStorage(
        bucket=settings.image_s3_bucket, region=settings.image_s3_region,
        prefix=settings.image_s3_prefix, presigned_ttl_seconds=settings.image_presigned_ttl_seconds,
        server_side_encryption=settings.image_s3_encryption,
    )

    def analyze(url):
        try:
            return analyze_photo(url, model=model,
                                 api_key=settings.ml_api_key.get_secret_value(),
                                 timeout_seconds=settings.photo_analysis_timeout_seconds)
        except PhotoAnalysisError as error:
            raise AppError(status_code=503, error_code=error.code,
                           message="사진 설명을 만들지 못했습니다.") from None

    return Worker(
        queue=PhotoAnalysisQueue(),
        process=PhotoAnalysisProcessor(storage=storage, analyze=analyze,
                                       model=model,
                                       timeout_seconds=settings.photo_analysis_timeout_seconds),
        open_connection=lambda: connect(settings.database_url),
        lease_seconds=settings.photo_analysis_lease_seconds,
    )


def main():
    parser = argparse.ArgumentParser(description="새록 합성 사진 분석 worker")
    parser.add_argument("--synthetic-test-data", action="store_true",
                        help="별도 테스트 DB에 합성 사진만 있음을 확인한 뒤 사용")
    args = argparse.Namespace()
    run_worker_main(
        description=parser.description, parser=parser, namespace=args,
        create_worker=lambda settings: create_worker(settings, synthetic_test_data=args.synthetic_test_data),
        poll_seconds=lambda settings: settings.photo_worker_poll_seconds,
    )


if __name__ == "__main__":
    main()
