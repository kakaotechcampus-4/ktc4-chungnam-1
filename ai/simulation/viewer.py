"""시뮬레이션 결과 JSON을 한 장짜리 HTML로 만든다. 주제판 기록을 읽는다(합치기 전 pr84-* 기록 포함).

    uv run python -m simulation.viewer simulation/runs/persona-topics-seocheon-seamstress-7-<시각>.json   # → 같은 이름의 .html
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from .backends import recommender_of

HERE = Path(__file__).resolve().parent
TEMPLATE = HERE / "viewer_template.html"
DBVIEW = HERE / "web" / "dbview.js"  # 작업대와 같이 쓰는 DB 보기. 한 장짜리 파일이 되게 안에 넣는다


def render(data: dict) -> str:
    data = {**data, "recommender": recommender_of(data)}
    # </script>가 데이터 안에 있어도 태그가 닫히지 않게 한다
    payload = json.dumps(data, ensure_ascii=False, default=str).replace("</", "<\\/")
    return TEMPLATE.read_text().replace("/*__DBVIEW_JS__*/", DBVIEW.read_text()).replace("__RUN_JSON__", payload)


def build(run_path: Path) -> Path:
    out = run_path.with_suffix(".html")
    out.write_text(render(json.loads(run_path.read_text())))
    return out


if __name__ == "__main__":
    print(build(Path(sys.argv[1])))
