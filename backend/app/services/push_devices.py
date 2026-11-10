"""리포트 완료 푸시를 받을 기기의 등록과 해제(API 1-7, 1-8).

앱은 알림 수신(선택 동의)에 동의한 계정에서 FCM 에 등록하고 받은 등록 ID(Firebase
Installation ID, FID)를 1-7 로 보낸다. 로그아웃이나 동의 철회 때 1-8 로 지운다. 동의를
거두는 1-6 은 그 계정의 등록을 모두 지우고, 탈퇴(1-5)는 계정과 함께 지운다(FK CASCADE).
계정당 기기 수는 설정(`SAEROK_PUSH_DEVICES_PER_ACCOUNT`, 기본 5)까지이며, 넘으면 등록
시각이 가장 오래된 기기를 지운다(2026-11-09 PM 결정).

FID 는 기기를 가리키는 값이라 로그와 오류 메시지에 남기지 않는다.
"""

from uuid import UUID

from app.core.database import DbConnection
from app.core.errors import AppError

# FCM 의 FID 는 URL-safe base64 문자열이다(지금은 22자). 형식이 바뀌어도 받을 수 있게
# 길이는 DB 열의 상한까지 둔다. DB 의 CHECK 와 같은 문자 집합이다.
FID_PATTERN = r"^[A-Za-z0-9_-]{1,64}$"


async def register_push_device(
    connection: DbConnection, account_id: str, fid: str, *, max_devices: int
) -> None:
    """1-7. 이 계정에 FID 를 등록한다. 같은 요청을 다시 보내면 등록 시각만 새로 한다.

    다른 계정에 등록된 FID 면 이 계정으로 옮긴다. 같은 기기에서 계정을 바꿔 로그인한
    경우다. 알림 수신에 동의하지 않은 계정이면 403 이다. 등록 뒤 이 계정의 기기가
    `max_devices` 를 넘으면 방금 등록한 기기를 빼고 등록 시각이 오래된 것부터 지운다.
    사용자에게는 오류로 알리지 않는다.
    """
    user_id = UUID(account_id)
    async with connection.transaction():
        # 동의를 바꾸는 1-6 은 계정 행을 `FOR UPDATE` 로 잠근다. 여기서 먼저 잠가, 동의를
        # 거두는 중에 등록이 끼어들어 철회 뒤에도 등록이 남는 일을 막는다. 같은 계정의
        # 등록끼리도 차례로 세도록 `FOR SHARE` 가 아니라 `FOR UPDATE` 로 잠근다.
        cursor = await connection.execute(
            "SELECT 1 FROM users WHERE user_id = %s FOR UPDATE", (user_id,)
        )
        if await cursor.fetchone() is None:
            raise AppError(
                status_code=404,
                error_code="ACCOUNT_NOT_FOUND",
                message="계정을 찾을 수 없습니다.",
            )
        cursor = await connection.execute(
            "SELECT push_notification FROM current_consents WHERE user_id = %s",
            (user_id,),
        )
        consent = await cursor.fetchone()
        if consent is None or not consent["push_notification"]:
            raise AppError(
                status_code=403,
                error_code="PUSH_NOTIFICATION_CONSENT_REQUIRED",
                message="알림 수신에 동의해야 기기를 등록할 수 있습니다.",
            )
        await connection.execute(
            "INSERT INTO push_devices (fid, user_id) VALUES (%s, %s) "
            "ON CONFLICT (fid) DO UPDATE "
            "SET user_id = EXCLUDED.user_id, registered_at = now()",
            (fid, user_id),
        )
        # 앱은 켤 때마다 다시 등록하므로 등록 시각이 가장 오래된 기기가 가장 오래 쓰지 않은
        # 기기다. 방금 등록한 기기는 시각이 같더라도 남긴다. 고른 기기가 그사이 같은 기기로
        # 로그인한 다른 계정으로 옮겨 갔으면, 바깥 조건의 계정을 다시 확인해 지우지 않는다.
        await connection.execute(
            "DELETE FROM push_devices WHERE user_id = %s AND fid IN ("
            " SELECT fid FROM push_devices WHERE user_id = %s"
            " ORDER BY fid = %s DESC, registered_at DESC, fid"
            " OFFSET %s)",
            (user_id, user_id, fid, max_devices),
        )


async def unregister_push_device(
    connection: DbConnection, account_id: str, fid: str
) -> None:
    """1-8. 이 계정에 등록된 FID 를 지운다.

    등록되지 않았거나 다른 계정에 등록된 FID 여도 오류로 알리지 않는다. 다른 계정의 등록
    여부를 드러내지 않고, 그 등록은 지우지 않는다.
    """
    await connection.execute(
        "DELETE FROM push_devices WHERE fid = %s AND user_id = %s",
        (fid, UUID(account_id)),
    )
