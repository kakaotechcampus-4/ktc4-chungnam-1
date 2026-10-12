"""생애 정보 API (2-6, 2-7)와 `create_life_fact` 검증.

임시 DB에 최신 migration을 적용해 실행한다(`conftest.py`). 값은 모두 합성 데이터다.
"""

from uuid import UUID

from psycopg import Rollback

from app.core.database import connect
from app.services.life_facts import create_life_fact
from tests.db_api import DbApi
from tests.support import run

MISSING_ID = "00000000-0000-4000-8000-000000000999"


def test_added_life_fact_follows_the_contract(migrated_database_url):
    caregiver = DbApi(migrated_database_url).create_account()
    profile_id = caregiver.create_profile()["profileId"]

    response = caregiver.call(
        "POST",
        f"/api/v1/profiles/{profile_id}/life-facts",
        json={"title": "단골손님", "content": "합성 단골손님 이야기"},
    )

    assert response.status_code == 201
    body = response.json()
    UUID(body.pop("factId"))
    assert body.pop("createdAt")
    assert body == {
        "schemaVersion": 1,
        "profileId": profile_id,
        "title": "단골손님",
        "content": "합성 단골손님 이야기",
    }


def test_invalid_life_facts_are_rejected(migrated_database_url):
    caregiver = DbApi(migrated_database_url).create_account()
    profile_id = caregiver.create_profile()["profileId"]
    path = f"/api/v1/profiles/{profile_id}/life-facts"

    invalid_bodies = [
        {"title": "", "content": "합성 내용"},
        {"title": "합성 제목", "content": "  "},
        {"title": "가" * 101, "content": "합성 내용"},
        {"title": "합성 제목"},
        {"title": "합성 제목", "content": "합성 내용", "sourceProposalId": None},
    ]
    codes = [
        caregiver.call("POST", path, json=body).json()["errorCode"]
        for body in invalid_bodies
    ]

    assert codes == ["INVALID_REQUEST"] * len(invalid_bodies)
    accepted = caregiver.call(
        "POST", path, json={"title": "가" * 100, "content": "합성 내용"}
    )
    assert accepted.status_code == 201
    assert len(caregiver.call("GET", f"/api/v1/profiles/{profile_id}").json()["lifeFacts"]) == 1


def test_life_fact_cannot_be_added_to_another_accounts_profile(migrated_database_url):
    api = DbApi(migrated_database_url)
    profile_id = api.create_account().create_profile()["profileId"]
    stranger = api.create_account()

    responses = [
        stranger.call(
            "POST",
            f"/api/v1/profiles/{path_id}/life-facts",
            json={"title": "합성 제목", "content": "합성 내용"},
        )
        for path_id in (profile_id, MISSING_ID)
    ]

    assert [r.status_code for r in responses] == [404, 404]
    assert {r.json()["errorCode"] for r in responses} == {"PROFILE_NOT_FOUND"}
    assert api.query("SELECT count(*) AS n FROM life_facts")[0]["n"] == 0


def test_patch_changes_only_the_sent_fields(migrated_database_url):
    caregiver = DbApi(migrated_database_url).create_account()
    profile_id = caregiver.create_profile()["profileId"]
    created = caregiver.call(
        "POST",
        f"/api/v1/profiles/{profile_id}/life-facts",
        json={"title": "단골손님", "content": "처음 내용"},
    ).json()
    path = f"/api/v1/life-facts/{created['factId']}"

    content_only = caregiver.call("PATCH", path, json={"content": "고친 내용"})
    title_only = caregiver.call("PATCH", path, json={"title": "고친 제목"})
    unchanged = caregiver.call("PATCH", path, json={})

    assert content_only.status_code == 200
    assert content_only.json() == {**created, "content": "고친 내용"}
    assert title_only.json() == {**created, "title": "고친 제목", "content": "고친 내용"}
    assert unchanged.json() == title_only.json()


