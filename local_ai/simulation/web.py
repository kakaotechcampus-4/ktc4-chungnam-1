"""페르소나 시뮬레이션 작업대(로컬 전용). 페르소나와 프롬프트를 보고 고치고, 추천 판을 골라 실행하고, 진행을 실시간으로 본다.

    TOPIC_REC_DATABASE_URL=... uv run python -m simulation.web    # → http://127.0.0.1:8780

127.0.0.1에만 띄운다. 한 번에 실행 하나만 돈다. 프롬프트를 처음 고칠 때 원본을 runs/backups/에 남긴다.
기록 탭에는 합치기 전 주제판 기록(pr84-*)도 같이 나온다.
"""

from __future__ import annotations

import json
import os
import shutil
import threading
import time
from pathlib import Path
from typing import Any

import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, HTMLResponse, StreamingResponse
from pydantic import BaseModel

from .backends import get_backend, recommender_of
from .run import DB_ENV, ROOT, prompt_files, simulate
from .viewer import DBVIEW, render

HERE = Path(__file__).resolve().parent
PERSONAS = HERE / "personas"
RUNS = HERE / "runs"
BACKUPS = RUNS / "backups"
RECOMMENDERS = ("topics",)


def _prompt_keys() -> dict[str, tuple[str, Path]]:
    """두 판에서 쓰는 프롬프트를 한 목록으로. 추천 프롬프트는 판마다 달라 이름 앞에 판을 붙인다."""
    seen: dict[Path, str] = {}
    for name in RECOMMENDERS:
        backend = get_backend(name)
        own = {ROOT / p for p in backend.prompt_files.values()}
        for label, path in prompt_files(backend).items():
            if path not in seen:
                seen[path] = f"[{'주제판' if name == 'topics' else '요소판'}] {label}" if path in own else label
    return {f"p{i}": (label, path) for i, (path, label) in enumerate(seen.items(), 1)}


PROMPT_KEYS = _prompt_keys()
app = FastAPI()


class Live:
    """지금 도는 실행 하나의 상태와 이벤트."""

    def __init__(self) -> None:
        self.lock = threading.Condition()
        self.events: list[dict[str, Any]] = []
        self.running = False
        self.stop = False
        self.run_name: str | None = None
        self.error: str | None = None

    def add(self, event: dict[str, Any]) -> None:
        with self.lock:
            event["seq"] = len(self.events)
            if event.get("kind") == "run_start":
                self.run_name = event.get("run")
            self.events.append(event)
            self.lock.notify_all()


live = Live()


def _backup_path(path: Path) -> Path:
    # 이름이 같은 파일이 여러 폴더에 있어(prompts/writing.md 등) 프로젝트 기준 경로 전체로 이름을 짓는다
    return BACKUPS / (str(path.relative_to(ROOT)).replace("/", "__") + ".orig")


def _backup(path: Path) -> None:
    BACKUPS.mkdir(parents=True, exist_ok=True)
    target = _backup_path(path)
    if path.exists() and not target.exists():
        shutil.copy(path, target)


# ── 페르소나 ─────────────────────────────────────────
@app.get("/api/personas")
def personas() -> list[str]:
    return sorted(p.stem for p in PERSONAS.glob("*.json"))


@app.get("/api/personas/{name}")
def get_persona(name: str) -> dict[str, Any]:
    path = PERSONAS / f"{Path(name).name}.json"
    if not path.exists():
        raise HTTPException(404, "페르소나 파일이 없습니다")
    return {"name": path.stem, "text": path.read_text()}


class Text(BaseModel):
    text: str


@app.put("/api/personas/{name}")
def put_persona(name: str, body: Text) -> dict[str, str]:
    try:
        data = json.loads(body.text)
    except json.JSONDecodeError as error:
        raise HTTPException(400, f"JSON 형식이 맞지 않습니다: {error.msg} ({error.lineno}행 {error.colno}열)")
    missing = [k for k in ("id", "patient", "caregiver", "visits") if k not in data]
    if missing:
        raise HTTPException(400, f"필요한 항목이 없습니다: {', '.join(missing)}")
    path = PERSONAS / f"{Path(name).name}.json"
    _backup(path)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    return {"saved": path.name}


# ── 프롬프트 ─────────────────────────────────────────
@app.get("/api/prompts")
def prompts() -> list[dict[str, Any]]:
    out = []
    for key, (label, path) in PROMPT_KEYS.items():
        backup = _backup_path(path)
        out.append({"key": key, "label": label, "path": str(path.relative_to(ROOT)), "text": path.read_text(),
                    "edited": backup.exists() and backup.read_text() != path.read_text()})
    return out


@app.put("/api/prompts/{key}")
def put_prompt(key: str, body: Text) -> dict[str, str]:
    if key not in PROMPT_KEYS:
        raise HTTPException(404, "없는 프롬프트입니다")
    _, path = PROMPT_KEYS[key]
    _backup(path)
    path.write_text(body.text)
    return {"saved": str(path.relative_to(ROOT))}


