"""AI 사진 분석 동의(`photoAnalysis`)를 거둘 때(1-6) 저장된 AI 설명의 정리 검증.

2026-11-09 PM 결정: 철회하면 저장된 AI 설명을 더 쓰지 않는다. 임시 DB에 최신 migration을
적용해 실행한다(`conftest.py`). 계정, 사진과 설명은 모두 합성이며 S3와 ML API는 부르지
않는다(메모리 사진 저장소와 합성 분석 함수).
"""

import asyncio
import threading
from uuid import UUID

from photo_analysis import PhotoDescription
from psycopg.types.json import Jsonb

from app.core.database import connect
from app.services.accounts import PostgresAccountRepository
from app.services.card_generation_jobs import CardGenerationQueue
from app.services.card_sets import CardGenerationProcessor, build_context
from app.services.photo_analysis_jobs import PhotoAnalysisQueue
from app.services.photo_analysis_pipeline import PhotoAnalysisProcessor
from app.workers.base import Worker
from tests.card_fixtures import completed_card_set, visit_with, with_db
from tests.support import run
from tests.test_card_generation_worker import _exclude, fake_result
from tests.test_photo_analysis_pipeline import FreshSyntheticStorage, setup, worker
from tests.test_photo_description import patch


def _analyse(url: str, description: str = "합성 AI 설명") -> None:
    taken = run(worker(url, lambda _: PhotoDescription(description=description)).run_once())
    assert taken


def _withdraw(user) -> None:
    response = user.call("PATCH", "/auth/me/consents", json={"photoAnalysis": False})
    assert response.status_code == 200, response.text
    assert response.json()["consent"]["photoAnalysis"] == {"granted": False, "grantedAt": None}


def _photo(api, photo: str) -> dict:
    return api.query(
        "SELECT analysis_status, description, model, prompt_version, user_description, "
        "       error_code, lease_expires_at FROM photos WHERE photo_id = %s",
        (photo,),
    )[0]


def _card_input_photos(url: str, profile: str) -> list[tuple[str, str]]:
    async def build(connection):
        return await build_context(connection, UUID(profile))

    return [(str(p.photo_id), p.description) for p in with_db(url, build).photos]


PENDING_WITHOUT_AI = {
    "analysis_status": "pending",
    "description": None,
    "model": None,
    "prompt_version": None,
    "user_description": None,
    "error_code": None,
    "lease_expires_at": None,
}


def test_withdrawal_clears_ai_descriptions_and_marks_unused_cards_stale(
    migrated_database_url,
):
    url = migrated_database_url
    api, user, profile, photo = setup(url)
    _analyse(url)
    _, _, other_profile, other_photo = setup(url)
    _analyse(url, "다른 계정의 합성 AI 설명")

    async def seed(connection):
        used, _ = await completed_card_set(connection, UUID(profile))
        await visit_with(connection, UUID(profile), used, evaluated=True)
        unused, _ = await completed_card_set(connection, UUID(profile))
        other, _ = await completed_card_set(connection, UUID(other_profile))
        return used, unused, other

    used, unused, other = with_db(url, seed)

    # 다른 선택 동의만 바꾸거나 이미 동의한 사진 분석을 다시 켜면 AI 설명을 지우지 않는다.
    for change in ({"serviceImprovement": True}, {"photoAnalysis": True}):
        assert user.call("PATCH", "/auth/me/consents", json=change).status_code == 200
        assert _photo(api, photo)["description"] == "합성 AI 설명"

    _withdraw(user)

    assert _photo(api, photo) == PENDING_WITHOUT_AI
    assert _card_input_photos(url, profile) == []
    stale = {
        row["set_id"]: row["stale_at"]
        for row in api.query("SELECT set_id, stale_at FROM card_sets")
    }
    # 아직 안 쓴 묶음만 갱신 대상이다. 면회에 쓴 묶음과 다른 계정의 묶음은 그대로다.
    assert stale[unused] is not None
    assert stale[used] is None
    assert stale[other] is None
    assert _photo(api, other_photo)["description"] == "다른 계정의 합성 AI 설명"
    read = user.call("GET", f"/api/v1/profile-photos/{photo}").json()
    assert (read["analysisStatus"], read["description"], read["descriptionSource"]) == (
        "pending", None, None)


