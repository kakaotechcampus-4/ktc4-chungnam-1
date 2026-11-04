"""서버가 실제로 여는 API 경로와 `docs/architecture/api-spec.md`의 경로 목록이 같은지 확인한다.

명세에서 `### 번호.` 다음에 백틱으로 감싼 `METHOD /경로` 제목만 읽는다. 요청과 응답 필드, 설명 문장은 비교하지 않는다.
경로 변수 이름(`{profileId}` 등)은 비교하지 않고 자리만 맞춘다.
"""

import re
from pathlib import Path

from app.main import app

SPEC = Path(__file__).resolve().parents[2] / "docs" / "architecture" / "api-spec.md"
METHODS = {"GET", "POST", "PATCH", "PUT", "DELETE"}

# 서버에는 있지만 명세 대상이 아닌 경로. 운영 상태 확인은 `backend/README.md`에 둔다.
NOT_IN_SPEC = {("GET", "/health/live"), ("GET", "/health/ready")}
# 명세에는 있지만 이 서버가 아닌 AI 서버가 여는 경로(8절 내부 API).
SERVED_ELSEWHERE_PREFIX = "/internal/"


def _normalize(path: str) -> str:
    return re.sub(r"\{[^}]+\}", "{}", path)


def _server_routes() -> set[tuple[str, str]]:
    routes = set()
    for path, operations in app.openapi()["paths"].items():
        for method in operations:
            if method.upper() in METHODS:
                routes.add((method.upper(), _normalize(path)))
    return routes - {(m, _normalize(p)) for m, p in NOT_IN_SPEC}


def _documented_routes() -> set[tuple[str, str]]:
    text = SPEC.read_text(encoding="utf-8")
    found = re.findall(
        r"^#{3} [0-9]+-[0-9]+\. `(GET|POST|PATCH|PUT|DELETE) (/[^`\s]+)`", text, re.M
    )
    return {
        (method, _normalize(path))
        for method, path in found
        if not path.startswith(SERVED_ELSEWHERE_PREFIX)
    }


def test_every_server_route_is_documented() -> None:
    missing = sorted(_server_routes() - _documented_routes())
    assert not missing, f"api-spec.md에 없는 서버 경로: {missing}"


def test_every_documented_route_exists_on_the_server() -> None:
    missing = sorted(_documented_routes() - _server_routes())
    assert not missing, f"서버에 없는 명세 경로: {missing}"
