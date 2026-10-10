"""리포트 목록, 리포트, 변경 제안 조회와 확인(API 7-1 ~ 7-4) 검증.

생애 정보 제안을 승인하는 7-4는 작업 A의 `create_life_fact`(PR #105)가 필요해
`test_proposal_review_life_facts.py`에 따로 둔다. 임시 DB에 최신 migration을 적용해
실행한다(`conftest.py`). 값은 모두 합성 데이터다.
"""

from datetime import UTC, datetime, timedelta

from app.services import proposals
from tests.visit_records import MISSING_ID, Records, Visit


def _reported(records: Records, profile_id, **evaluate) -> Visit:
    visit = records.visit(profile_id)
    records.evaluate(visit, **evaluate)
    records.report(visit)
    return visit


def _review_path(visit: Visit) -> str:
    return f"/api/v1/visit-sessions/{visit.session_id}/proposals/review"


def test_report_list_has_reported_sessions_with_mood_and_korean_date(
    migrated_database_url,
):
    records = Records(migrated_database_url)
    user_id, profile_id = records.account()
    # 한국 시간 2026-08-21 00:30. UTC 날짜(8월 20일)가 아니라 한국 날짜를 쓴다.
    korea_midnight = datetime(2026, 8, 20, 15, 30, tzinfo=UTC)
    moods = {}
    for day, satisfaction in enumerate([1, 2, 3, 4, 5]):
        visit = records.visit(profile_id, started_at=korea_midnight - timedelta(days=day))
        records.evaluate(visit, satisfaction=satisfaction)
        records.report(visit)
        moods[str(visit.session_id)] = satisfaction
    unreported = records.visit(profile_id, started_at=korea_midnight + timedelta(days=1))
    records.evaluate(unreported)

    response = records.call(user_id, "GET", f"/api/v1/profiles/{profile_id}/reports")

    assert response.status_code == 200
    reports = response.json()["reports"]
    assert [r["mood"] for r in reports] == ["hard", "hard", "normal", "good", "good"]
    assert reports[0] == {
        "sessionId": list(moods)[0],
        "title": "합성 리포트 제목",
        "visitDate": "2026-08-21",
        "mood": "hard",
    }
    assert str(unreported.session_id) not in [r["sessionId"] for r in reports]
    limited = records.call(user_id, "GET", f"/api/v1/profiles/{profile_id}/reports?limit=2")
    assert len(limited.json()["reports"]) == 2


def test_report_contract_with_photo_and_card_summaries(migrated_database_url):
    records = Records(migrated_database_url)
    user_id, profile_id = records.account()
    visit = records.visit(profile_id, started_at=datetime(2026, 8, 21, 5, tzinfo=UTC))
    first, second = visit.selected
    records.evaluate(visit, reactions={first: "positive", second: "notUsed"})
    records.report(visit, summaries={first: "합성 카드 요약"})
    photo_id = records.scalar(
        "INSERT INTO photos (profile_id, session_id, s3_object_key) "
        "VALUES (%s, %s, 'synthetic/visit.jpg') RETURNING photo_id",
        (profile_id, visit.session_id),
    )

    response = records.call(user_id, "GET", f"/api/v1/visit-sessions/{visit.session_id}/report")

    assert response.status_code == 200
    body = response.json()
    assert body.pop("generatedAt")
    assert body == {
        "schemaVersion": 1,
        "sessionId": str(visit.session_id),
        "title": "합성 리포트 제목",
        "body": "합성 리포트 본문",
        "visitDate": "2026-08-21",
        "mood": "good",
        "photo": {
            "photoId": str(photo_id),
            "imageUrl": "https://bucket.s3.ap-northeast-2.amazonaws.com/synthetic.jpg",
            "imageUrlExpiresAt": "2026-08-21T06:00:00Z",
        },
        "cardSummaries": [
            {"cardId": str(first), "cardTitle": "합성 카드 1", "summary": "합성 카드 요약"}
        ],
    }
    assert records.storage.downloads == ["synthetic/visit.jpg"]


def test_report_without_photo_does_not_touch_storage(migrated_database_url):
    records = Records(migrated_database_url)
    user_id, profile_id = records.account()
    visit = _reported(records, profile_id)

    response = records.call(user_id, "GET", f"/api/v1/visit-sessions/{visit.session_id}/report")

    assert response.json()["photo"] is None
    assert records.storage.downloads == []


def test_report_and_proposals_before_report_are_not_found(migrated_database_url):
    records = Records(migrated_database_url)
    user_id, profile_id = records.account()
    visit = records.visit(profile_id)
    records.evaluate(visit)

    responses = [
        records.call(user_id, "GET", f"/api/v1/visit-sessions/{visit.session_id}/report"),
        records.call(user_id, "GET", f"/api/v1/visit-sessions/{visit.session_id}/proposals"),
        records.call(user_id, "POST", _review_path(visit), json={"lifeFacts": [], "topics": []}),
    ]

    assert {r.status_code for r in responses} == {404}
    assert {r.json()["errorCode"] for r in responses} == {"REPORT_NOT_FOUND"}


