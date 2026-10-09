"""회차 응답(`VisitSession`)과 회차 상태 계산, 회차 목록(API 5-4).

`sessionStatus`는 저장하지 않고 평가, 음성 분석 작업과 리포트로 계산한다(API 명세
5절). 작업 B의 5-1, 5-3과 작업 C의 5-4가 `load_visit_session`을 같이 쓴다.

| 값 | 조건 |
| --- | --- |
| `completed` | `report_generated_at IS NOT NULL` |
| `evaluationPending` | `evaluated_at IS NULL` |
| `processing` | 작업이 `queued`, `transcribing`, `sttCompleted`, `generatingReport` |
| `failed` | 접수 후 실패한 작업(`status = 'failed' AND size_bytes IS NOT NULL`)이 있음 |
| `audioPending` | 그 밖. 업로드 단계의 실패는 작업을 지우므로 남지 않는다 |

`participantCount`와 `analysisId`는 가장 최근 작업(`created_at DESC`)의 값이다.

PR #99에는 상태를 `evaluationPending`으로 고정한 임시 `load_visit_session`이
`app/services/visit_sessions.py`에 있다. 시그니처를 그 함수와 같게 두었으므로 #99가
병합되면 그 임시 구현을 지우고 이 함수를 쓰게 한다.
"""

from typing import LiteralString
from uuid import UUID

from app.core.database import DbConnection
from app.core.errors import AppError
from app.schemas.reports import VisitSession
from app.services import ownership

_SELECT: LiteralString = """
SELECT v.session_id, v.profile_id, v.started_at, s.set_id,
       (SELECT ph.photo_id FROM photos ph WHERE ph.session_id = v.session_id)
           AS photo_id,
       ARRAY(SELECT c.card_id FROM conversation_cards c
              WHERE c.set_id = s.set_id AND c.selected
              ORDER BY c.position) AS selected_card_ids,
       CASE
           WHEN v.report_generated_at IS NOT NULL THEN 'completed'
           WHEN v.evaluated_at IS NULL THEN 'evaluationPending'
           WHEN EXISTS (SELECT 1 FROM speech_analysis_jobs j
                         WHERE j.session_id = v.session_id
                           AND j.status IN ('queued', 'transcribing',
                                            'sttCompleted', 'generatingReport'))
               THEN 'processing'
           WHEN EXISTS (SELECT 1 FROM speech_analysis_jobs j
                         WHERE j.session_id = v.session_id
                           AND j.status = 'failed' AND j.size_bytes IS NOT NULL)
               THEN 'failed'
           ELSE 'audioPending'
       END AS session_status,
       latest.participant_count, latest.analysis_id
  FROM visit_sessions v
  JOIN card_sets s ON s.session_id = v.session_id
  LEFT JOIN LATERAL (
       SELECT j.participant_count, j.analysis_id FROM speech_analysis_jobs j
        WHERE j.session_id = v.session_id
        ORDER BY j.created_at DESC LIMIT 1
  ) latest ON true
"""


async def load_visit_session(
    connection: DbConnection, session_id: UUID
) -> VisitSession:
    """회차 하나의 `VisitSession`. 소유 확인은 부르는 쪽에서 먼저 한다."""
    cursor = await connection.execute(
        _SELECT + " WHERE v.session_id = %s", (session_id,)
    )
    row = await cursor.fetchone()
    if row is None:
        # 소유 확인 뒤 회차가 지워진 경우다.
        raise AppError(
            status_code=404,
            error_code=ownership.VISIT_SESSION.error_code,
            message=ownership.VISIT_SESSION.message,
        )
    return VisitSession(**row)


async def list_visit_sessions(
    connection: DbConnection, profile_id: UUID, *, account_id: str, limit: int
) -> list[VisitSession]:
    """5-4. 최근 회차(`started_at DESC`)부터 `limit`개."""
    await ownership.require_owned(
        connection, ownership.PROFILE, profile_id, account_id=account_id
    )
    cursor = await connection.execute(
        _SELECT
        + " WHERE v.profile_id = %s ORDER BY v.started_at DESC, v.session_id LIMIT %s",
        (profile_id, limit),
    )
    return [VisitSession(**row) for row in await cursor.fetchall()]
