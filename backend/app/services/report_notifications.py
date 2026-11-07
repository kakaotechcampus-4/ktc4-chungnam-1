"""리포트가 완료되면 보호자의 기기로 푸시를 보낸다.

음성 worker 가 작업을 완료로 저장한 뒤 부른다. 발송 대상은 DB 에서 다시 고른다.
작업이 실제로 완료(`completed`)됐고, 그 회차의 계정이 지금 알림 수신에 동의했고,
그 계정에 등록된 기기(1-7)가 있을 때만 보낸다. 임대를 잃어 리포트를 저장하지 못한
작업이나 그사이 동의를 거둔 계정에는 보내지 않는다.

발송 실패는 리포트 처리를 실패로 만들지 않는다. 알림을 놓쳐도 앱은 홈에서 회차
상태(5-4)로 리포트 도착을 보여준다. 다시 보내지 않는다.
"""

from __future__ import annotations

import logging
from typing import Protocol

from app.clients.fcm import SendResult
from app.core.database import DbConnection

logger = logging.getLogger("saerok.report_notifications")


class ReportReadySender(Protocol):
    async def send_report_ready(
        self, fid: str, *, session_id: str, analysis_id: str
    ) -> SendResult: ...


class ReportNotifier(Protocol):
    async def report_ready(self, connection: DbConnection, *, analysis_id: str) -> None:
        """완료된 리포트를 알린다. 실패해도 예외를 내지 않는다."""
        ...


class PushReportNotifier:
    def __init__(self, sender: ReportReadySender) -> None:
        self._sender = sender

    async def report_ready(self, connection: DbConnection, *, analysis_id: str) -> None:
        try:
            await self._notify(connection, analysis_id)
        except Exception as error:  # noqa: BLE001 - 알림 실패가 작업을 실패시키지 않게 한다
            logger.warning(
                "report_notification_failed",
                extra={"analysis_id": analysis_id, "reason": type(error).__name__},
            )

    async def _notify(self, connection: DbConnection, analysis_id: str) -> None:
        # 트랜잭션 없이 읽는다. 발송(HTTP) 동안 잠금을 잡지 않는다.
        cursor = await connection.execute(
            "SELECT d.fid, d.user_id, j.session_id "
            "FROM speech_analysis_jobs j "
            "JOIN visit_sessions s ON s.session_id = j.session_id "
            "JOIN profiles p ON p.profile_id = s.profile_id "
            "JOIN current_consents c ON c.user_id = p.user_id "
            "JOIN push_devices d ON d.user_id = p.user_id "
            "WHERE j.analysis_id = %s AND j.status = 'completed' "
            "  AND c.push_notification "
            "ORDER BY d.registered_at DESC",
            (analysis_id,),
        )
        devices = await cursor.fetchall()
        results: dict[SendResult, int] = {}
        for device in devices:
            result = await self._sender.send_report_ready(
                device["fid"],
                session_id=str(device["session_id"]),
                analysis_id=analysis_id,
            )
            results[result] = results.get(result, 0) + 1
            if result is SendResult.UNREGISTERED:
                # 그사이 다른 계정이 같은 기기를 등록했으면 그 등록은 지우지 않는다.
                await connection.execute(
                    "DELETE FROM push_devices WHERE fid = %s AND user_id = %s",
                    (device["fid"], device["user_id"]),
                )
        logger.info(
            "report_notification_sent",
            extra={
                "analysis_id": analysis_id,
                "devices": len(devices),
                "sent": results.get(SendResult.SENT, 0),
                "unregistered": results.get(SendResult.UNREGISTERED, 0),
                "failed": results.get(SendResult.FAILED, 0),
            },
        )