@app.post("/api/prompts/{key}/restore")
def restore_prompt(key: str) -> dict[str, str]:
    if key not in PROMPT_KEYS:
        raise HTTPException(404, "없는 프롬프트입니다")
    _, path = PROMPT_KEYS[key]
    backup = _backup_path(path)
    if not backup.exists():
        raise HTTPException(400, "고친 적이 없어서 되돌릴 원본이 없습니다")
    shutil.copy(backup, path)
    return {"restored": str(path.relative_to(ROOT))}


# ── 실행 ────────────────────────────────────────────
class Start(BaseModel):
    persona: str
    recommender: str = "topics"
    visits: int = 5
    seed: int = 7


@app.post("/api/run")
def start(body: Start) -> dict[str, Any]:
    url = os.environ.get(DB_ENV)
    if not url:
        raise HTTPException(500, f"{DB_ENV} 환경 변수가 없습니다")
    if body.recommender not in RECOMMENDERS:
        raise HTTPException(400, "추천 판은 topics뿐입니다")
    path = PERSONAS / f"{Path(body.persona).name}.json"
    if not path.exists():
        raise HTTPException(404, "페르소나 파일이 없습니다")
    with live.lock:
        if live.running:
            raise HTTPException(409, "이미 실행 중입니다. 끝나거나 멈춘 뒤에 다시 시작하세요")
        live.events, live.running, live.stop, live.run_name, live.error = [], True, False, None, None

    def work() -> None:
        try:
            simulate(path, body.recommender, max(1, min(body.visits, 10)), body.seed, url, sink=live.add,
                     should_stop=lambda: live.stop)
        except Exception as error:
            live.error = f"{type(error).__name__}: {error}"
            live.add({"kind": "run_error", "stage": "", "ts": time.time(), "error": live.error})
        finally:
            with live.lock:
                live.running = False
                live.lock.notify_all()

    threading.Thread(target=work, daemon=True).start()
    return {"started": True}


@app.post("/api/stop")
def stop() -> dict[str, bool]:
    live.stop = True  # 지금 회차는 끝까지 돌고, 다음 회차 전에 멈춘다
    return {"stopping": live.running}


@app.get("/api/status")
def status() -> dict[str, Any]:
    return {"running": live.running, "run": live.run_name, "events": len(live.events), "error": live.error,
            "stopping": live.stop}


@app.get("/api/events")
def events(since: int = 0) -> StreamingResponse:
    def stream():
        i = since
        idle = 0
        while True:
            with live.lock:
                if i >= len(live.events):
                    live.lock.wait(timeout=15)
                batch = live.events[i:]
            if batch:
                idle = 0
                for e in batch:
                    yield f"data: {json.dumps(e, ensure_ascii=False, default=str)}\n\n"
                i += len(batch)
            else:
                idle += 1
                yield ": keep-alive\n\n"
                if not live.running and idle > 2:
                    return

    return StreamingResponse(stream(), media_type="text/event-stream", headers={"Cache-Control": "no-cache"})


# ── 기록 ────────────────────────────────────────────
def _run_files() -> list[Path]:
    return [p for p in RUNS.glob("*.json") if p.name.startswith(("persona-", "pr84-"))]


@app.get("/api/runs")
def runs() -> list[dict[str, Any]]:
    out = []
    for path in _run_files():
        try:
            data = json.loads(path.read_text())
        except (json.JSONDecodeError, OSError):
            continue
        out.append({"name": path.stem, "persona": data.get("persona", {}).get("id"), "seed": data.get("seed"),
                    "recommender": recommender_of(data), "started_at": data.get("started_at"),
                    "visits": len(data.get("visits", [])), "failure": data.get("failure"),
                    "has_events": path.with_suffix(".events.jsonl").exists()})
    return sorted(out, key=lambda r: r["started_at"] or "", reverse=True)


@app.get("/runs/{name}/view", response_class=HTMLResponse)
def view(name: str) -> str:
    path = RUNS / f"{Path(name).name}.json"
    if not path.exists():
        raise HTTPException(404, "기록이 없습니다")
    return render(json.loads(path.read_text()))


@app.get("/api/runs/{name}")
def run_json(name: str) -> dict[str, Any]:
    path = RUNS / f"{Path(name).name}.json"
    if not path.exists():
        raise HTTPException(404, "기록이 없습니다")
    return json.loads(path.read_text())


@app.get("/api/runs/{name}/events")
def past_events(name: str) -> list[dict[str, Any]]:
    path = RUNS / f"{Path(name).name}.events.jsonl"
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


@app.get("/static/dbview.js")
def dbview_js() -> FileResponse:
    return FileResponse(DBVIEW, media_type="text/javascript")


@app.get("/", response_class=HTMLResponse)
def index() -> str:
    return (HERE / "web/index.html").read_text()


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=int(os.environ.get("PERSONA_SIM_PORT", "8780")))
