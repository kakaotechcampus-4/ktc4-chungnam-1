"""AI 사진 분석 동의(`photoAnalysis`)를 거둘 때(1-6) 저장된 AI 설명의 정리 검증.

2026-11-09 PM 결정: 철회하면 저장된 AI 설명을 더 쓰지 않는다. 임시 DB에 최신 migration을
적용해 실행한다(`conftest.py`). 계정, 사진과 설명은 모두 합성이며 S3와 ML API는 부르지
않는다(메모리 사진 저장소와 합성 분석 함수).
"""

from uuid import UUID

from photo_analysis import PhotoDescription

from app.core.database import connect
from app.services.card_generation_jobs import CardGenerationQueue
from app.services.card_sets import CardGenerationProcessor, build_context
from tests.card_fixtures import completed_card_set, visit_with, with_db
from tests.support import run
from tests.test_card_generation_worker import fake_result
from tests.test_photo_analysis_pipeline import setup, worker
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

    # 다른 선택 동의만 바꾸면 AI 설명을 지우지 않는다.
    user.call("PATCH", "/auth/me/consents", json={"serviceImprovement": True})
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
