"""합성 사진, 실제 임시 PostgreSQL. 외부 S3와 AI는 사용하지 않는다."""
from uuid import UUID

import pytest

from app.api.deps import get_image_storage
from app.core.database import connect
from app.services.card_sets import build_context
from app.services.image_storage import UnconfiguredImageStorage
from tests.card_fixtures import completed_card_set, with_db
from tests.support import run
from tests.test_profile_photos import _api, _upload, MemoryImageStorage


def setup(url):
    api = _api(url, MemoryImageStorage())
    user = api.create_account()
    profile = user.create_profile()["profileId"]
    photo = _upload(user, profile).json()["photoId"]
    return api, user, profile, photo


def patch(user, photo, description):
    return user.call("PATCH", f"/api/v1/profile-photos/{photo}/description",
                     json={"description": description})


def test_correction_is_stored_and_survives_read_and_late_ai(migrated_database_url):
    api, user, profile, photo = setup(migrated_database_url)
    response = patch(user, photo, "  버스를 타고 가족 여행을 갔을 때 찍은 사진  ")
    assert response.status_code == 200
    assert response.json()["description"] == "버스를 타고 가족 여행을 갔을 때 찍은 사진"
    assert response.json()["descriptionSource"] == "caregiver"
    # 뒤늦게 받은 AI 결과는 보관하지만 사용자 정정을 덮지 않는다.
    api.query("UPDATE photos SET analysis_status='completed', description='AI 원래 설명', "
              "model='synthetic-model', prompt_version='image-v1' WHERE photo_id=%s", (photo,))
    read = user.call("GET", f"/api/v1/profile-photos/{photo}").json()
    reread = user.call("GET", f"/api/v1/profiles/{profile}").json()["photos"][0]
    assert read["description"] == reread["description"] == response.json()["description"]
    assert read["descriptionSource"] == "caregiver"
    assert api.query("SELECT description, user_description FROM photos WHERE photo_id=%s", (photo,))[0] == {
        "description": "AI 원래 설명", "user_description": response.json()["description"]}


def test_edit_does_not_require_s3_url_generation(migrated_database_url):
    api, user, _, photo = setup(migrated_database_url)
    api.app.dependency_overrides[get_image_storage] = lambda: UnconfiguredImageStorage()
    assert patch(user, photo, "합성 사진 설명 수정").status_code == 200


@pytest.mark.parametrize("description", ["", "   ", None])
def test_blank_description_is_refused(migrated_database_url, description):
    api, user, _, photo = setup(migrated_database_url)
    assert patch(user, photo, description).status_code == 422
    assert api.query("SELECT user_description FROM photos")[0]["user_description"] is None


def test_other_account_cannot_change_description(migrated_database_url):
    api, _, _, photo = setup(migrated_database_url)
    other = api.create_account()
    assert patch(other, photo, "다른 계정의 수정").status_code == 404


def test_visit_photo_cannot_be_changed_through_profile_api(migrated_database_url):
    api, user, profile, photo = setup(migrated_database_url)
    session = api.query("INSERT INTO visit_sessions(profile_id) VALUES (%s) RETURNING session_id", (profile,))[0]["session_id"]
    api.query("UPDATE photos SET session_id=%s WHERE photo_id=%s", (session, photo))
    assert patch(user, photo, "면회 사진 수정").status_code == 404


def test_corrected_description_enters_card_input_even_after_ai_failure(migrated_database_url):
    api, user, profile, photo = setup(migrated_database_url)
    api.query("UPDATE photos SET analysis_status='failed', error_code='SYNTHETIC' WHERE photo_id=%s", (photo,))
    assert patch(user, photo, "보호자가 적은 사진 설명").status_code == 200
    async def context():
        async with connect(migrated_database_url) as conn:
            return await build_context(conn, UUID(profile))
    assert run(context()).photos[0].description == "보호자가 적은 사진 설명"


def test_correction_blocks_old_ready_cards_but_does_not_regenerate(migrated_database_url):
    api, user, profile, photo = setup(migrated_database_url)
    async def seed(conn):
        return await completed_card_set(conn, UUID(profile))
    set_id, _ = with_db(migrated_database_url, seed)
    assert patch(user, photo, "정정한 사진 설명").status_code == 200
    assert api.query("SELECT stale_at FROM card_sets WHERE set_id=%s", (set_id,))[0]["stale_at"] is not None
    assert api.query("SELECT count(*) AS n FROM card_sets")[0]["n"] == 1


def test_running_cards_reject_description_change_without_partial_save(migrated_database_url):
    api, user, profile, photo = setup(migrated_database_url)
    api.query("INSERT INTO card_sets(profile_id, status, model, prompt_version) "
              "VALUES (%s, 'running', 'synthetic', '1')", (profile,))
    response = patch(user, photo, "보호자 정정")
    assert response.status_code == 409
    assert response.json()["errorCode"] == "CARD_GENERATION_IN_PROGRESS"
    assert api.query("SELECT user_description FROM photos")[0]["user_description"] is None
