"""#116 소규모 실제 모델 점검 실행기. 키는 ML_API_KEY 환경 변수에서만 읽고 어디에도 쓰지 않는다.

저장소 루트에서 ai 프로젝트 환경으로 실행한다. 사용법은 같은 폴더의 README.md를 본다.

    uv run --offline --project ai python <이 폴더>/run.py check                 # 호출 없이 입력 검증만
    uv run --offline --project ai python <이 폴더>/run.py reports               # 리포트와 변경 제안 3쌍(6회 호출 예상)
    uv run --offline --project ai python <이 폴더>/run.py card rich|rich-uuid|sparse|sparse-uuid

호출 수는 출력 폴더의 calls.json에 누적하고 전체 40회를 넘기려는 순간 콜백이 예외로 호출을 막는다.
출력 폴더는 SPOT_CHECK_OUT 환경 변수로 정하고, 없으면 OS 임시 폴더 아래 saerok-spot-check-116을 쓴다.
커밋된 outputs/를 덮어쓰지 않도록 기본값을 저장소 밖에 둔다.

SPOT_CHECK_MODEL을 설정하면 그 모델로 검사한다. 없으면 기존 5.6 모델을 사용한다.
출력 한도는 현재 ChatConfig 기본값이다. 이전 결과의 모델, 한도를 새 실행으로 덮어쓰지 않는다.
"""

from __future__ import annotations

import contextvars
import json
import os
import re
import sys
import tempfile
import time
import traceback
from pathlib import Path

HERE = Path(__file__).resolve().parent
AI = HERE.parents[2] / "ai"
sys.path.insert(0, str(AI))
sys.path.insert(0, str(HERE))

from langchain_core.callbacks import BaseCallbackHandler  # noqa: E402
from langchain_core.tracers.context import register_configure_hook  # noqa: E402

OUT = Path(os.environ.get("SPOT_CHECK_OUT") or Path(tempfile.gettempdir()) / "saerok-spot-check-116")
LEDGER = OUT / "calls.json"
CAP = 40
MODEL = os.environ.get("SPOT_CHECK_MODEL", "gpt-5.6-luna")


class BudgetExceeded(RuntimeError):
    pass


class Counter(BaseCallbackHandler):
    raise_error = True

    def __init__(self, used: int) -> None:
        self.used = used
        self.calls: list[dict] = []
        self.started: dict = {}

    def on_chat_model_start(self, serialized, messages, *, run_id, **kwargs):
        if self.used >= CAP:
            raise BudgetExceeded(f"호출 상한 {CAP}회 도달")
        self.used += 1
        self.started[run_id] = time.monotonic()

    def on_llm_end(self, response, *, run_id, **kwargs):
        gen = response.generations[0][0] if response.generations and response.generations[0] else None
        msg = getattr(gen, "message", None)
        usage = dict(getattr(msg, "usage_metadata", None) or {})
        meta = dict(getattr(msg, "response_metadata", None) or {})
        self.calls.append({"seconds": round(time.monotonic() - self.started.pop(run_id, time.monotonic()), 1),
                           "usage": usage, "model_name": meta.get("model_name") or meta.get("model"),
                           "ok": True})

    def on_llm_error(self, error, *, run_id, **kwargs):
        self.calls.append({"seconds": round(time.monotonic() - self.started.pop(run_id, time.monotonic()), 1),
                           "ok": False, "error": f"{type(error).__name__}: {str(error)[:300]}"})


_var: contextvars.ContextVar = contextvars.ContextVar("spot_counter", default=None)
register_configure_hook(_var, inheritable=True)


def ledger() -> dict:
    return json.loads(LEDGER.read_text(encoding="utf-8")) if LEDGER.exists() else {"used": 0, "runs": []}


def scrub(text: str) -> str:
    key = os.environ.get("ML_API_KEY", "")
    text = text.replace(key, "[REDACTED]") if key else text
    return re.sub(r"https?://[^\s\"'<>]+", "[URL_REDACTED]", text)


