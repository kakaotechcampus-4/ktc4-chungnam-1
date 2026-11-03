"""배포 준비용 분석 접수와 새 작업 임대 제어. 관리 HTTP API는 제공하지 않는다."""

from contextlib import asynccontextmanager

from app.core.errors import AppError

# 세션 잠금은 프로세스/연결이 끊기면 PostgreSQL이 해제한다. 자료 ID는 저장하지 않는다.
WORKER_ACTIVITY_LOCK = 60110301
SHORT_SPEECH_ACTIVITY_LOCK = 60110302


async def _state(connection, *, lock=False):
    cursor = await connection.execute(
        "SELECT admissions_paused, claims_paused FROM deployment_control WHERE singleton"
        + (" FOR SHARE" if lock else "")
    )
    row = await cursor.fetchone()
    if row is None:
        raise RuntimeError("DEPLOYMENT_CONTROL_MISSING")
    return row


async def assert_admission_open(connection):
    """호출자가 생성 트랜잭션 안에서 부른다. pause와 접수를 직렬화한다."""
    if (await _state(connection, lock=True))["admissions_paused"]:
        raise AppError(status_code=503, error_code="SERVICE_MAINTENANCE",
                       message="서비스 점검 중입니다. 잠시 후 다시 시도해 주세요.", retryable=True)


async def _activity(connection, key, *, release=False):
    function = "pg_advisory_unlock_shared" if release else "pg_advisory_lock_shared"
    await connection.execute(f"SELECT {function}(%s::bigint)", (key,))


@asynccontextmanager
async def short_speech_admission(connection):
    # 긴 외부 요청 동안 행 잠금을 붙잡지 않는다. 접수 확인과 실행 표지만 원자적으로 남긴다.
    async with connection.transaction():
        await assert_admission_open(connection)
        await _activity(connection, SHORT_SPEECH_ACTIVITY_LOCK)
    try:
        yield
    finally:
        await _activity(connection, SHORT_SPEECH_ACTIVITY_LOCK, release=True)


async def claim_job(connection, claim):
    acquired = False
    try:
        async with connection.transaction():
            if (await _state(connection, lock=True))["claims_paused"]:
                return None
            await _activity(connection, WORKER_ACTIVITY_LOCK)
            acquired = True
            job = await claim()
        if job is None:
            await finish_job(connection)
            acquired = False
        return job
    except BaseException:
        if acquired:
            await finish_job(connection)
        raise


async def finish_job(connection):
    await _activity(connection, WORKER_ACTIVITY_LOCK, release=True)


async def set_control(connection, action):
    async with connection.transaction():
        await connection.execute("SET LOCAL lock_timeout = '3000ms'")
        row = await (await connection.execute(
            "SELECT * FROM deployment_control WHERE singleton FOR UPDATE"
        )).fetchone()
        if row is None:
            raise RuntimeError("DEPLOYMENT_CONTROL_MISSING")
        admissions, claims = row["admissions_paused"], row["claims_paused"]
        if action == "pause-admissions":
            admissions = True
        elif action == "pause-all":
            admissions = claims = True
        elif action == "pause-workers":
            if not admissions:
                raise ValueError("PAUSE_ADMISSIONS_FIRST")
            claims = True
        elif action == "resume-workers":
            claims = False
        elif action == "resume-all":
            admissions = claims = False
        else:
            raise ValueError("UNKNOWN_CONTROL_ACTION")
        await connection.execute(
            "UPDATE deployment_control SET admissions_paused=%s, claims_paused=%s, updated_at=now() "
            "WHERE singleton", (admissions, claims),
        )


async def snapshot(connection):
    """읽기 전용 집계. 본문, 사용자 ID, 연결 주소는 조회하지 않는다."""
    state = await _state(connection)
    counts = await (await connection.execute("""
        SELECT
          (SELECT count(*) FROM speech_analysis_jobs
           WHERE status IN ('uploading','transcribing','generatingReport')) AS active_speech,
          (SELECT count(*) FROM speech_analysis_jobs WHERE status='queued') AS queued_speech,
          (SELECT count(*) FROM card_sets WHERE status='running' AND lease_expires_at IS NOT NULL) AS active_cards,
          (SELECT count(*) FROM card_sets WHERE status='running' AND lease_expires_at IS NULL) AS queued_cards,
          (SELECT count(*) FROM photos WHERE analysis_status='processing') AS active_photos,
          (SELECT count(*) FROM photos WHERE analysis_status='pending' AND session_id IS NULL) AS queued_photos,
          (SELECT count(*) FROM pg_locks WHERE locktype='advisory' AND granted
             AND database=(SELECT oid FROM pg_database WHERE datname=current_database())
             AND classid=0 AND objsubid=1 AND objid=%s) AS worker_executions,
          (SELECT count(*) FROM pg_locks WHERE locktype='advisory' AND granted
             AND database=(SELECT oid FROM pg_database WHERE datname=current_database())
             AND classid=0 AND objsubid=1 AND objid=%s) AS short_speech_executions
        """, (WORKER_ACTIVITY_LOCK, SHORT_SPEECH_ACTIVITY_LOCK))).fetchone()
    idle = not any(counts[key] for key in (
        "active_speech", "active_cards", "active_photos", "worker_executions", "short_speech_executions",
    ))
    return {"admissionsPaused": state["admissions_paused"],
            "workerClaimsPaused": state["claims_paused"], "counts": counts,
            "analysisDrained": state["admissions_paused"] and state["claims_paused"] and idle}
