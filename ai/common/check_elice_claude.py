"""합성 입력만 사용하는 수동 연결 점검. 원문·키·주소·오류 본문을 출력하지 않는다."""
import argparse
import json
import os

from langchain_core.messages import HumanMessage, ToolMessage
from pydantic import BaseModel, Field

from common.elice_claude import ELICE_CLAUDE_BASE_URL, EliceClaudeConfig, elice_claude_model


class SyntheticAnswer(BaseModel):
    word: str = Field(description="입력에 주어진 합성 단어")


def check(config: EliceClaudeConfig) -> dict[str, bool]:
    model = elice_claude_model(config)
    text = model.invoke("연결 점검용 합성 입력입니다. '연결 확인'이라고 답하세요.")
    if not text.content:
        raise ValueError("empty synthetic response")
    structured = model.with_structured_output(
        SyntheticAnswer, method="json_schema", strict=True,
    ).invoke("합성 단어는 나무입니다. word에 나무를 넣으세요.")
    if structured.word != "나무":
        raise ValueError("synthetic structured output mismatch")
    tool = {"type": "function", "function": {
        "name": "synthetic_lookup", "description": "합성 자료 한 건 읽기",
        "parameters": {"type": "object", "properties": {},
                       "required": [], "additionalProperties": False},
    }}
    messages = [HumanMessage("synthetic_lookup 도구를 한 번 사용한 뒤 결과를 짧게 설명하세요.")]
    reply = model.bind_tools([tool], tool_choice="synthetic_lookup", strict=True).invoke(messages)
    if len(reply.tool_calls) != 1 or reply.tool_calls[0]["name"] != "synthetic_lookup":
        raise ValueError("synthetic tool call missing")
    final = model.invoke([*messages, reply, ToolMessage(
        content="합성 자료: 나무 그림", tool_call_id=reply.tool_calls[0]["id"],
    )])
    if not final.content:
        raise ValueError("synthetic tool result response missing")
    return {"text": True, "structured_output": True, "tool_roundtrip": True}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default=ELICE_CLAUDE_BASE_URL,
                        help="다른 엘리스 /v1 주소를 명시할 때만 사용")
    args = parser.parse_args()
    try:
        result = check(EliceClaudeConfig(base_url=args.base_url,
                                        api_key=os.environ.get("ML_API_KEY", "")))
    except Exception as error:
        print(json.dumps({"ok": False, "error_type": type(error).__name__}))
        raise SystemExit(1) from None
    print(json.dumps({"ok": True, "checks": result}))


if __name__ == "__main__":
    main()
