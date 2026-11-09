"""생애 정보 제안 승인(API 7-4)과 그 뒤의 7-3 검증. PR #105 의존.

승인한 생애 정보 제안은 작업 A의 `app.services.life_facts.create_life_fact`로
만든다. 임시 DB에 최신 migration을 적용해 실행한다(`conftest.py`). 값은 모두 합성
데이터다.
"""

from app.services.life_facts import LIFE_FACT_LIMIT
from tests.visit_records import Records


def _reported(records: Records):
    user_id, profile_id = records.account()
    visit = records.visit(profile_id)
    records.evaluate(visit)
    records.report(visit)
    return user_id, profile_id, visit


def test_accepted_life_fact_uses_the_caregivers_final_values(migrated_database_url):
    records = Records(migrated_database_url)
    user_id, profile_id, visit = _reported(records)
    accepted = records.life_fact_proposal(visit, title="합성 제안 제목")
    rejected = records.life_fact_proposal(visit, title="합성 거절 제목")
    topic = records.topic_proposal(visit, 0, "more")

    response = records.call(
        user_id,
        "POST",
        f"/api/v1/visit-sessions/{visit.session_id}/proposals/review",
        json={
            "lifeFacts": [
                {
                    "proposalId": str(accepted),
                    "reviewStatus": "accepted",
                    "title": "합성 최종 제목",
                    "content": "합성 최종 내용",
                },
                {"proposalId": str(rejected), "reviewStatus": "rejected"},
            ],
            "topics": [{"proposalId": str(topic), "reviewStatus": "accepted", "action": "more"}],
        },
    )

    assert response.status_code == 200
    statuses = {
        p["proposalId"]: (p["title"], p["reviewStatus"])
        for p in response.json()["lifeFactProposals"]
    }
    # 제안 값은 AI가 만든 원래 값 그대로다.
    assert statuses == {
        str(accepted): ("합성 제안 제목", "accepted"),
        str(rejected): ("합성 거절 제목", "rejected"),
    }
    assert records.query(
        "SELECT profile_id, title, content, source_proposal_id FROM life_facts"
    ) == [
        {
            "profile_id": profile_id,
            "title": "합성 최종 제목",
            "content": "합성 최종 내용",
            "source_proposal_id": accepted,
        }
    ]
    assert records.query("SELECT title FROM life_fact_proposals ORDER BY title") == [
        {"title": "합성 거절 제목"},
        {"title": "합성 제안 제목"},
    ]


def test_accepted_life_fact_is_rolled_back_with_a_failed_review(migrated_database_url):
    records = Records(migrated_database_url)
    user_id, _, visit = _reported(records)
    fact = records.life_fact_proposal(visit)
    records.topic_proposal(visit, 0)

    # 주제 제안을 빠뜨려 422가 난다. 생애 정보도 만들지 않는다.
    response = records.call(
        user_id,
        "POST",
        f"/api/v1/visit-sessions/{visit.session_id}/proposals/review",
        json={
            "lifeFacts": [
                {"proposalId": str(fact), "reviewStatus": "accepted", "title": "합성", "content": "합성"}
            ],
            "topics": [],
        },
    )

    assert response.json()["errorCode"] == "INVALID_PROPOSAL_REVIEW"
    assert records.scalar("SELECT count(*) FROM life_facts") == 0
    assert records.scalar(
        "SELECT count(*) FROM life_fact_proposals WHERE status = 'settled'"
    ) == 0


def _review_path(visit) -> str:
    return f"/api/v1/visit-sessions/{visit.session_id}/proposals/review"


def _accept(proposal, content="합성 최종 내용"):
    return {
        "proposalId": str(proposal),
        "reviewStatus": "accepted",
        "title": "합성 최종 제목",
        "content": content,
    }


def test_accepted_life_fact_content_is_limited_like_2_6(migrated_database_url):
    records = Records(migrated_database_url)
    user_id, _, visit = _reported(records)
    fact = records.life_fact_proposal(visit)

    too_long = records.call(
        user_id,
        "POST",
        _review_path(visit),
        json={"lifeFacts": [_accept(fact, "가" * 5001)], "topics": []},
    )
    longest = records.call(
        user_id,
        "POST",
        _review_path(visit),
        json={"lifeFacts": [_accept(fact, "가" * 5000)], "topics": []},
    )

    assert too_long.status_code == 422
    assert too_long.json()["errorCode"] == "INVALID_REQUEST"
    assert longest.status_code == 200
    assert records.query("SELECT content FROM life_facts") == [{"content": "가" * 5000}]