def record(name: str, counter: Counter, started: float, used_before: int, result=None, error=None) -> None:
    from common.llm import ChatConfig
    config = ChatConfig(model=MODEL, api_key="")
    data = ledger()
    data["used"] = counter.used
    data["runs"].append({"name": name, "requested_model": MODEL,
                         "max_output_tokens": config.max_tokens, "effort": config.effort,
                         "calls_attempted": counter.used - used_before,
                         "wall_seconds": round(time.monotonic() - started, 1), "calls": counter.calls,
                         "error": scrub(error) if error else None})
    LEDGER.write_text(scrub(json.dumps(data, ensure_ascii=False, indent=2)), encoding="utf-8")
    if result is not None:
        (OUT / f"{name}.json").write_text(scrub(json.dumps(result, ensure_ascii=False, indent=2)), encoding="utf-8")


def check() -> int:
    """모델을 부르지 않고 합성 입력이 현재 요청 계약을 통과하는지만 본다."""
    import inputs
    from card_generation import GenerationRequest
    from common.visit_report import VisitReportRequest
    for name in ("CARD_RICH", "CARD_RICH_UUID", "CARD_SPARSE", "CARD_SPARSE_UUID"):
        GenerationRequest.model_validate(getattr(inputs, name))
        print(name, "ok")
    for name in ("REPORT_CLEAR", "REPORT_MERGED", "REPORT_THIRD"):
        VisitReportRequest.model_validate(getattr(inputs, name))
        print(name, "ok")
    return 0


def main() -> int:
    mode = sys.argv[1]
    if mode == "check":
        return check()
    key = os.environ.get("ML_API_KEY", "")
    if not key:
        print("ML_API_KEY 없음")
        return 2
    OUT.mkdir(parents=True, exist_ok=True)
    from common.llm import ENDPOINTS
    if MODEL not in ENDPOINTS:
        print("등록되지 않은 SPOT_CHECK_MODEL")
        return 2
    failed = False
    import inputs
    if mode == "reports":
        from common.visit_report import VisitReportRequest
        from proposal_generation import generate_proposals
        from report_generation import generate_report
        for case_name, payload in (("clear", inputs.REPORT_CLEAR), ("merged", inputs.REPORT_MERGED),
                                   ("third", inputs.REPORT_THIRD)):
            req = VisitReportRequest.model_validate(payload)
            for kind, fn in (("report", generate_report), ("proposals", generate_proposals)):
                name = f"{kind}-{case_name}"
                counter = Counter(ledger()["used"])
                before, started = counter.used, time.monotonic()
                token = _var.set(counter)
                try:
                    out = fn(req, model=MODEL, api_key=key)
                    record(name, counter, started, before, result=out.model_dump(by_alias=True))
                    print(name, "ok", counter.used - before, "calls", round(time.monotonic() - started, 1), "s")
                except Exception as error:
                    failed = True
                    record(name, counter, started, before, error=f"{type(error).__name__}: {error}")
                    print(name, "FAILED", scrub(f"{type(error).__name__}: {str(error)[:300]}"))
                finally:
                    _var.reset(token)
    elif mode == "card":
        from card_generation import GenerationRequest, generate_cards
        payload = {"rich": inputs.CARD_RICH, "sparse": inputs.CARD_SPARSE, "rich-uuid": inputs.CARD_RICH_UUID, "sparse-uuid": inputs.CARD_SPARSE_UUID}[sys.argv[2]]
        name = f"card-{sys.argv[2]}"
        counter = Counter(ledger()["used"])
        before, started = counter.used, time.monotonic()
        token = _var.set(counter)
        try:
            out = generate_cards(GenerationRequest.model_validate({**payload, "model": MODEL}), api_key=key, seed=116)
            record(name, counter, started, before, result=out.model_dump(by_alias=True))
            print(name, "ok", counter.used - before, "calls", round(time.monotonic() - started, 1), "s")
        except Exception as error:
            failed = True
            record(name, counter, started, before, error=f"{type(error).__name__}: {error}\n{traceback.format_exc()[-1500:]}")
            print(name, "FAILED", scrub(f"{type(error).__name__}: {str(error)[:500]}"))
        finally:
            _var.reset(token)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
