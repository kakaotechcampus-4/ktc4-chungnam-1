"""운영 점검 결과(`app.ops.runtime_check`의 JSON)를 읽고, 문제 목록이 바뀌었을 때만 알린다.

    python -m app.ops.runtime_check --probe-stt --worker-container speech=... \
      | python -m app.ops.runtime_alert --state /var/lib/saerok/runtime-alert.json

- 알림 주소는 `SAEROK_ALERT_WEBHOOK_URL`(Discord 웹훅 형식)에서만 읽고 어디에도 출력하지 않는다.
- 보내는 내용은 문제 코드, 시각, 서버 이름(`SAEROK_ALERT_HOST_LABEL`)뿐이다. 점검 결과의 다른 값은 보내지 않는다.
- 같은 문제 목록이 이어지면 다시 보내지 않는다. 새 문제가 생기거나 모두 사라졌을 때만 보낸다.
- `--ignore`로 지금 운영에서 이미 알고 있는 문제 코드를 뺄 수 있다(예: 삭제 대기열 처리 전).
- 알림 전송에 실패해도 상태 파일은 바꾸지 않아 다음 실행에서 다시 보낸다.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import UTC, datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlsplit

import httpx

KST = timezone(timedelta(hours=9))
WEBHOOK_ENV = "SAEROK_ALERT_WEBHOOK_URL"
HOST_ENV = "SAEROK_ALERT_HOST_LABEL"


def issues_from(result: dict, ignore: set[str]) -> list[str]:
    """점검 결과에서 알릴 문제 코드만 정렬해 돌려준다. 결과를 읽지 못하면 그 사실 자체를 문제로 본다."""
    issues = result.get("issues")
    if not isinstance(issues, list) or not all(isinstance(i, str) for i in issues):
        return ["RUNTIME_CHECK_OUTPUT_UNREADABLE"]
    return sorted({i for i in issues if i not in ignore})


def load_state(path: Path) -> list[str] | None:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    issues = data.get("issues") if isinstance(data, dict) else None
    return issues if isinstance(issues, list) else None


def save_state(path: Path, issues: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps({"issues": issues}, ensure_ascii=False), encoding="utf-8")
    tmp.replace(path)


def message(previous: list[str] | None, current: list[str], host: str, now: datetime) -> str | None:
    """보낼 문장. 보낼 일이 없으면 None. 처음 실행에서 문제가 없으면 보내지 않는다."""
    if previous == current or (previous is None and not current):
        return None
    when = now.astimezone(KST).strftime("%m/%d %H:%M KST")
    if not current:
        return f"[새록 운영 점검] {host} 문제 해소 ({when})"
    added = [i for i in current if i not in (previous or [])]
    lines = [f"[새록 운영 점검] {host} 확인 필요 ({when})", "현재 문제: " + ", ".join(current)]
    if added and previous:
        lines.append("새로 생긴 문제: " + ", ".join(added))
    return "\n".join(lines)


def valid_webhook(url: str) -> bool:
    parts = urlsplit(url)
    return parts.scheme == "https" and bool(parts.hostname) and not parts.username and not parts.password


def send(url: str, text: str, *, transport: httpx.BaseTransport | None = None) -> bool:
    try:
        with httpx.Client(timeout=10, follow_redirects=False, transport=transport) as client:
            response = client.post(url, json={"content": text})
        return 200 <= response.status_code < 300
    except httpx.HTTPError:
        return False


def run(raw: str, state: Path, ignore: set[str], *, url: str | None, host: str,
        now: datetime, transport: httpx.BaseTransport | None = None) -> int:
    """종료 코드: 0 알림 불필요 또는 전송 성공, 1 전송 실패(상태 유지), 2 설정 오류."""
    try:
        result = json.loads(raw)
    except ValueError:
        result = {}
    current = issues_from(result if isinstance(result, dict) else {}, ignore)
    previous = load_state(state)
    text = message(previous, current, host, now)
    if text is None:
        if previous is None:
            save_state(state, current)
        print(json.dumps({"sent": False, "issues": current}, ensure_ascii=False))
        return 0
    if not url or not valid_webhook(url):
        print(json.dumps({"sent": False, "issues": current, "error": "WEBHOOK_NOT_CONFIGURED"}))
        return 2
    if not send(url, text, transport=transport):
        print(json.dumps({"sent": False, "issues": current, "error": "WEBHOOK_SEND_FAILED"}))
        return 1
    save_state(state, current)
    print(json.dumps({"sent": True, "issues": current}, ensure_ascii=False))
    return 0


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--state", required=True, type=Path, help="지난 알림의 문제 목록을 남길 파일")
    parser.add_argument("--ignore", default="", help="알리지 않을 문제 코드. 쉼표로 구분")
    args = parser.parse_args()
    ignore = {code.strip() for code in args.ignore.split(",") if code.strip()}
    code = run(sys.stdin.read(), args.state, ignore, url=os.environ.get(WEBHOOK_ENV),
               host=os.environ.get(HOST_ENV, "saerok"), now=datetime.now(UTC))
    raise SystemExit(code)


if __name__ == "__main__":
    main()
