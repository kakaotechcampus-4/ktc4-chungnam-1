"""프로필과 생애 정보의 요청과 응답 (API 2절, data-contracts.md `Profile`, `LifeFact`)."""

from datetime import UTC, date, datetime
from typing import Annotated, Any, Literal
from uuid import UUID

from pydantic import AfterValidator, Field, StrictBool, model_validator

from app.schemas.common import ApiModel

Gender = Literal["male", "female"]
ConditionStage = Literal["mildCognitiveImpairment", "mildDementia", "unknown"]
SetupStatus = Literal["inProgress", "completed"]
PhotoAnalysisStatus = Literal["pending", "processing", "completed", "failed"]
# 일대기의 분류. 필드 이름 `storyCategory`, `imageNumber`는 임시다(작업 D 문서 미정 D1, D2).
StoryCategory = Literal["family", "hobby", "work", "hometown", "friend", "travel", "other"]


def _not_blank(value: str) -> str:
    # 없는 값은 빈 문자열이 아니라 null로 보낸다(공통 규칙). 공백만 있는 값도 DB
    # CHECK(`length(btrim(x)) > 0`)가 막으므로 요청 검증에서 먼저 거절한다.
    if not value.strip():
        raise ValueError("빈 문자열은 받지 않습니다.")
    return value


NonBlankText = Annotated[str, AfterValidator(_not_blank)]
ProfileName = Annotated[NonBlankText, Field(max_length=50)]

# 카드 생성 입력의 연령대(`ageRange`)는 `10s` 이상만 받는다(`ai/card_generation/contract.py`).
# 만 10세가 안 된 생년월일과 미래 날짜는 카드 생성이 늘 `INVALID_CONTEXT`로 실패하므로 저장할 때
# 거절한다. 다른 나이 정책은 정하지 않았다.
MIN_AGE_YEARS = 10


def _today() -> date:
    # 카드 생성(`card_sets.build_context`)은 DB의 `current_date`로 나이를 센다. API와 DB
    # 컨테이너 모두 시간대를 따로 두지 않아 UTC이므로 같은 날짜로 확인한다. DB 시간대가 UTC보다
    # 동쪽(예: 한국 시간)이어도 DB 날짜가 같거나 늦어 여기서 받은 값은 카드 생성에서도 통과한다.
    return datetime.now(UTC).date()


def latest_birth_date(today: date) -> date:
    """`today`에 만 `MIN_AGE_YEARS`세가 되는 가장 늦은 생년월일. 그해에 없는 2월 29일은 2월 28일이다."""
    year = today.year - MIN_AGE_YEARS
    try:
        return today.replace(year=year)
    except ValueError:
        return date(year, 2, 28)


def _old_enough(value: date) -> date:
    if value > latest_birth_date(_today()):
        raise ValueError(f"생년월일은 만 {MIN_AGE_YEARS}세 이상이어야 합니다.")
    return value


BirthDate = Annotated[date, AfterValidator(_old_enough)]

# 2026-11-09 PM 결정: 이야기(생애 정보) 하나의 내용은 5,000자 이하다. 제목은 100자 이하다.
# 2-6, 2-7과 7-4(`app.schemas.reports.LifeFactReview`)가 같은 형식을 쓴다.
LIFE_FACT_TITLE_MAX_LENGTH = 100
LIFE_FACT_CONTENT_MAX_LENGTH = 5000
LifeFactTitle = Annotated[NonBlankText, Field(max_length=LIFE_FACT_TITLE_MAX_LENGTH)]
LifeFactContent = Annotated[NonBlankText, Field(max_length=LIFE_FACT_CONTENT_MAX_LENGTH)]
# 분류마다 기본 그림이 5장이다(`life_facts.image_number` CHECK).
ImageNumber = Annotated[int, Field(strict=True, ge=1, le=5)]


def _reject_null(model: ApiModel, *fields: str) -> None:
    """보낼 수는 있지만 `null`로 지울 수 없는 필드를 확인한다."""
    for field in fields:
        if field in model.model_fields_set and getattr(model, field) is None:
            raise ValueError(f"{field}는 null일 수 없습니다.")


class Condition(ApiModel):
    stage: ConditionStage
    symptom_note: str | None = Field(default=None, alias="symptomNote")


class ProfileCreateRequest(ApiModel):
    name: ProfileName
    gender: Gender
    birth_date: BirthDate = Field(alias="birthDate")
    condition: Condition


class ProfileUpdateRequest(ApiModel):
    """보낸 필드만 바꾼다. 세부 정보 네 항목은 `null`을 보내면 지운다.

    `condition`의 `stage`는 항상 보낸다. `symptomNote`를 빼고 보내면 저장된 메모를 그대로
    두고, `null`을 보낼 때만 지운다.
    """

    name: ProfileName | None = None
    gender: Gender | None = None
    birth_date: BirthDate | None = Field(default=None, alias="birthDate")
    condition: Condition | None = None
    occupation: NonBlankText | None = None
    hometown: NonBlankText | None = None
    hobby: NonBlankText | None = None
    family: NonBlankText | None = None

    @model_validator(mode="after")
    def _basic_fields_are_not_cleared(self) -> "ProfileUpdateRequest":
        _reject_null(self, "name", "gender", "birth_date", "condition")
        return self

    def column_changes(self) -> dict[str, Any]:
        """보낸 필드를 `profiles`의 컬럼 이름과 값으로 옮긴다."""
        changes: dict[str, Any] = {}
        for field in ("name", "gender", "occupation", "hometown", "hobby", "family"):
            if field in self.model_fields_set:
                changes[field] = getattr(self, field)
        if "birth_date" in self.model_fields_set:
            changes["birth_date"] = self.birth_date
        if "condition" in self.model_fields_set and self.condition is not None:
            changes["condition_stage"] = self.condition.stage
            if "symptom_note" in self.condition.model_fields_set:
                changes["symptom_note"] = self.condition.symptom_note
        return changes


