"""푸시 받을 기기의 등록(1-7)과 해제(1-8), 알림 수신 철회(1-6)와 탈퇴(1-5) 때의 정리 검증.

임시 DB에 최신 migration을 적용해 실행한다(`conftest.py`). FID 와 계정은 모두 합성이다.
"""

from tests.db_api import DbApi
from tests.support import request

FID_A = "cSyntheticFidAAAAAAAAA"
FID_B = "dSyntheticFidBBBBBBBBB"


def _devices(api: DbApi) -> list[dict]:
    return api.query(
        "SELECT fid, user_id::text AS user_id, registered_at "
        "FROM push_devices ORDER BY fid"
    )


def test_registering_a_device_stores_it_for_the_account(migrated_database_url):
    api = DbApi(migrated_database_url)
    caregiver = api.create_account()

    first = caregiver.call("PUT", f"/auth/me/push-devices/{FID_A}")
    [stored] = _devices(api)
    again = caregiver.call("PUT", f"/auth/me/push-devices/{FID_A}")
    [refreshed] = _devices(api)

    assert first.status_code == 204
    assert first.content == b""
    assert again.status_code == 204
    assert (stored["fid"], stored["user_id"]) == (FID_A, caregiver.account_id)
    # 같은 요청을 다시 보내면 행을 늘리지 않고 등록 시각만 새로 한다.
    assert refreshed["user_id"] == caregiver.account_id
    assert refreshed["registered_at"] >= stored["registered_at"]


def test_a_device_moves_to_the_account_that_registered_it_last(
    migrated_database_url,
):
    api = DbApi(migrated_database_url)
    before = api.create_account()
    after = api.create_account()

    before.call("PUT", f"/auth/me/push-devices/{FID_A}")
    moved = after.call("PUT", f"/auth/me/push-devices/{FID_A}")

    assert moved.status_code == 204
    assert [(d["fid"], d["user_id"]) for d in _devices(api)] == [
        (FID_A, after.account_id)
    ]


def test_registering_requires_push_notification_consent(migrated_database_url):
    api = DbApi(migrated_database_url)
    caregiver = api.create_account()
    caregiver.call("PATCH", "/auth/me/consents", json={"pushNotification": False})

    response = caregiver.call("PUT", f"/auth/me/push-devices/{FID_A}")

    assert response.status_code == 403
    assert response.json()["errorCode"] == "PUSH_NOTIFICATION_CONSENT_REQUIRED"
    assert _devices(api) == []


def test_withdrawing_push_consent_removes_only_that_accounts_devices(
    migrated_database_url,
):
    api = DbApi(migrated_database_url)
    withdrawing = api.create_account()
    other = api.create_account()
    withdrawing.call("PUT", f"/auth/me/push-devices/{FID_A}")
    other.call("PUT", f"/auth/me/push-devices/{FID_B}")

    # 다른 선택 동의만 바꾸면 등록을 지우지 않는다.
    withdrawing.call("PATCH", "/auth/me/consents", json={"serviceImprovement": True})
    assert len(_devices(api)) == 2

    response = withdrawing.call(
        "PATCH", "/auth/me/consents", json={"pushNotification": False}
    )

    assert response.status_code == 200
    assert [(d["fid"], d["user_id"]) for d in _devices(api)] == [
        (FID_B, other.account_id)
    ]


def test_unregistering_removes_only_the_callers_device(migrated_database_url):
    api = DbApi(migrated_database_url)
    caregiver = api.create_account()
    other = api.create_account()
    caregiver.call("PUT", f"/auth/me/push-devices/{FID_A}")
    other.call("PUT", f"/auth/me/push-devices/{FID_B}")

    responses = [
        caregiver.call("DELETE", f"/auth/me/push-devices/{FID_A}"),
        # 다른 계정의 기기와 등록하지 않은 기기도 같은 204 다. 지우지는 않는다.
        caregiver.call("DELETE", f"/auth/me/push-devices/{FID_B}"),
        caregiver.call("DELETE", "/auth/me/push-devices/eSyntheticFidUnknownXX"),
    ]

    assert [r.status_code for r in responses] == [204, 204, 204]
    assert [(d["fid"], d["user_id"]) for d in _devices(api)] == [
        (FID_B, other.account_id)
    ]


def test_unregistering_works_without_push_consent(migrated_database_url):
    api = DbApi(migrated_database_url)
    caregiver = api.create_account()
    caregiver.call("PUT", f"/auth/me/push-devices/{FID_A}")
    # 다른 경로로 동의가 거둬진 뒤에 남은 등록이 있어도 앱이 지울 수 있어야 한다.
    api.query(
        "INSERT INTO consent_records "
        "(user_id, terms_version, service_data, sensitive_data, "
        " service_improvement, push_notification) "
        "SELECT user_id, terms_version, service_data, sensitive_data, "
        "       service_improvement, false "
        "FROM current_consents WHERE user_id = %s",
        (caregiver.account_id,),
    )

    response = caregiver.call("DELETE", f"/auth/me/push-devices/{FID_A}")

    assert response.status_code == 204
    assert _devices(api) == []


def test_deleting_the_account_removes_its_devices(migrated_database_url):
    api = DbApi(migrated_database_url)
    leaving = api.create_account()
    staying = api.create_account()
    leaving.call("PUT", f"/auth/me/push-devices/{FID_A}")
    staying.call("PUT", f"/auth/me/push-devices/{FID_B}")

    response = leaving.call("DELETE", "/auth/me")

    assert response.status_code == 204
    assert [d["fid"] for d in _devices(api)] == [FID_B]


def test_malformed_device_ids_are_rejected(migrated_database_url):
    api = DbApi(migrated_database_url)
    caregiver = api.create_account()

    responses = [
        caregiver.call(method, f"/auth/me/push-devices/{fid}")
        for method in ("PUT", "DELETE")
        for fid in ("has.dot", "a" * 65)
    ]

    assert [r.status_code for r in responses] == [422] * 4
    assert {r.json()["errorCode"] for r in responses} == {"INVALID_REQUEST"}
    assert _devices(api) == []


def test_device_requests_need_a_session(migrated_database_url):
    api = DbApi(migrated_database_url)

    responses = [
        request(api.app, method, f"/auth/me/push-devices/{FID_A}")
        for method in ("PUT", "DELETE")
    ]

    assert [r.status_code for r in responses] == [401, 401]
    assert _devices(api) == []