def test_caregiver_description_is_kept_and_cards_stay_current(migrated_database_url):
    url = migrated_database_url
    api, user, profile, photo = setup(url)
    _analyse(url)
    assert patch(user, photo, "보호자가 쓴 합성 설명").status_code == 200

    async def seed(connection):
        set_id, _ = await completed_card_set(connection, UUID(profile))
        return set_id

    set_id = with_db(url, seed)

    _withdraw(user)

    assert _photo(api, photo) == {**PENDING_WITHOUT_AI, "user_description": "보호자가 쓴 합성 설명"}
    # 카드 입력은 보호자 설명 그대로라 묶음을 다시 만들 필요가 없다.
    assert _card_input_photos(url, profile) == [(photo, "보호자가 쓴 합성 설명")]
    assert api.query("SELECT stale_at FROM card_sets WHERE set_id = %s", (set_id,)) == [
        {"stale_at": None}
    ]
    read = user.call("GET", f"/api/v1/profile-photos/{photo}").json()
    assert (read["analysisStatus"], read["description"], read["descriptionSource"]) == (
        "pending", "보호자가 쓴 합성 설명", "caregiver")


def test_withdrawal_during_card_generation_succeeds_and_result_needs_refresh(
    migrated_database_url,
):
    url = migrated_database_url
    api, user, profile, photo = setup(url)
    _analyse(url)
    api.query("UPDATE profiles SET hobby = '합성 취미' WHERE profile_id = %s", (profile,))
    api.query(
        "INSERT INTO card_sets (profile_id, status, model, prompt_version) "
        "VALUES (%s, 'running', 'synthetic', '1')",
        (profile,),
    )
    sent = []

    def generate(request):
        sent.extend(p.description for p in request.context.photos)
        # 카드를 만드는 중에도 동의 변경은 거절하지 않는다(card_sets.mark_stale의 409를 쓰지 않음).
        _withdraw(user)
        return fake_result(request)

    async def scenario():
        async with connect(url) as connection:
            queue = CardGenerationQueue()
            job = await queue.claim(connection, lease_seconds=60)
            await CardGenerationProcessor(queue=queue, generate=generate)(connection, job)

    run(scenario())

    assert sent == ["합성 AI 설명"]
    assert _photo(api, photo) == PENDING_WITHOUT_AI
    # 철회 전 설명으로 만든 묶음은 다음 대화 준비 때 다시 만든다.
    row = api.query("SELECT status, stale_at FROM card_sets")[0]
    assert row["status"] == "completed" and row["stale_at"] is not None


def test_withdrawal_during_analysis_discards_the_late_result(migrated_database_url):
    url = migrated_database_url
    api, user, _, photo = setup(url)

    def analyze(_url):
        _withdraw(user)
        return PhotoDescription(description="철회 뒤에 끝난 합성 분석")

    run(worker(url, analyze).run_once())

    assert _photo(api, photo) == PENDING_WITHOUT_AI


class _ChangeBeforeVendorCall(FreshSyntheticStorage):
    """worker가 사진을 가져가 조회 주소를 만든 직후, 업체를 부르기 전에 `change`를 실행한다."""

    def __init__(self, change) -> None:
        super().__init__()
        self._change = change

    async def create_download(self, *, object_key):
        download = await super().create_download(object_key=object_key)
        await asyncio.to_thread(self._change)
        return download


def _analyse_after(url: str, change, calls: list) -> bool:
    def analyze(photo_url):
        calls.append(photo_url)
        return PhotoDescription(description="동의 확인 뒤 만든 합성 설명")

    return run(Worker(
        queue=PhotoAnalysisQueue(),
        process=PhotoAnalysisProcessor(storage=_ChangeBeforeVendorCall(change), analyze=analyze,
                                       model="synthetic-model", timeout_seconds=30),
        open_connection=lambda: connect(url), lease_seconds=60,
    ).run_once())


def test_withdrawal_after_the_photo_is_taken_stops_the_vendor_call(migrated_database_url):
    # worker가 사진을 가져간 뒤 업체를 부르기 전에 철회하면 사진을 업체에 보내지 않는다.
    url = migrated_database_url
    api, user, _, photo = setup(url)
    calls = []

    assert _analyse_after(url, lambda: _withdraw(user), calls)

    assert calls == []
    assert _photo(api, photo) == PENDING_WITHOUT_AI
    # 철회한 동안에는 다시 가져가지 않는다.
    assert not run(worker(url, lambda u: calls.append(u)).run_once())
    assert calls == []


