from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, File, Path, UploadFile, status

from app.api.deps import (
    CurrentAccountDep,
    DbConnectionDep,
    ImageStorageDep,
    SettingsDep,
)
from app.schemas.visit_session import (
    AddCardsRequest,
    CreateVisitSessionRequest,
    VisitPhoto,
    VisitSession,
)
from app.services.ownership import CARD_SET, VISIT_SESSION, require_owned
from app.services.visit_photos import replace_visit_photo
from app.services.visit_sessions import (
    add_session_cards,
    create_visit_session,
    load_visit_session,
)


router = APIRouter(tags=["visit-sessions"])


@router.post(
    "/api/v1/visit-sessions",
    summary="면회 회차 생성",
    status_code=status.HTTP_201_CREATED,
    response_model=VisitSession,
    response_model_by_alias=True,
)
async def create_session(
    account: CurrentAccountDep,
    connection: DbConnectionDep,
    body: CreateVisitSessionRequest,
) -> VisitSession:
    """녹음을 시작할 때 고른 카드(1~9번)로 회차 생성. `startedAt`은 서버 수신 시각.

    API 명세 5-1
    """

    profile_id = await require_owned(
        connection, CARD_SET, body.set_id, account_id=account.account_id
    )
    session_id = await create_visit_session(
        connection, profile_id, body.set_id, body.selected_card_ids
    )
    return await load_visit_session(connection, session_id)


@router.post(
    "/api/v1/visit-sessions/{session_id}/photo",
    summary="면회 사진 업로드",
    status_code=status.HTTP_201_CREATED,
    response_model=VisitPhoto,
    response_model_by_alias=True,
)
async def upload_photo(
    account: CurrentAccountDep,
    connection: DbConnectionDep,
    storage: ImageStorageDep,
    settings: SettingsDep,
    session_id: Annotated[UUID, Path()],
    image: Annotated[UploadFile, File()],
) -> VisitPhoto:
    """면회 사진 한 장(JPEG, PNG)을 S3에 올려 회차 기록으로 저장. 다시 올리면 기존 사진을 교체.

    평가 전 회차만 받고 이미지 분석은 하지 않음. API 명세 5-2
    """

    await require_owned(connection, VISIT_SESSION, session_id, account_id=account.account_id)
    return await replace_visit_photo(
        connection,
        storage,
        session_id,
        image=image,
        max_size_bytes=settings.max_image_bytes,
    )


@router.patch(
    "/api/v1/visit-sessions/{session_id}/cards",
    summary="보충 카드 추가",
    response_model=VisitSession,
    response_model_by_alias=True,
)
async def add_cards(
    account: CurrentAccountDep,
    connection: DbConnectionDep,
    session_id: Annotated[UUID, Path()],
    body: AddCardsRequest,
) -> VisitSession:
    """면회 중 꺼낸 보충 카드(10~12번) 추가. 같은 요청을 다시 보내도 결과가 같음.

    API 명세 5-3
    """

    await require_owned(connection, VISIT_SESSION, session_id, account_id=account.account_id)
    await add_session_cards(connection, session_id, body.card_ids)
    return await load_visit_session(connection, session_id)
