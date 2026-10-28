"""생애 정보 API (2-6, 2-7, 2-9)와 `create_life_fact` 검증.

임시 DB에 최신 migration을 적용해 실행한다(`conftest.py`). 값은 모두 합성 데이터다.
"""

from uuid import UUID

from psycopg import Rollback

from app.core.database import connect
from app.services.life_facts import create_life_fact
from tests.db_api import DbApi
from tests.support import run

MISSING_ID = "00000000-0000-4000-8000-000000000999"
STORY_CATEGORIES = ["family", "hobby", "work", "hometown", "friend", "travel", "other"]


def story(**overrides):
    """2-6 요청 본문. 값은 합성이다."""
    return {
        "storyCategory": "work",
        "title": "단골손님",
        "content": "처음 내용",
        "imageNumber": 3,
        **overrides,
    }


def without(field):
    body = story()
    del body[field]
    return body


def add_story(caregiver, profile_id, **overrides):
    response = caregiver.call(
        "POST", f"/api/v1/profiles/{profile_id}/life-facts", json=story(**overrides)
    )
    assert response.status_code == 201
    return response.json()


async def _life_fact_proposal(connection, profile_id):
    cursor = await connection.execute(
        "INSERT INTO visit_sessions (profile_id) VALUES (%s) RETURNING session_id",
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
    return (await cursor.fetchone())["proposal_id"]


def test_added_life_fact_follows_the_contract(migrated_database_url):
    caregiver = DbApi(migrated_database_url).create_account()
    profile_id = caregiver.create_profile()["profileId"]

    response = caregiver.call(
        "POST",
        f"/api/v1/profiles/{profile_id}/life-facts",
        json=story(content="합성 단골손님 이야기"),
    )

    assert response.status_code == 201
    body = response.json()
    UUID(body.pop("factId"))
    assert body.pop("createdAt")
    assert body == {
        "schemaVersion": 1,
        "profileId": profile_id,
        "storyCategory": "work",
        "title": "단골손님",
        "content": "합성 단골손님 이야기",
        "imageNumber": 3,
    }


def test_every_story_category_and_image_number_is_kept(migrated_database_url):
    caregiver = DbApi(migrated_database_url).create_account()
    profile_id = caregiver.create_profile()["profileId"]
    expected = [
        (category, index % 5 + 1) for index, category in enumerate(STORY_CATEGORIES)
    ]

    for category, number in expected:
        add_story(caregiver, profile_id, storyCategory=category, imageNumber=number)

    stored = caregiver.call("GET", f"/api/v1/profiles/{profile_id}").json()["lifeFacts"]
    assert [(f["storyCategory"], f["imageNumber"]) for f in stored] == expected


def test_invalid_life_facts_are_rejected(migrated_database_url):
    caregiver = DbApi(migrated_database_url).create_account()
    profile_id = caregiver.create_profile()["profileId"]
    path = f"/api/v1/profiles/{profile_id}/life-facts"

    invalid_bodies = [
        story(title=""),
        story(content="  "),
        story(title="가" * 101),
        without("content"),
        story(sourceProposalId=None),
        without("storyCategory"),
        story(storyCategory="occupation"),
        story(storyCategory=None),
        without("imageNumber"),
        story(imageNumber=0),
        story(imageNumber=6),
        story(imageNumber=2.5),
        story(imageNumber="3"),
        story(imageNumber=True),
        story(imageNumber=None),
    ]
    codes = [
        caregiver.call("POST", path, json=body).json()["errorCode"]
        for body in invalid_bodies
    ]

    assert codes == ["INVALID_REQUEST"] * len(invalid_bodies)
    accepted = caregiver.call("POST", path, json=story(title="가" * 100))
    assert accepted.status_code == 201
    assert len(caregiver.call("GET", f"/api/v1/profiles/{profile_id}").json()["lifeFacts"]) == 1


def test_life_fact_cannot_be_added_to_another_accounts_profile(migrated_database_url):
    api = DbApi(migrated_database_url)
    profile_id = api.create_account().create_profile()["profileId"]
    stranger = api.create_account()

    responses = [
        stranger.call("POST", f"/api/v1/profiles/{path_id}/life-facts", json=story())
        for path_id in (profile_id, MISSING_ID)
    ]

    assert [r.status_code for r in responses] == [404, 404]
    assert {r.json()["errorCode"] for r in responses} == {"PROFILE_NOT_FOUND"}
    assert api.query("SELECT count(*) AS n FROM life_facts")[0]["n"] == 0


def test_patch_changes_only_the_sent_fields(migrated_database_url):
    caregiver = DbApi(migrated_database_url).create_account()
    profile_id = caregiver.create_profile()["profileId"]
    created = add_story(caregiver, profile_id)
    path = f"/api/v1/life-facts/{created['factId']}"

    content_only = caregiver.call("PATCH", path, json={"content": "고친 내용"})
    title_only = caregiver.call("PATCH", path, json={"title": "고친 제목"})
    category_only = caregiver.call("PATCH", path, json={"storyCategory": "friend"})
    image_only = caregiver.call("PATCH", path, json={"imageNumber": 5})
    unchanged = caregiver.call("PATCH", path, json={})

    assert content_only.status_code == 200
    assert content_only.json() == {**created, "content": "고친 내용"}
    assert title_only.json() == {**created, "title": "고친 제목", "content": "고친 내용"}
    edited = {**created, "title": "고친 제목", "content": "고친 내용", "storyCategory": "friend"}
    # 분류를 바꿔도 그림 번호와 담은 시각(`createdAt`)은 그대로다.
    assert category_only.json() == edited
    assert image_only.json() == {**edited, "imageNumber": 5}
    assert unchanged.json() == image_only.json()


def test_patch_rejects_cleared_or_blank_fields(migrated_database_url):
    caregiver = DbApi(migrated_database_url).create_account()
    profile_id = caregiver.create_profile()["profileId"]
    created = add_story(caregiver, profile_id)
    path = f"/api/v1/life-facts/{created['factId']}"

    invalid_bodies = [
        {"title": None},
        {"content": None},
        {"content": ""},
        {"title": "가" * 101},
        {"storyCategory": None},
        {"storyCategory": "occupation"},
        {"imageNumber": None},
        {"imageNumber": 0},
        {"imageNumber": 6},
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
    fact_id = add_story(owner, profile_id)["factId"]

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


def test_deleted_life_fact_leaves_the_profile(migrated_database_url):
    caregiver = DbApi(migrated_database_url).create_account()
    profile_id = caregiver.create_profile()["profileId"]
    removed = add_story(caregiver, profile_id, title="지울 이야기")
    kept = add_story(caregiver, profile_id, title="남길 이야기")
    path = f"/api/v1/life-facts/{removed['factId']}"

    response = caregiver.call("DELETE", path)
    again = caregiver.call("DELETE", path)
    patched = caregiver.call("PATCH", path, json={"content": "지운 뒤 수정"})

    assert response.status_code == 204
    assert response.content == b""
    assert [again.status_code, patched.status_code] == [404, 404]
    assert {again.json()["errorCode"], patched.json()["errorCode"]} == {"LIFE_FACT_NOT_FOUND"}
    stored = caregiver.call("GET", f"/api/v1/profiles/{profile_id}").json()["lifeFacts"]
    assert stored == [kept]


def test_other_accounts_life_fact_cannot_be_deleted(migrated_database_url):
    api = DbApi(migrated_database_url)
    owner = api.create_account()
    profile_id = owner.create_profile()["profileId"]
    fact = add_story(owner, profile_id)

    responses = [
        api.create_account().call("DELETE", f"/api/v1/life-facts/{fact['factId']}"),
        owner.call("DELETE", f"/api/v1/life-facts/{MISSING_ID}"),
    ]

    assert [r.status_code for r in responses] == [404, 404]
    assert {r.json()["errorCode"] for r in responses} == {"LIFE_FACT_NOT_FOUND"}
    stored = owner.call("GET", f"/api/v1/profiles/{profile_id}").json()["lifeFacts"]
    assert stored == [fact]


def test_deleting_life_fact_keeps_its_source_proposal(migrated_database_url):
    """면회 제안을 승인해 만든 이야기를 지워도 제안은 남는다."""
    api = DbApi(migrated_database_url)
    caregiver = api.create_account()
    profile_id = UUID(caregiver.create_profile()["profileId"])

    async def scenario():
        async with connect(migrated_database_url) as connection:
            proposal_id = await _life_fact_proposal(connection, profile_id)
            return await create_life_fact(
                connection,
                profile_id=profile_id,
                title="승인한 제목",
                content="승인한 내용",
                source_proposal_id=proposal_id,
            )

    fact = run(scenario())

    response = caregiver.call("DELETE", f"/api/v1/life-facts/{fact.fact_id}")

    assert response.status_code == 204
    assert api.query("SELECT count(*) AS n FROM life_facts")[0]["n"] == 0
    assert api.query("SELECT title FROM life_fact_proposals") == [{"title": "제안 제목"}]


def test_create_life_fact_defaults_story_category_and_image(migrated_database_url):
    """7-4는 분류와 그림 번호를 보내지 않는다. 기타와 1~5 중 한 번호로 만든다."""
    api = DbApi(migrated_database_url)
    profile_id = UUID(api.create_account().create_profile()["profileId"])

    async def scenario():
        async with connect(migrated_database_url) as connection:
            return [
                await create_life_fact(
                    connection, profile_id=profile_id, title=f"제목 {n}", content="합성 내용"
                )
                for n in range(10)
            ]

    facts = run(scenario())

    assert {fact.story_category for fact in facts} == {"other"}
    assert {fact.image_number for fact in facts} <= {1, 2, 3, 4, 5}
    stored = api.query(
        "SELECT fact_id, story_category, image_number FROM life_facts ORDER BY fact_id"
    )
    assert stored == sorted(
        (
            {
                "fact_id": f.fact_id,
                "story_category": f.story_category,
                "image_number": f.image_number,
            }
            for f in facts
        ),
        key=lambda row: row["fact_id"],
    )


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
            proposal_id = await _life_fact_proposal(connection, profile_id)
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