def test_review_over_the_story_limit_saves_nothing(migrated_database_url):
    """승인한 생애 정보를 더해 300개를 넘으면 제안 정리와 주제 피드백까지 모두 저장하지 않는다."""
    records = Records(migrated_database_url)
    user_id, profile_id, visit = _reported(records)
    records.execute(
        "INSERT INTO life_facts (profile_id, title, content) "
        "SELECT %s, '합성 제목 ' || n, '합성 내용' FROM generate_series(1, %s) AS n",
        (profile_id, LIFE_FACT_LIMIT - 1),
    )
    first = records.life_fact_proposal(visit, title="합성 제안 1")
    second = records.life_fact_proposal(visit, title="합성 제안 2")
    topic = records.topic_proposal(visit, 0, "more")
    accepted_topic = [{"proposalId": str(topic), "reviewStatus": "accepted", "action": "more"}]

    over = records.call(
        user_id,
        "POST",
        _review_path(visit),
        json={"lifeFacts": [_accept(first), _accept(second)], "topics": accepted_topic},
    )

    assert over.status_code == 409
    assert over.json()["errorCode"] == "LIFE_FACT_LIMIT_EXCEEDED"
    assert records.scalar("SELECT count(*) FROM life_facts") == LIFE_FACT_LIMIT - 1
    assert records.scalar(
        "SELECT count(*) FROM life_fact_proposals WHERE status = 'settled'"
    ) == 0
    assert records.scalar(
        "SELECT count(*) FROM topic_proposals WHERE status = 'settled'"
    ) == 0
    assert records.scalar("SELECT count(*) FROM topic_feedback") == 0

    # 하나만 승인하면 300개에 맞아 저장된다.
    fits = records.call(
        user_id,
        "POST",
        _review_path(visit),
        json={
            "lifeFacts": [_accept(first), {"proposalId": str(second), "reviewStatus": "rejected"}],
            "topics": accepted_topic,
        },
    )

    assert fits.status_code == 200
    assert records.scalar("SELECT count(*) FROM life_facts") == LIFE_FACT_LIMIT
    assert records.scalar("SELECT count(*) FROM topic_feedback") == 1


def test_accepted_life_fact_takes_the_proposed_category_unless_the_caregiver_changes_it(
    migrated_database_url,
):
    """2026-11-09 PM 결정: AI가 고른 분류로 이야기를 만들고, 보호자가 고른 분류가 있으면 그것을 쓴다.

    제안의 분류와 아픈 기억 표시는 확인 뒤에도 바뀌지 않는다.
    """
    records = Records(migrated_database_url)
    user_id, profile_id, visit = _reported(records)
    kept = records.life_fact_proposal(visit, title="합성 제안 1", story_category="hometown")
    changed = records.life_fact_proposal(
        visit, title="합성 제안 2", story_category="family", sensitive=True
    )

    response = records.call(
        user_id,
        "POST",
        _review_path(visit),
        json={
            "lifeFacts": [
                {**_accept(kept), "title": "합성 최종 1"},
                {**_accept(changed), "title": "합성 최종 2", "storyCategory": "travel"},
            ],
            "topics": [],
        },
    )

    assert response.status_code == 200
    assert [
        (p["storyCategory"], p["sensitive"], p["reviewStatus"])
        for p in response.json()["lifeFactProposals"]
    ] == [("hometown", False, "accepted"), ("family", True, "accepted")]
    assert records.query(
        "SELECT title, story_category, source_proposal_id FROM life_facts ORDER BY title"
    ) == [
        {"title": "합성 최종 1", "story_category": "hometown", "source_proposal_id": kept},
        {"title": "합성 최종 2", "story_category": "travel", "source_proposal_id": changed},
    ]
    # 일대기(2-3)에도 그 분류로 보인다.
    profile = records.call(user_id, "GET", f"/api/v1/profiles/{profile_id}").json()
    assert sorted(f["storyCategory"] for f in profile["lifeFacts"]) == ["hometown", "travel"]