def test_vendor_is_called_when_photo_analysis_consent_remains(migrated_database_url):
    # 그사이 다른 선택 동의만 바꿔 동의 이력이 새로 생겨도 사진 분석 동의가 켜져 있으면 부른다.
    url = migrated_database_url
    api, user, _, photo = setup(url)

    def change_other_consent():
        response = user.call("PATCH", "/auth/me/consents", json={"serviceImprovement": True})
        assert response.status_code == 200, response.text
        assert response.json()["consent"]["photoAnalysis"]["granted"] is True

    calls = []

    assert _analyse_after(url, change_other_consent, calls)

    assert len(calls) == 1
    row = _photo(api, photo)
    assert (row["analysis_status"], row["description"]) == (
        "completed", "동의 확인 뒤 만든 합성 설명")


async def _until_lock_waits(watcher, count: int, *, unless=None) -> None:
    """이 시험 DB에서 잠금을 기다리는 연결이 `count`개가 되거나 `unless`가 끝날 때까지."""
    for _ in range(400):
        if unless is not None and unless.done():
            return
        cursor = await watcher.execute(
            "SELECT count(*) AS n FROM pg_stat_activity "
            "WHERE datname = current_database() AND wait_event_type = 'Lock'"
        )
        if (await cursor.fetchone())["n"] >= count:
            return
        await asyncio.sleep(0.05)
    raise AssertionError("잠금 대기를 확인하지 못했다")


def test_check_before_vendor_call_waits_for_a_withdrawal_in_progress(migrated_database_url):
    # 철회 트랜잭션이 프로필을 잠근 채 아직 커밋하지 않았을 때 worker가 사진을 가져가면,
    # 업체 호출 전 확인은 프로필 잠금에서 기다렸다가 철회를 보고 업체를 부르지 않는다.
    # 프로필을 잠그지 않으면 커밋 전이라 동의가 켜진 것으로 읽고 업체를 부른다.
    url = migrated_database_url
    api, _, profile, photo = setup(url)
    user_id = api.query("SELECT user_id FROM profiles WHERE profile_id = %s", (profile,))[0][
        "user_id"
    ]
    calls = []

    def analyze(photo_url):
        calls.append(photo_url)
        return PhotoDescription(description="철회와 겹친 합성 설명")

    async def scenario():
        async with connect(url) as withdrawal, connect(url) as watcher:
            async with withdrawal.transaction():
                accounts = PostgresAccountRepository(withdrawal, default_display_name="보호자")
                changed = await accounts.change_optional_consents(
                    str(user_id), {"photoAnalysis": False}
                )
                assert changed is not None
                analysis = asyncio.create_task(worker(url, analyze, timeout=30).run_once())
                await _until_lock_waits(watcher, 1, unless=analysis)
            assert await analysis

    run(scenario())

    assert calls == []
    assert _photo(api, photo) == PENDING_WITHOUT_AI


def test_withdrawal_waits_for_an_analysis_result_being_saved(migrated_database_url):
    # 분석 결과를 저장하는 트랜잭션이 끝나기 전에 철회가 들어오면, 철회는 프로필 잠금에서
    # 기다렸다가 저장된 설명을 지운다. 프로필을 잠그지 않으면 철회의 UPDATE는 아직
    # `processing`으로 보이는 사진을 건너뛰고, 뒤이어 커밋된 결과가 설명을 되살린다.
    url = migrated_database_url
    api, user, profile, photo = setup(url)

    async def seed(connection):
        set_id, _ = await completed_card_set(connection, UUID(profile))
        return set_id

    unused = with_db(url, seed)
    called, release = threading.Event(), threading.Event()

    def analyze(_url):
        called.set()
        assert release.wait(30)
        return PhotoDescription(description="합성 AI 설명")

    async def scenario():
        async with connect(url) as blocker, connect(url) as watcher:
            analysis = asyncio.create_task(worker(url, analyze, timeout=60).run_once())
            assert await asyncio.to_thread(called.wait, 30)
            async with blocker.transaction():
                # 업체 응답 뒤 결과 저장 트랜잭션이 프로필을 잠근 채 사진 행에서 멈추게 한다.
                await blocker.execute(
                    "SELECT 1 FROM photos WHERE photo_id = %s FOR UPDATE", (photo,)
                )
                release.set()
                await _until_lock_waits(watcher, 1)
                withdrawal = asyncio.create_task(asyncio.to_thread(_withdraw, user))
                await _until_lock_waits(watcher, 2, unless=withdrawal)
            assert await analysis
            await withdrawal

    run(scenario())

    assert _photo(api, photo) == PENDING_WITHOUT_AI
    assert api.query("SELECT stale_at FROM card_sets WHERE set_id = %s", (unused,))[0][
        "stale_at"
    ] is not None


