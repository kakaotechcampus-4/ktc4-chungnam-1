from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class ApiModel(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")


class HealthResponse(ApiModel):
    schema_version: Literal[1] = Field(default=1, alias="schemaVersion")
    status: Literal["ok", "ready"]
    service: str
    version: str


class ErrorResponse(ApiModel):
    schema_version: Literal[1] = Field(default=1, alias="schemaVersion")
    error_code: str = Field(alias="errorCode")
    message: str
    request_id: str | None = Field(default=None, alias="requestId")
    retryable: bool = False
