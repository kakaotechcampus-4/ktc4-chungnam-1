"""생애 정보 제안 승인(API 7-4)과 그 뒤의 7-3 검증. PR #105 의존.

승인한 생애 정보 제안은 작업 A의 `app.services.life_facts.create_life_fact`로
만든다. 그 모듈은 PR #105에서 들어오므로 develop에 병합되기 전에는 이 파일 전체를
건너뛰고, 병합되면 그대로 실행된다. 임시 DB에 최신 migration을 적용해
실행한다(`conftest.py`). 값은 모두 합성 데이터다.
"""

import importlib.util

import pytest

from tests.visit_records import Records

pytestmark = pytest.mark.skipif(
    importlib.util.find_spec("app.services.life_facts") is None,
    reason="PR #105(create_life_fact) 병합 전: develop에 app/services/life_facts.py 없음",
)


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