def test_other_accounts_report_looks_missing(migrated_database_url):
    records = Records(migrated_database_url)
    _, profile_id = records.account()
    other_user, _ = records.account()
    visit = _reported(records, profile_id)

    responses = [
        records.call(other_user, "GET", f"/api/v1/visit-sessions/{target}/{kind}")
        for target in (visit.session_id, MISSING_ID)
        for kind in ("report", "proposals")
    ] + [records.call(other_user, "GET", f"/api/v1/profiles/{profile_id}/reports")]

    assert [r.json()["errorCode"] for r in responses] == ["VISIT_SESSION_NOT_FOUND"] * 4 + [
        "PROFILE_NOT_FOUND"
    ]


def test_proposals_contract(migrated_database_url):
    records = Records(migrated_database_url)
    user_id, profile_id = records.account()
    visit = _reported(records, profile_id)
    fact_proposal = records.life_fact_proposal(visit)
    topic_proposal = records.topic_proposal(visit, 0, "more")

    response = records.call(user_id, "GET", f"/api/v1/visit-sessions/{visit.session_id}/proposals")

    assert response.status_code == 200
    assert response.json() == {
        "schemaVersion": 1,
        "sessionId": str(visit.session_id),
        "lifeFactProposals": [
            {
                "proposalId": str(fact_proposal),
                "title": "합성 제안",
                "content": "합성 제안 내용",
                "reason": "합성 이유",
                "reviewStatus": "pending",
            }
        ],
        "topicProposals": [
            {
                "proposalId": str(topic_proposal),
                "cardId": str(visit.card_ids[0]),
                "topic": {
                    "topicId": str(visit.topic_ids[0]),
                    "title": "합성 주제 1",
                    "description": "합성 주제 설명 1",
                },
                "suggestedAction": "more",
                "reason": "합성 이유",
                "reviewStatus": "pending",
            }
        ],
    }


