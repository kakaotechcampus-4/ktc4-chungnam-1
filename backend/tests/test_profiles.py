"""프로필 API (2-1 ~ 2-4, 2-8) 검증.

임시 DB에 최신 migration을 적용해 실행한다(`conftest.py`). 값은 모두 합성 데이터다.
"""

import asyncio
from datetime import date
from uuid import UUID, uuid4

from app.core.database import connect
from app.core.errors import AppError
from app.services import profiles
from tests.db_api import DbApi, profile_body
from tests.support import run

MISSING_ID = "00000000-0000-4000-8000-000000000999"


def _add_card_set(api: DbApi, profile_id: str) -> None:
    api.query(
        "INSERT INTO card_sets (profile_id, status, model, prompt_version) "
        "VALUES (%s, 'running', 'synthetic-model', 'card-v1')",
        (profile_id,),
    )


def test_created_profile_starts_in_progress_with_empty_details(
    migrated_database_url,
):
    caregiver = DbApi(migrated_database_url).create_account()

    response = caregiver.call(
        "POST",
        "/api/v1/profiles",
        json=profile_body(condition={"stage": "unknown", "symptomNote": "합성 메모"}),
    )

    assert response.status_code == 201
    body = response.json()
    UUID(body.pop("profileId"))
    assert body.pop("createdAt")
    assert body == {
        "schemaVersion": 1,
        "setupStatus": "inProgress",
        "name": "합성 어르신",
        "gender": "female",
        "birthDate": "1943-03-12",
        "condition": {"stage": "unknown", "symptomNote": "합성 메모"},
        "occupation": None,
        "hometown": None,
        "hobby": None,
        "family": None,
        "lifeFacts": [],
        "photos": [],
    }


def test_invalid_basic_information_is_rejected(migrated_database_url):
    caregiver = DbApi(migrated_database_url).create_account()

    invalid_bodies = [
        profile_body(name="가" * 51),
        profile_body(name="   "),
        profile_body(gender="unknown"),
        profile_body(birthDate="1943-13-01"),
        profile_body(condition={"stage": "severe"}),
        profile_body(occupation="합성 직업"),
        {"name": "합성 어르신", "gender": "female", "birthDate": "1943-03-12"},
    ]
    statuses = [
        caregiver.call("POST", "/api/v1/profiles", json=body).json()["errorCode"]
        for body in invalid_bodies
    ]

    assert statuses == ["INVALID_REQUEST"] * len(invalid_bodies)
    assert caregiver.call("GET", "/api/v1/profiles").json()["profiles"] == []


def test_list_keeps_creation_order_and_computes_setup_status(migrated_database_url):
    api = DbApi(migrated_database_url)
    caregiver = api.create_account()
    first = caregiver.create_profile(name="첫째", gender="male")
    second = caregiver.create_profile(name="둘째")
    _add_card_set(api, second["profileId"])
    api.create_account().create_profile(name="다른 계정")

    response = caregiver.call("GET", "/api/v1/profiles")

    assert response.status_code == 200
    assert response.json() == {
        "schemaVersion": 1,
        "profiles": [
            {
                "profileId": first["profileId"],
                "name": "첫째",
                "gender": "male",
                "setupStatus": "inProgress",
            },
            {
                "profileId": second["profileId"],
                "name": "둘째",
                "gender": "female",
                "setupStatus": "completed",
            },
        ],
    }


def test_fourth_profile_is_refused(migrated_database_url):
    api = DbApi(migrated_database_url)
    caregiver = api.create_account()
    for index in range(profiles.PROFILE_LIMIT):
        caregiver.create_profile(name=f"합성 어르신 {index}")

    refused = caregiver.call("POST", "/api/v1/profiles", json=profile_body())
    other = api.create_account().call("POST", "/api/v1/profiles", json=profile_body())

    assert refused.status_code == 409
    assert refused.json()["errorCode"] == "PROFILE_LIMIT_EXCEEDED"
    assert len(caregiver.call("GET", "/api/v1/profiles").json()["profiles"]) == 3
    assert other.status_code == 201


def test_concurrent_creation_does_not_exceed_the_limit(migrated_database_url):
    account_id = DbApi(migrated_database_url).create_account().account_id

    async def create_one() -> str:
        async with connect(migrated_database_url) as connection:
            try:
                await profiles.create_profile(
                    connection,
                    account_id=account_id,
                    name="합성 어르신",
                    gender="female",
                    birth_date=date(1943, 3, 12),
                    condition_stage="unknown",
                    symptom_note=None,
                )
            except AppError as error:
                return error.error_code
            return "created"

    async def scenario() -> list[str]:
        return await asyncio.gather(*(create_one() for _ in range(6)))

    results = run(scenario())

    assert sorted(results) == ["PROFILE_LIMIT_EXCEEDED"] * 3 + ["created"] * 3