class LifeFactCreateRequest(ApiModel):
    story_category: StoryCategory = Field(alias="storyCategory")
    title: LifeFactTitle
    content: LifeFactContent
    image_number: ImageNumber = Field(alias="imageNumber")


class LifeFactUpdateRequest(ApiModel):
    """보낸 필드만 바꾼다. 모두 비울 수 없으므로 `null`도 받지 않는다.

    `sensitive`는 아픈 기억일 수 있는 이야기라는 표시다. 보호자가 켜고 끈다(2026-11-10 PM 결정).
    """

    story_category: StoryCategory | None = Field(default=None, alias="storyCategory")
    title: LifeFactTitle | None = None
    content: LifeFactContent | None = None
    image_number: ImageNumber | None = Field(default=None, alias="imageNumber")
    sensitive: StrictBool | None = None

    @model_validator(mode="after")
    def _fields_are_not_cleared(self) -> "LifeFactUpdateRequest":
        _reject_null(self, "story_category", "title", "content", "image_number", "sensitive")
        return self

    def column_changes(self) -> dict[str, Any]:
        """보낸 필드를 `life_facts`의 열 이름과 값으로 옮긴다."""
        return {
            field: getattr(self, field)
            for field in ("story_category", "title", "content", "image_number", "sensitive")
            if field in self.model_fields_set
        }


class LifeFactResponse(ApiModel):
    schema_version: Literal[1] = Field(default=1, alias="schemaVersion")
    fact_id: UUID = Field(alias="factId")
    profile_id: UUID = Field(alias="profileId")
    story_category: StoryCategory = Field(alias="storyCategory")
    title: str
    content: str
    image_number: int = Field(alias="imageNumber")
    # 아픈 기억일 수 있는 이야기. 7-4가 제안의 표시를 옮기고 보호자가 2-7로 바꾼다. 앱은 일대기에 표시를
    # 붙이고 홈 추천에서 뺀다(2026-11-10 PM 결정). 이 필드를 모르는 앱은 무시하면 된다
    sensitive: bool = False
    created_at: datetime = Field(alias="createdAt")


class PhotoAnalysisError(ApiModel):
    error_code: str = Field(alias="errorCode")


class PhotoDescriptionRequest(ApiModel):
    description: NonBlankText


class PhotoDescriptionResponse(ApiModel):
    schema_version: Literal[1] = Field(default=1, alias="schemaVersion")
    photo_id: UUID = Field(alias="photoId")
    description: str
    description_source: Literal["caregiver"] = Field(default="caregiver", alias="descriptionSource")
    updated_at: datetime = Field(alias="updatedAt")


class ProfilePhotoResponse(ApiModel):
    """프로필 사진 (API 3-1, 3-2, data-contracts.md `ProfilePhoto`).

    `imageUrl`은 수명이 짧은 S3 Presigned GET URL이며 `imageUrlExpiresAt`이 지나면 다시
    조회한다. `description`은 보호자 수정이 있으면 그것을 우선하고, 없으면 완료된 AI
    설명이다. `descriptionSource`가 출처를 구분하며 `error`는 AI 분석 실패를 나타낸다.
    """

    schema_version: Literal[1] = Field(default=1, alias="schemaVersion")
    photo_id: UUID = Field(alias="photoId")
    profile_id: UUID = Field(alias="profileId")
    image_url: str = Field(alias="imageUrl")
    image_url_expires_at: datetime = Field(alias="imageUrlExpiresAt")
    analysis_status: PhotoAnalysisStatus = Field(alias="analysisStatus")
    description: str | None
    description_source: Literal["ai", "caregiver"] | None = Field(default=None, alias="descriptionSource")
    error: PhotoAnalysisError | None
    created_at: datetime = Field(alias="createdAt")


class ProfileResponse(ApiModel):
    schema_version: Literal[1] = Field(default=1, alias="schemaVersion")
    profile_id: UUID = Field(alias="profileId")
    setup_status: SetupStatus = Field(alias="setupStatus")
    name: str
    gender: Gender
    birth_date: date = Field(alias="birthDate")
    condition: Condition
    occupation: str | None
    hometown: str | None
    hobby: str | None
    family: str | None
    life_facts: list[LifeFactResponse] = Field(alias="lifeFacts")
    # 프로필 사진만 담는다. 면회 사진은 면회 기록(5절)에서 내려준다.
    photos: list[ProfilePhotoResponse]
    created_at: datetime = Field(alias="createdAt")


class ProfileSummaryResponse(ApiModel):
    profile_id: UUID = Field(alias="profileId")
    name: str
    gender: Gender
    setup_status: SetupStatus = Field(alias="setupStatus")


class ProfileListResponse(ApiModel):
    schema_version: Literal[1] = Field(default=1, alias="schemaVersion")
    profiles: list[ProfileSummaryResponse]
