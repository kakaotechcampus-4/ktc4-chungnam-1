"""보호자 평가 저장과 조회(API 6-1, 6-4) 검증.

임시 DB에 최신 migration을 적용해 실행한다(`conftest.py`). 값은 모두 합성 데이터다.
"""

from uuid import UUID

from tests.visit_records import MISSING_ID, Records


def _body(card_reviews, **overrides):
    return {
        "conversationSatisfaction": 4,
        "careRecipientReaction": "pleased",
        "cardReviews": card_reviews,
        "freeNote": None,
        **overrides,
    }


def _used(card_id: UUID, reaction: str = "positive"):
    return {"cardId": str(card_id), "wasUsed": True, "caregiverReaction": reaction}


def _not_used(card_id: UUID):
    return {"cardId": str(card_id), "wasUsed": False, "caregiverReaction": None}


def _path(session_id) -> str:
    return f"/api/v1/visit-sessions/{session_id}/evaluation"


def _reactions(records: Records, set_id: UUID) -> list:
    rows = records.query(
        "SELECT review_reaction FROM conversation_cards WHERE set_id = %s "
        "ORDER BY position",
        (set_id,),
    )
    return [row["review_reaction"] for row in rows]


def test_submit_evaluation_saves_session_and_card_reviews(migrated_database_url):
    records = Records(migrated_database_url)
    user_id, profile_id = records.account()
    visit = records.visit(profile_id, cards=4, selected=3)
    first, second, _unanswered = visit.selected

    response = records.call(
        user_id,
        "POST",
        _path(visit.session_id),
        json=_body([_used(first), _not_used(second)], freeNote="합성 메모"),
    )

    assert response.status_code == 201
    body = response.json()
    assert body.pop("evaluatedAt")
    assert body == {
        "schemaVersion": 1,
        "sessionId": str(visit.session_id),
        "conversationSatisfaction": 4,
        "careRecipientReaction": "pleased",
        "cardReviews": [_used(first), _not_used(second)],
        "freeNote": "합성 메모",
    }
    # 답하지 않은 카드와 고르지 않은 카드는 null로 남는다.
    assert _reactions(records, visit.set_id) == ["positive", "notUsed", None, None]
    sessions = records.call(
        user_id, "GET", f"/api/v1/profiles/{profile_id}/visit-sessions"
    ).json()["sessions"]
    assert sessions[0]["sessionStatus"] == "audioPending"


def test_get_evaluation_returns_saved_reviews(migrated_database_url):
    records = Records(migrated_database_url)
    user_id, profile_id = records.account()
    visit = records.visit(profile_id)
    first, second = visit.selected
    records.call(
        user_id,
        "POST",
        _path(visit.session_id),
        json=_body([_not_used(second), _used(first, "negative")]),
    )

    response = records.call(user_id, "GET", _path(visit.session_id))

    assert response.status_code == 200
    # 카드 순서(position)대로 돌려준다.
    assert response.json()["cardReviews"] == [_used(first, "negative"), _not_used(second)]


def test_get_evaluation_before_submission_is_not_found(migrated_database_url):
    records = Records(migrated_database_url)
    user_id, profile_id = records.account()
    visit = records.visit(profile_id)

    response = records.call(user_id, "GET", _path(visit.session_id))

    assert response.status_code == 404
    assert response.json()["errorCode"] == "EVALUATION_NOT_FOUND"


def test_second_evaluation_is_rejected_without_changes(migrated_database_url):
    records = Records(migrated_database_url)
    user_id, profile_id = records.account()
    visit = records.visit(profile_id)
    first = visit.selected[0]
    records.call(user_id, "POST", _path(visit.session_id), json=_body([_used(first)]))

    response = records.call(
        user_id,
        "POST",
        _path(visit.session_id),
        json=_body([_not_used(first)], conversationSatisfaction=1),
    )

    assert response.status_code == 409
    assert response.json()["errorCode"] == "EVALUATION_ALREADY_SUBMITTED"
    assert records.scalar(
        "SELECT evaluation_satisfaction FROM visit_sessions WHERE session_id = %s",
        (visit.session_id,),
    ) == 4
    assert _reactions(records, visit.set_id)[0] == "positive"


def test_invalid_card_reviews_are_rejected_without_changes(migrated_database_url):
    records = Records(migrated_database_url)
    user_id, profile_id = records.account()
    visit = records.visit(profile_id, cards=3, selected=2)
    first = visit.selected[0]
    not_selected = visit.card_ids[2]
    other_visit = records.visit(profile_id)
    invalid_reviews = [
        [_used(not_selected)],
        [_used(other_visit.selected[0])],
        [_used(first), _used(first)],
        [{"cardId": str(first), "wasUsed": True, "caregiverReaction": None}],
        [{"cardId": str(first), "wasUsed": False, "caregiverReaction": "positive"}],
    ]

    codes = [
        records.call(user_id, "POST", _path(visit.session_id), json=_body(reviews)).json()[
            "errorCode"
        ]
        for reviews in invalid_reviews
    ]

    assert codes == ["INVALID_CARD_REVIEW"] * len(invalid_reviews)
    assert records.scalar(
        "SELECT evaluated_at FROM visit_sessions WHERE session_id = %s",
        (visit.session_id,),
    ) is None
    assert _reactions(records, visit.set_id) == [None, None, None]


def test_malformed_evaluation_is_invalid_request(migrated_database_url):
    records = Records(migrated_database_url)
    user_id, profile_id = records.account()
    visit = records.visit(profile_id)
    invalid_bodies = [
        _body([], conversationSatisfaction=0),
        _body([], conversationSatisfaction=6),
        _body([], conversationSatisfaction="4"),
        _body([], careRecipientReaction="happy"),
        _body([{"cardId": str(visit.selected[0]), "wasUsed": "yes", "caregiverReaction": None}]),
        _body([], unknown=True),
        {"conversationSatisfaction": 4, "careRecipientReaction": "calm"},
    ]

    codes = [
        records.call(user_id, "POST", _path(visit.session_id), json=body).json()["errorCode"]
        for body in invalid_bodies
    ]

    assert codes == ["INVALID_REQUEST"] * len(invalid_bodies)


def test_other_accounts_session_looks_missing(migrated_database_url):
    records = Records(migrated_database_url)
    _, profile_id = records.account()
    other_user, _ = records.account()
    visit = records.visit(profile_id)

    responses = [
        records.call(other_user, method, _path(target), json=_body([]) if method == "POST" else None)
        for target in (visit.session_id, MISSING_ID)
        for method in ("POST", "GET")
    ]

    assert {r.status_code for r in responses} == {404}
    assert {r.json()["errorCode"] for r in responses} == {"VISIT_SESSION_NOT_FOUND"}