def test_detail_returns_life_facts_in_creation_order(migrated_database_url):
    api = DbApi(migrated_database_url)
    caregiver = api.create_account()
    profile_id = caregiver.create_profile()["profileId"]
    for title in ("첫 생애 정보", "둘째 생애 정보"):
        caregiver.call(
            "POST",
            f"/api/v1/profiles/{profile_id}/life-facts",
            json={"title": title, "content": "합성 내용"},
        )

    response = caregiver.call("GET", f"/api/v1/profiles/{profile_id}")

    assert response.status_code == 200
    body = response.json()
    assert body["setupStatus"] == "inProgress"
    assert [fact["title"] for fact in body["lifeFacts"]] == [
        "첫 생애 정보",
        "둘째 생애 정보",
    ]
    assert {fact["profileId"] for fact in body["lifeFacts"]} == {profile_id}
    assert body["photos"] == []


def test_other_accounts_profile_looks_missing(migrated_database_url):
    api = DbApi(migrated_database_url)
    owner = api.create_account()
    stranger = api.create_account()
    profile_id = owner.create_profile()["profileId"]

    responses = [
        stranger.call("GET", f"/api/v1/profiles/{profile_id}"),
        stranger.call("PATCH", f"/api/v1/profiles/{profile_id}", json={"hobby": "합성"}),
        stranger.call("DELETE", f"/api/v1/profiles/{profile_id}"),
        owner.call("GET", f"/api/v1/profiles/{MISSING_ID}"),
    ]

    assert [r.status_code for r in responses] == [404] * 4
    assert {r.json()["errorCode"] for r in responses} == {"PROFILE_NOT_FOUND"}
    assert len({r.json()["message"] for r in responses}) == 1
    malformed = owner.call("GET", "/api/v1/profiles/not-a-uuid")
    assert malformed.status_code == 422
    assert malformed.json()["errorCode"] == "INVALID_REQUEST"
    assert owner.call("GET", f"/api/v1/profiles/{profile_id}").json()["hobby"] is None


def test_patch_changes_only_the_sent_fields(migrated_database_url):
    caregiver = DbApi(migrated_database_url).create_account()
    created = caregiver.create_profile(
        condition={"stage": "unknown", "symptomNote": "처음 메모"}
    )
    path = f"/api/v1/profiles/{created['profileId']}"

    first = caregiver.call(
        "PATCH",
        path,
        json={
            "condition": {"stage": "mildDementia", "symptomNote": "합성 증상 메모"},
            "hobby": "노래 부르기를 좋아하셨어요.",
            "family": "합성 가족 이야기",
        },
    )
    second = caregiver.call("PATCH", path, json={"family": None, "name": "고친 이름"})
    unchanged = caregiver.call("PATCH", path, json={})

    assert first.status_code == 200
    assert first.json()["condition"] == {
        "stage": "mildDementia",
        "symptomNote": "합성 증상 메모",
    }
    assert first.json()["hobby"] == "노래 부르기를 좋아하셨어요."
    body = second.json()
    assert body["name"] == "고친 이름"
    assert body["family"] is None
    assert body["hobby"] == "노래 부르기를 좋아하셨어요."
    assert body["condition"]["stage"] == "mildDementia"
    assert (body["gender"], body["birthDate"]) == ("female", "1943-03-12")
    assert unchanged.status_code == 200
    assert unchanged.json() == body


def test_patch_without_symptom_note_clears_it(migrated_database_url):
    caregiver = DbApi(migrated_database_url).create_account()
    created = caregiver.create_profile(
        condition={"stage": "unknown", "symptomNote": "처음 메모"}
    )

    response = caregiver.call(
        "PATCH",
        f"/api/v1/profiles/{created['profileId']}",
        json={"condition": {"stage": "mildDementia"}},
    )

    assert response.json()["condition"] == {
        "stage": "mildDementia",
        "symptomNote": None,
    }


def test_patch_rejects_blank_details_and_cleared_basic_fields(migrated_database_url):
    caregiver = DbApi(migrated_database_url).create_account()
    created = caregiver.create_profile()
    path = f"/api/v1/profiles/{created['profileId']}"

    invalid_bodies = [
        {"hobby": ""},
        {"occupation": "   "},
        {"name": None},
        {"gender": None},
        {"birthDate": None},
        {"condition": None},
        {"name": "가" * 51},
        {"setupStatus": "completed"},
    ]
    codes = [
        caregiver.call("PATCH", path, json=body).json()["errorCode"]
        for body in invalid_bodies
    ]

    assert codes == ["INVALID_REQUEST"] * len(invalid_bodies)
    stored = caregiver.call("GET", path).json()
    assert stored == created


def test_deleting_a_profile_keeps_the_account_and_other_profiles(
    migrated_database_url,
):
    caregiver = DbApi(migrated_database_url).create_account()
    kept = caregiver.create_profile(name="남길 어르신")
    removed = caregiver.create_profile(name="지울 어르신")

    response = caregiver.call("DELETE", f"/api/v1/profiles/{removed['profileId']}")
    again = caregiver.call("DELETE", f"/api/v1/profiles/{removed['profileId']}")

    assert response.status_code == 204
    assert response.content == b""
    assert again.status_code == 404
    listed = caregiver.call("GET", "/api/v1/profiles").json()["profiles"]
    assert [p["profileId"] for p in listed] == [kept["profileId"]]
    assert caregiver.call("GET", "/auth/me").status_code == 200