def test_consenting_again_reanalyses_the_photo(migrated_database_url):
    url = migrated_database_url
    api, user, _, photo = setup(url)
    _analyse(url, "처음 만든 합성 설명")
    _withdraw(user)

    calls = []
    assert not run(worker(url, lambda u: calls.append(u)).run_once())
    assert calls == []

    granted = user.call("PATCH", "/auth/me/consents", json={"photoAnalysis": True})
    assert granted.status_code == 200
    _analyse(url, "다시 만든 합성 설명")

    row = _photo(api, photo)
    assert (row["analysis_status"], row["description"]) == ("completed", "다시 만든 합성 설명")


def test_topic_based_only_on_a_withdrawn_ai_description_is_not_sent(migrated_database_url):
    """AI 설명을 지운 사진(보호자 설명 없음)은 카드 입력에서 빠지므로, 근거가 그 사진뿐인 주제도
    제외 여부와 상관없이 다음 카드 생성 입력에서 빠진다(근거가 사라진 주제 규칙, 2026-11-08과
    2026-11-09 PM 결정). 저장된 주제는 그대로이며, 다시 동의해 분석이 끝나거나 보호자가 설명을
    쓰면 사진과 함께 다시 들어간다."""
    url = migrated_database_url
    api, user, profile, photo = setup(url)
    _analyse(url)

    async def seed(connection):
        # 제외한 주제의 근거 사진은 제외 규칙으로 입력에서 빠지므로 다른 주제와 겹치지 않게 따로 둔다.
        other = await connection.execute(
            "INSERT INTO photos (profile_id, s3_object_key, description, analysis_status, model,"
            " prompt_version) VALUES (%s, %s, '다른 합성 AI 설명', 'completed', 'synthetic-model',"
            " 'photo-1') RETURNING photo_id",
            (profile, f"synthetic/{profile}/other.jpg"),
        )
        other_photo = str((await other.fetchone())["photo_id"])
        set_id, _ = await completed_card_set(connection, UUID(profile))
        await visit_with(connection, UUID(profile), set_id, evaluated=True)
        cursor = await connection.execute(
            "SELECT position, topic_id FROM conversation_cards WHERE set_id = %s", (set_id,)
        )
        topics = {row["position"]: row["topic_id"] for row in await cursor.fetchall()}
        evidence = {
            1: [{"photoId": photo}],  # 사진만 근거
            2: [{"photoId": other_photo}],  # 사진만 근거, 보호자가 제외함
            3: [{"photoId": photo}, {"profileField": "hobby"}],  # 세부 정보 칸도 근거
        }
        for position, items in evidence.items():
            await connection.execute(
                "UPDATE profile_topics SET evidence = %s WHERE topic_id = %s",
                (Jsonb(items), topics[position]),
            )
        await _exclude(connection, UUID(profile), set_id, topics[2])
        return other_photo, topics

    other_photo, topics = with_db(url, seed)
    every_topic = set(topics.values())

    def sent_topics() -> set:
        async def build(connection):
            return await build_context(connection, UUID(profile))

        return {topic.topic_id for topic in with_db(url, build).topics}

    assert sent_topics() == every_topic

    _withdraw(user)

    assert _card_input_photos(url, profile) == []
    assert sent_topics() == every_topic - {topics[1], topics[2]}
    assert api.query(
        "SELECT evidence FROM profile_topics WHERE topic_id = %s", (topics[2],)
    ) == [{"evidence": [{"photoId": other_photo}]}]

    # 다시 동의해 분석이 끝나면 사진과 주제가 다시 들어간다.
    granted = user.call("PATCH", "/auth/me/consents", json={"photoAnalysis": True})
    assert granted.status_code == 200
    _analyse(url, "다시 만든 합성 AI 설명")
    _analyse(url, "다시 만든 합성 AI 설명")
    assert sent_topics() == every_topic

    # 보호자가 쓴 설명이 있으면 철회해도 사진이 입력에 남으므로 주제도 남는다.
    for target in (photo, other_photo):
        assert patch(user, target, "보호자가 쓴 합성 설명").status_code == 200
    _withdraw(user)
    # 제외한 주제의 근거 사진은 제외 규칙으로 늘 빠지지만, 남아 있으므로 그 주제는 넣는다.
    assert _card_input_photos(url, profile) == [(photo, "보호자가 쓴 합성 설명")]
    assert sent_topics() == every_topic
