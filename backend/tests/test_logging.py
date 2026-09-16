import logging

from fastapi import FastAPI
from pydantic import BaseModel

from app.core.logging import SafeJsonFormatter, install_request_logging
from tests.support import request


def test_request_log_does_not_include_query_or_body(caplog) -> None:
    application = FastAPI()
    install_request_logging(application)

    class Input(BaseModel):
        value: str

    @application.post("/items/{item_id}")
    async def create_item(item_id: str, body: Input) -> dict[str, bool]:
        del item_id, body
        return {"created": True}

    caplog.set_level(logging.INFO, logger="saerok.http")
    response = request(
        application,
        "POST",
        "/items/sensitive-path-value?token=sensitive-query-value",
        json={"value": "sensitive-body-value"},
    )

    assert response.status_code == 200
    records = [record for record in caplog.records if record.name == "saerok.http"]
    assert len(records) == 1

    formatted = SafeJsonFormatter().format(records[0])
    assert "sensitive-path-value" not in formatted
    assert "sensitive-query-value" not in formatted
    assert "sensitive-body-value" not in formatted
    assert '"route": "/items/{item_id}"' in formatted