def test_patch_rejects_cleared_or_blank_fields(migrated_database_url):
    caregiver = DbApi(migrated_database_url).create_account()
    profile_id = caregiver.create_profile()["profileId"]
    created = caregiver.call(
        "POST",
        f"/api/v1/profiles/{profile_id}/life-facts",
        json={"title": "단골손님", "content": "처음 내용"},
    ).json()
    path = f"/api/v1/life-facts/{created['factId']}"

    invalid_bodies = [
        {"title": None},
        {"content": None},
        {"content": ""},
        {"title": "가" * 101},
    ]
    codes = [
        caregiver.call("PATCH", path, json=body).json()["errorCode"]
        for body in invalid_bodies
    ]

    assert codes == ["INVALID_REQUEST"] * len(invalid_bodies)
    stored = caregiver.call("GET", f"/api/v1/profiles/{profile_id}").json()
    assert stored["lifeFacts"] == [created]


def test_other_accounts_life_fact_looks_missing(migrated_database_url):
    api = DbApi(migrated_database_url)
    owner = api.create_account()
    profile_id = owner.create_profile()["profileId"]
    fact_id = owner.call(
        "POST",
        f"/api/v1/profiles/{profile_id}/life-facts",
        json={"title": "단골손님", "content": "처음 내용"},
    ).json()["factId"]

    responses = [
        api.create_account().call(
            "PATCH", f"/api/v1/life-facts/{fact_id}", json={"content": "남의 수정"}
        ),
        owner.call("PATCH", f"/api/v1/life-facts/{MISSING_ID}", json={"content": "x"}),
    ]

    assert [r.status_code for r in responses] == [404, 404]
    assert {r.json()["errorCode"] for r in responses} == {"LIFE_FACT_NOT_FOUND"}
    stored = owner.call("GET", f"/api/v1/profiles/{profile_id}").json()["lifeFacts"]
    assert stored[0]["content"] == "처음 내용"


def test_create_life_fact_joins_the_callers_transaction(migrated_database_url):
    """7-4(작업 C)는 제안 정리와 같은 트랜잭션에서 부른다. 함수가 따로 커밋하면 안 된다."""
    api = DbApi(migrated_database_url)
    profile_id = UUID(api.create_account().create_profile()["profileId"])

    async def scenario():
        async with connect(migrated_database_url) as connection:
            async with connection.transaction():
                await create_life_fact(
                    connection, profile_id=profile_id, title="버릴 제목", content="버릴 내용"
                )
                raise Rollback()
            async with connection.transaction():
                return await create_life_fact(
                    connection, profile_id=profile_id, title="남길 제목", content="남길 내용"
                )

    kept = run(scenario())

    rows = api.query("SELECT fact_id, title, source_proposal_id FROM life_facts")
    assert rows == [
        {"fact_id": kept.fact_id, "title": "남길 제목", "source_proposal_id": None}
    ]
    assert (kept.profile_id, kept.content) == (profile_id, "남길 내용")


def test_create_life_fact_records_the_source_proposal(migrated_database_url):
    api = DbApi(migrated_database_url)
    profile_id = UUID(api.create_account().create_profile()["profileId"])

    async def scenario():
        async with connect(migrated_database_url) as connection:
            cursor = await connection.execute(
                "INSERT INTO visit_sessions (profile_id) VALUES (%s) "
                "RETURNING session_id",
                (profile_id,),
            )
            session_id = (await cursor.fetchone())["session_id"]
            cursor = await connection.execute(
                "INSERT INTO life_fact_proposals "
                "(session_id, profile_id, title, content, reason) "
                "VALUES (%s, %s, '제안 제목', '제안 내용', '합성 근거') "
                "RETURNING proposal_id",
                (session_id, profile_id),
            )
            proposal_id = (await cursor.fetchone())["proposal_id"]
            fact = await create_life_fact(
                connection,
                profile_id=profile_id,
                title="보호자가 고친 제목",
                content="보호자가 고친 내용",
                source_proposal_id=proposal_id,
            )
            return proposal_id, fact

    proposal_id, fact = run(scenario())

    rows = api.query(
        "SELECT title, content, source_proposal_id FROM life_facts WHERE fact_id = %s",
        (fact.fact_id,),
    )
    assert rows == [
        {
            "title": "보호자가 고친 제목",
            "content": "보호자가 고친 내용",
            "source_proposal_id": proposal_id,
        }
    ]
    proposal = api.query("SELECT title, content FROM life_fact_proposals")
    assert proposal == [{"title": "제안 제목", "content": "제안 내용"}]
