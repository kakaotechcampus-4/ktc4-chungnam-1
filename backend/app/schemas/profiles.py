"""프로필과 생애 정보의 요청과 응답 (API 2절, data-contracts.md `Profile`, `LifeFact`)."""

from datetime import date, datetime
from typing import Annotated, Any, Literal
from uuid import UUID

from pydantic import AfterValidator, Field, model_validator

from app.schemas.common import ApiModel

Gender = Literal["male", "female"]
ConditionStage = Literal["mildCognitiveImpairment", "mildDementia", "unknown"]
SetupStatus = Literal["inProgress", "completed"]


def _not_blank(value: str) -> str:
    # 없는 값은 빈 문자열이 아니라 null로 보낸다(공통 규칙). 공백만 있는 값도 DB
    # CHECK(`length(btrim(x)) > 0`)가 막으므로 요청 검증에서 먼저 거절한다.
    if not value.strip():
        raise ValueError("빈 문자열은 받지 않습니다.")
    return value


NonBlankText = Annotated[str, AfterValidator(_not_blank)]
ProfileName = Annotated[NonBlankText, Field(max_length=50)]
LifeFactTitle = Annotated[NonBlankText, Field(max_length=100)]


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
    birth_date: date = Field(alias="birthDate")
    condition: Condition


class ProfileUpdateRequest(ApiModel):
    """보낸 필드만 바꾼다. 세부 정보 네 항목은 `null`을 보내면 지운다.

    `condition`은 한 덩어리로 바꾼다. `symptomNote`를 빼고 보내면 `null`로 저장한다.
    """

    name: ProfileName | None = None
    gender: Gender | None = None
    birth_date: date | None = Field(default=None, alias="birthDate")
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
            changes["symptom_note"] = self.condition.symptom_note
        return changes


class LifeFactCreateRequest(ApiModel):
    title: LifeFactTitle
    content: NonBlankText


class LifeFactUpdateRequest(ApiModel):
    """보낸 필드만 바꾼다. 둘 다 비울 수 없으므로 `null`도 받지 않는다."""

    title: LifeFactTitle | None = None
    content: NonBlankText | None = None

    @model_validator(mode="after")
    def _fields_are_not_cleared(self) -> "LifeFactUpdateRequest":
        _reject_null(self, "title", "content")
        return self

    def column_changes(self) -> dict[str, str]:
        return {
            field: getattr(self, field)
            for field in ("title", "content")
            if field in self.model_fields_set
        }


class LifeFactResponse(ApiModel):
    schema_version: Literal[1] = Field(default=1, alias="schemaVersion")
    fact_id: UUID = Field(alias="factId")
    profile_id: UUID = Field(alias="profileId")
    title: str
    content: str
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
    # 프로필 사진은 3-1 전까지 항상 빈 배열이다. `ProfilePhoto` 응답은 사진 보관과 분석
    # 동의 설계(API 명세 미정 3) 후 3-1, 3-2와 함께 붙인다.
    photos: list[Any] = Field(default_factory=list)
    created_at: datetime = Field(alias="createdAt")


class ProfileSummaryResponse(ApiModel):
    profile_id: UUID = Field(alias="profileId")
    name: str
    gender: Gender
    setup_status: SetupStatus = Field(alias="setupStatus")


class ProfileListResponse(ApiModel):
    schema_version: Literal[1] = Field(default=1, alias="schemaVersion")
    profiles: list[ProfileSummaryResponse]
