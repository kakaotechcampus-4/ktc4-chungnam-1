"""푸시 받을 기기의 등록(1-7)과 해제(1-8), 알림 수신 철회(1-6)와 탈퇴(1-5) 때의 정리 검증.

임시 DB에 최신 migration을 적용해 실행한다(`conftest.py`). FID 와 계정은 모두 합성이다.
"""

import asyncio

from httpx import ASGITransport, AsyncClient

from tests.db_api import DbApi
from tests.support import request, run

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


# ── 계정당 기기 수(2026-11-09 PM 결정, 기본 5대) ───────────────────────────────


def _fid(number: int) -> str:
    return f"synthFid{number:02d}AAAAAAAAAAAA"


def _age_devices(api: DbApi, hours_ago: dict[str, int]) -> None:
    """등록 시각을 정해 둔다. 순서를 요청 사이의 시계 차이에 맡기지 않는다."""
    for fid, hours in hours_ago.items():
        api.query(
            "UPDATE push_devices SET registered_at = now() - %s * interval '1 hour' "
            "WHERE fid = %s",
            (hours, fid),
        )


def test_a_sixth_device_replaces_the_least_recently_registered_one(
    migrated_database_url,
):
    api = DbApi(migrated_database_url)
    caregiver = api.create_account()
    other = api.create_account()
    for number in range(5):
        assert caregiver.call("PUT", f"/auth/me/push-devices/{_fid(number)}").status_code == 204
    other.call("PUT", f"/auth/me/push-devices/{FID_B}")
    # 2번이 가장 오래전에 등록한 기기다. 다른 계정의 기기는 더 오래됐어도 세지 않는다.
    _age_devices(api, {_fid(0): 3, _fid(1): 2, _fid(2): 5, _fid(3): 1, _fid(4): 4, FID_B: 9})

    response = caregiver.call("PUT", f"/auth/me/push-devices/{_fid(5)}")

    assert response.status_code == 204
    assert response.content == b""
    mine = {d["fid"] for d in _devices(api) if d["user_id"] == caregiver.account_id}
    assert mine == {_fid(0), _fid(1), _fid(3), _fid(4), _fid(5)}
    assert [d["user_id"] for d in _devices(api) if d["fid"] == FID_B] == [other.account_id]


def test_registering_a_known_device_again_keeps_every_device(migrated_database_url):
    api = DbApi(migrated_database_url)
    caregiver = api.create_account()
    for number in range(5):
        caregiver.call("PUT", f"/auth/me/push-devices/{_fid(number)}")
    _age_devices(api, {_fid(number): 5 - number for number in range(5)})

    # 앱을 다시 켠 기기는 등록 시각만 새로 하고 아무것도 지우지 않는다.
    refreshed = caregiver.call("PUT", f"/auth/me/push-devices/{_fid(0)}")
    assert refreshed.status_code == 204
    assert {d["fid"] for d in _devices(api)} == {_fid(n) for n in range(5)}

    # 그래서 다음 새 기기는 0번이 아니라 그다음으로 오래된 1번을 밀어낸다.
    caregiver.call("PUT", f"/auth/me/push-devices/{_fid(5)}")
    assert {d["fid"] for d in _devices(api)} == {_fid(0), _fid(2), _fid(3), _fid(4), _fid(5)}


def test_device_limit_follows_the_setting_and_counts_moved_devices(
    migrated_database_url,
):
    api = DbApi(migrated_database_url)
    api.settings = api.settings.model_copy(update={"push_devices_per_account": 2})
    caregiver = api.create_account()
    previous_owner = api.create_account()
    caregiver.call("PUT", f"/auth/me/push-devices/{_fid(0)}")
    caregiver.call("PUT", f"/auth/me/push-devices/{_fid(1)}")
    previous_owner.call("PUT", f"/auth/me/push-devices/{FID_A}")
    _age_devices(api, {_fid(0): 2, _fid(1): 1})

    # 다른 계정에서 옮겨 온 기기도 이 계정의 기기로 센다.
    moved = caregiver.call("PUT", f"/auth/me/push-devices/{FID_A}")

    assert moved.status_code == 204
    assert [(d["fid"], d["user_id"]) for d in _devices(api)] == sorted([
        (FID_A, caregiver.account_id), (_fid(1), caregiver.account_id),
    ])


def test_concurrent_registrations_do_not_exceed_the_limit(migrated_database_url):
    api = DbApi(migrated_database_url)
    caregiver = api.create_account()
    headers = {"Authorization": f"Bearer {caregiver.token}"}

    async def register_all():
        transport = ASGITransport(app=api.app)
        async with AsyncClient(transport=transport, base_url="http://testserver") as client:
            return await asyncio.gather(*[
                client.put(f"/auth/me/push-devices/{_fid(number)}", headers=headers)
                for number in range(8)
            ])

    responses = run(register_all())

    assert [r.status_code for r in responses] == [204] * 8
    assert len(_devices(api)) == 5