def test_last_profile_can_be_deleted(migrated_database_url):
    caregiver = DbApi(migrated_database_url).create_account()
    profile_id = caregiver.create_profile()["profileId"]

    response = caregiver.call("DELETE", f"/api/v1/profiles/{profile_id}")

    assert response.status_code == 204
    assert caregiver.call("GET", "/api/v1/profiles").json()["profiles"] == []


async def seed_profile_records(connection, profile_id: UUID) -> list[str]:
    """프로필 아래에 카드, 주제, 면회, 사진과 음성 작업을 하나씩 만든다.

    `conversation_cards`의 `profile_topics` 참조에는 `ON DELETE`가 없으므로, 카드와 주제가
    함께 있어야 CASCADE 순서를 확인할 수 있다. 사진과 음성의 객체 키를 돌려준다.
    """

    async def insert(query, params):
        cursor = await connection.execute(query, params)
        return next(iter((await cursor.fetchone()).values()))

    set_id = await insert(
        "INSERT INTO card_sets (profile_id, status, model, prompt_version, "
        " generation_log) "
        "VALUES (%s, 'completed', 'synthetic-model', 'card-v1', "
        " '{\"input\": {}}') RETURNING set_id",
        (profile_id,),
    )
    topic_id = await insert(
        "INSERT INTO profile_topics (profile_id, title, description) "
        "VALUES (%s, '합성 주제', '합성 설명') RETURNING topic_id",
        (profile_id,),
    )
    await insert(
        "INSERT INTO conversation_cards "
        "(set_id, profile_id, topic_id, card_title, position, description, "
        " primary_question, follow_up_questions, evidence_source) "
        "VALUES (%s, %s, %s, '합성 카드', 1, '합성 설명', '합성 질문', "
        " ARRAY['합성 후속 질문'], 'none') RETURNING card_id",
        (set_id, profile_id, topic_id),
    )
    session_id = await insert(
        "INSERT INTO visit_sessions (profile_id) VALUES (%s) RETURNING session_id",
        (profile_id,),
    )
    keys = [
        f"synthetic/photos/{uuid4().hex}.jpg",
        f"synthetic/photos/{uuid4().hex}.jpg",
        f"synthetic/speech/{uuid4().hex}.wav",
    ]
    await insert(
        "INSERT INTO photos (profile_id, s3_object_key) VALUES (%s, %s) "
        "RETURNING photo_id",
        (profile_id, keys[0]),
    )
    await insert(
        "INSERT INTO photos (profile_id, session_id, s3_object_key) "
        "VALUES (%s, %s, %s) RETURNING photo_id",
        (profile_id, session_id, keys[1]),
    )
    await insert(
        "INSERT INTO speech_analysis_jobs "
        "(analysis_id, session_id, status, participant_count, s3_object_key, "
        " lease_expires_at, data_expires_at) "
        "VALUES (%s, %s, 'uploading', 2, %s, now() + interval '1 hour', "
        " now() + interval '1 day') RETURNING analysis_id",
        (uuid4(), session_id, keys[2]),
    )
    return keys


PROFILE_TABLES = (
    "profiles",
    "life_facts",
    "card_sets",
    "profile_topics",
    "conversation_cards",
    "visit_sessions",
    "photos",
    "speech_analysis_jobs",
)


def count_rows(api: DbApi, profile_id: str) -> dict[str, int]:
    return {
        table: api.query(
            f"SELECT count(*) AS n FROM {table} WHERE "
            + (
                "session_id IN (SELECT session_id FROM visit_sessions "
                "WHERE profile_id = %s)"
                if table == "speech_analysis_jobs"
                else "profile_id = %s"
            ),
            (profile_id,),
        )[0]["n"]
        for table in PROFILE_TABLES
    }


def test_deleting_a_profile_with_cards_and_topics_removes_its_records(
    migrated_database_url,
):
    api = DbApi(migrated_database_url)
    caregiver = api.create_account()
    removed = caregiver.create_profile(name="지울 어르신")["profileId"]
    kept = caregiver.create_profile(name="남길 어르신")["profileId"]

    async def seed() -> tuple[list[str], list[str]]:
        async with connect(migrated_database_url) as connection:
            return (
                await seed_profile_records(connection, UUID(removed)),
                await seed_profile_records(connection, UUID(kept)),
            )

    removed_keys, kept_keys = run(seed())
    caregiver.call(
        "POST",
        f"/api/v1/profiles/{removed}/life-facts",
        json={"title": "합성 제목", "content": "합성 내용"},
    )

    response = caregiver.call("DELETE", f"/api/v1/profiles/{removed}")

    assert response.status_code == 204
    assert set(count_rows(api, removed).values()) == {0}
    assert min(
        count for table, count in count_rows(api, kept).items() if table != "life_facts"
    ) == 1
    queued = {
        row["s3_object_key"]
        for row in api.query("SELECT s3_object_key FROM storage_deletion_request_queue")
    }
    assert queued == set(removed_keys)
    assert queued.isdisjoint(kept_keys)
