"""리포트 완료 푸시의 대상 고르기와 음성 worker 연결 검증.

대상 고르기는 임시 DB(`conftest.py`)에서, worker 연결은 메모리 작업 저장소로 확인한다.
FCM 은 [FakeSender] 로 대신한다. 계정, 회차와 FID 는 모두 합성이다.
"""

from uuid import UUID

from app.clients.fcm import SendResult
from app.core.database import connect
from app.services.report_notifications import PushReportNotifier
from app.services.speech_analysis_jobs import SpeechAnalysisStatus
from app.services.speech_analysis_pipeline import create_speech_worker
from tests.support import run
from tests.test_speech_analyses import (
    ACCOUNT,
    FakeAiServer,
    FakeReportGenerator,
    LeaseLosingAiServer,
    harness,
    no_connection,
    submit,
)
from tests.visit_records import Records

FID_A = "cSyntheticFidAAAAAAAAA"
FID_B = "dSyntheticFidBBBBBBBBB"
FID_OTHER = "eSyntheticFidOtherXXXX"


class FakeSender:
    def __init__(self, results: dict[str, SendResult] | None = None) -> None:
        self.sent: list[tuple[str, str, str]] = []
        self._results = results or {}
        self.error: Exception | None = None

    async def send_report_ready(
        self, fid: str, *, session_id: str, analysis_id: str
    ) -> SendResult:
        if self.error is not None:
            raise self.error
        self.sent.append((fid, session_id, analysis_id))
        return self._results.get(fid, SendResult.SENT)


def _caregiver(records: Records, *, push: bool = True) -> tuple[UUID, UUID]:
    """알림 동의를 정한 계정과 프로필. `Records.account` 는 동의 이력을 만들지 않는다."""
    user_id, profile_id = records.account()
    records.execute(
        "INSERT INTO consent_records (user_id, terms_version, service_data, "
        "sensitive_data, service_improvement, push_notification) "
        "VALUES (%s, '2026-09-06', true, true, false, %s)",
        (user_id, push),
    )
    return user_id, profile_id


def _register(records: Records, user_id: UUID, fid: str) -> None:
    records.execute(
        "INSERT INTO push_devices (fid, user_id) VALUES (%s, %s)", (fid, user_id)
    )


def _completed_job(records: Records, profile_id: UUID, status: str = "completed"):
    visit = records.visit(profile_id)
    return visit.session_id, records.job(visit.session_id, status)


def _notify(records: Records, sender: FakeSender, analysis_id: UUID) -> None:
    async def scenario() -> None:
        async with connect(records.database_url) as connection:
            await PushReportNotifier(sender).report_ready(
                connection, analysis_id=str(analysis_id)
            )

    run(scenario())


def _fids(records: Records) -> list[str]:
    return [row["fid"] for row in records.query("SELECT fid FROM push_devices ORDER BY fid")]


def test_completed_report_is_sent_to_every_device_of_the_account(
    migrated_database_url,
):
    records = Records(migrated_database_url)
    user_id, profile_id = _caregiver(records)
    other_id, _ = _caregiver(records)
    _register(records, user_id, FID_A)
    _register(records, user_id, FID_B)
    _register(records, other_id, FID_OTHER)
    session_id, analysis_id = _completed_job(records, profile_id)
    sender = FakeSender()

    _notify(records, sender, analysis_id)

    assert sorted(sender.sent) == [
        (FID_A, str(session_id), str(analysis_id)),
        (FID_B, str(session_id), str(analysis_id)),
    ]


def test_nothing_is_sent_unless_the_job_is_completed(migrated_database_url):
    records = Records(migrated_database_url)
    user_id, profile_id = _caregiver(records)
    _register(records, user_id, FID_A)
    sender = FakeSender()

    for status in ("generatingReport", "failed"):
        _, analysis_id = _completed_job(records, profile_id, status)
        _notify(records, sender, analysis_id)

    assert sender.sent == []


def test_nothing_is_sent_when_push_consent_is_withdrawn(migrated_database_url):
    records = Records(migrated_database_url)
    user_id, profile_id = _caregiver(records)
    _register(records, user_id, FID_A)
    # 기기 등록이 남아 있어도 지금 동의가 없으면 보내지 않는다.
    records.execute(
        "INSERT INTO consent_records (user_id, terms_version, service_data, "
        "sensitive_data, service_improvement, push_notification) "
        "VALUES (%s, '2026-09-06', true, true, false, false)",
        (user_id,),
    )
    _, analysis_id = _completed_job(records, profile_id)
    sender = FakeSender()

    _notify(records, sender, analysis_id)

    assert sender.sent == []


def test_unregistered_devices_are_removed_and_others_kept(migrated_database_url):
    records = Records(migrated_database_url)
    user_id, profile_id = _caregiver(records)
    _register(records, user_id, FID_A)
    _register(records, user_id, FID_B)
    _, analysis_id = _completed_job(records, profile_id)
    sender = FakeSender(
        {FID_A: SendResult.UNREGISTERED, FID_B: SendResult.FAILED}
    )

    _notify(records, sender, analysis_id)

    assert len(sender.sent) == 2
    assert _fids(records) == [FID_B]


def test_send_errors_do_not_escape(migrated_database_url):
    records = Records(migrated_database_url)
    user_id, profile_id = _caregiver(records)
    _register(records, user_id, FID_A)
    _, analysis_id = _completed_job(records, profile_id)
    sender = FakeSender()
    sender.error = RuntimeError("synthetic sender failure")

    _notify(records, sender, analysis_id)

    assert _fids(records) == [FID_A]


class FakeNotifier:
    def __init__(self) -> None:
        self.analysis_ids: list[str] = []

    async def report_ready(self, connection, *, analysis_id: str) -> None:
        del connection
        self.analysis_ids.append(analysis_id)


def _worker(jobs, storage, ai, reports, notifier):
    return create_speech_worker(
        jobs_for=lambda connection: jobs,
        audio_storage=storage,
        ai_server=ai,
        open_connection=no_connection,
        lease_seconds=900,
        report_generator=reports,
        report_notifier=notifier,
    )


def test_worker_notifies_after_the_report_is_completed():
    application, jobs, storage, _ = harness()
    accepted = submit(application).json()
    notifier = FakeNotifier()

    run(_worker(jobs, storage, FakeAiServer(), FakeReportGenerator(), notifier).run_once())

    job = run(
        jobs.get_for_account(
            analysis_id=accepted["analysisId"], account_id=ACCOUNT.account_id
        )
    )
    assert job.status == SpeechAnalysisStatus.COMPLETED
    assert notifier.analysis_ids == [accepted["analysisId"]]


def test_worker_does_not_notify_a_job_that_stopped_before_the_report():
    application, jobs, storage, _ = harness()
    submit(application)
    notifier = FakeNotifier()

    run(
        _worker(
            jobs, storage, LeaseLosingAiServer(jobs), FakeReportGenerator(), notifier
        ).run_once()
    )

    assert notifier.analysis_ids == []