def test_review_records_topic_feedback_with_the_caregivers_action(
    migrated_database_url,
):
    records = Records(migrated_database_url)
    user_id, profile_id = records.account()
    visit = _reported(records, profile_id)
    kept = records.topic_proposal(visit, 0, "more")
    dropped = records.topic_proposal(visit, 1, "less")
    fact_proposal = records.life_fact_proposal(visit)

    response = records.call(
        user_id,
        "POST",
        _review_path(visit),
        json={
            "lifeFacts": [{"proposalId": str(fact_proposal), "reviewStatus": "rejected"}],
            "topics": [
                # 보호자가 제안(more)과 다른 행동을 골랐다.
                {"proposalId": str(kept), "reviewStatus": "accepted", "action": "exclude"},
                {"proposalId": str(dropped), "reviewStatus": "rejected"},
            ],
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert [p["reviewStatus"] for p in body["lifeFactProposals"]] == ["rejected"]
    assert [(p["proposalId"], p["suggestedAction"], p["reviewStatus"]) for p in body["topicProposals"]] == [
        (str(kept), "more", "accepted"),
        (str(dropped), "less", "rejected"),
    ]
    assert records.query(
        "SELECT profile_id, topic_id, proposal_id, action FROM topic_feedback"
    ) == [
        {
            "profile_id": profile_id,
            "topic_id": visit.topic_ids[0],
            "proposal_id": kept,
            "action": "exclude",
        }
    ]
    assert records.scalar("SELECT count(*) FROM life_facts") == 0
    statuses = records.query(
        "SELECT status FROM topic_proposals UNION ALL SELECT status FROM life_fact_proposals"
    )
    assert {row["status"] for row in statuses} == {"settled"}
    # 확인 뒤 7-3도 같은 결과를 돌려준다.
    again = records.call(user_id, "GET", f"/api/v1/visit-sessions/{visit.session_id}/proposals")
    assert again.json() == body


def test_review_of_a_session_without_proposals_is_a_no_op(migrated_database_url):
    records = Records(migrated_database_url)
    user_id, profile_id = records.account()
    visit = _reported(records, profile_id)

    response = records.call(user_id, "POST", _review_path(visit), json={"lifeFacts": [], "topics": []})

    assert response.status_code == 200
    assert response.json()["lifeFactProposals"] == []
    assert response.json()["topicProposals"] == []


def test_second_review_is_rejected(migrated_database_url):
    records = Records(migrated_database_url)
    user_id, profile_id = records.account()
    visit = _reported(records, profile_id)
    proposal = records.topic_proposal(visit, 0)
    rejected = {"lifeFacts": [], "topics": [{"proposalId": str(proposal), "reviewStatus": "rejected"}]}
    records.call(user_id, "POST", _review_path(visit), json=rejected)

    responses = [
        records.call(user_id, "POST", _review_path(visit), json=rejected),
        records.call(user_id, "POST", _review_path(visit), json={"lifeFacts": [], "topics": []}),
    ]

    assert {r.status_code for r in responses} == {409}
    assert {r.json()["errorCode"] for r in responses} == {"PROPOSAL_ALREADY_REVIEWED"}


def test_review_must_cover_exactly_the_pending_proposals(migrated_database_url):
    records = Records(migrated_database_url)
    user_id, profile_id = records.account()
    visit = _reported(records, profile_id)
    first = records.topic_proposal(visit, 0)
    second = records.topic_proposal(visit, 1)
    fact_proposal = records.life_fact_proposal(visit)
    other_visit = _reported(records, profile_id)
    other_proposal = records.topic_proposal(other_visit, 0)

    def rejected(*ids):
        return [{"proposalId": str(i), "reviewStatus": "rejected"} for i in ids]

    fact = rejected(fact_proposal)
    invalid_bodies = [
        {"lifeFacts": fact, "topics": rejected(first)},
        {"lifeFacts": fact, "topics": rejected(first, second, other_proposal)},
        {"lifeFacts": fact, "topics": rejected(first, second, second)},
        {"lifeFacts": [], "topics": rejected(first, second)},
        # 주제 제안을 생애 정보 자리에 보냈다.
        {"lifeFacts": rejected(fact_proposal, first), "topics": rejected(second)},
    ]

    codes = [
        records.call(user_id, "POST", _review_path(visit), json=body).json()["errorCode"]
        for body in invalid_bodies
    ]

    assert codes == ["INVALID_PROPOSAL_REVIEW"] * len(invalid_bodies)
    assert records.scalar(
        "SELECT count(*) FROM topic_proposals WHERE status = 'settled'"
    ) == 0
    assert records.scalar("SELECT count(*) FROM topic_feedback") == 0


def test_review_final_values_must_match_review_status(migrated_database_url):
    records = Records(migrated_database_url)
    user_id, profile_id = records.account()
    visit = _reported(records, profile_id)
    topic = str(records.topic_proposal(visit, 0))
    fact = str(records.life_fact_proposal(visit))
    rejected_topic = [{"proposalId": topic, "reviewStatus": "rejected"}]
    rejected_fact = [{"proposalId": fact, "reviewStatus": "rejected"}]
    invalid_bodies = [
        {"lifeFacts": [{"proposalId": fact, "reviewStatus": "accepted"}], "topics": rejected_topic},
        {
            "lifeFacts": [{"proposalId": fact, "reviewStatus": "accepted", "title": "합성"}],
            "topics": rejected_topic,
        },
        {
            "lifeFacts": [{"proposalId": fact, "reviewStatus": "rejected", "title": "합성"}],
            "topics": rejected_topic,
        },
        {
            "lifeFacts": [
                {"proposalId": fact, "reviewStatus": "accepted", "title": " ", "content": "합성"}
            ],
            "topics": rejected_topic,
        },
        {
            "lifeFacts": [
                {"proposalId": fact, "reviewStatus": "accepted", "title": "가" * 101, "content": "합성"}
            ],
            "topics": rejected_topic,
        },
        {"lifeFacts": rejected_fact, "topics": [{"proposalId": topic, "reviewStatus": "accepted"}]},
        {
            "lifeFacts": rejected_fact,
            "topics": [{"proposalId": topic, "reviewStatus": "rejected", "action": "more"}],
        },
        {
            "lifeFacts": rejected_fact,
            "topics": [{"proposalId": topic, "reviewStatus": "accepted", "action": "remove"}],
        },
        {"lifeFacts": rejected_fact, "topics": [{"proposalId": topic, "reviewStatus": "pending"}]},
    ]

    codes = [
        records.call(user_id, "POST", _review_path(visit), json=body).json()["errorCode"]
        for body in invalid_bodies
    ]

    assert codes == ["INVALID_REQUEST"] * len(invalid_bodies)


def test_accepting_a_life_fact_without_the_life_fact_module_is_rejected(
    migrated_database_url, monkeypatch
):
    """임시 가드: `app.services.life_facts`가 없으면 DB를 쓰지 않고 503을 낸다.

    PR #105 병합 여부와 관계없이 돌도록 모듈 이름을 없는 이름으로 바꿔 확인한다.
    #105 병합 뒤 가드를 지울 때 이 테스트도 함께 지운다.
    """
    monkeypatch.setattr(proposals, "LIFE_FACTS_MODULE", "app.services._missing_module")
    records = Records(migrated_database_url)
    user_id, profile_id = records.account()
    visit = _reported(records, profile_id)
    fact = records.life_fact_proposal(visit)
    topic = records.topic_proposal(visit, 0)

    response = records.call(
        user_id,
        "POST",
        _review_path(visit),
        json={
            "lifeFacts": [
                {"proposalId": str(fact), "reviewStatus": "accepted", "title": "합성", "content": "합성"}
            ],
            "topics": [{"proposalId": str(topic), "reviewStatus": "accepted", "action": "more"}],
        },
    )

    assert response.status_code == 503
    assert response.json()["errorCode"] == "LIFE_FACT_STORE_NOT_READY"
    assert records.scalar(
        "SELECT count(*) FROM life_fact_proposals WHERE status = 'settled'"
    ) == 0
    assert records.scalar(
        "SELECT count(*) FROM topic_proposals WHERE status = 'settled'"
    ) == 0
    assert records.scalar("SELECT count(*) FROM topic_feedback") == 0
