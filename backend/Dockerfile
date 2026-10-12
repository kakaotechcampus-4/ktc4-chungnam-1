# 새록 백엔드 API와 worker가 함께 쓰는 이미지. 실행 방법은 docs/deployment.md를 따른다.
# 비밀값(.env)은 이미지에 넣지 않고 실행할 때 환경 변수로 주입한다.
FROM python:3.12-slim

# 로컬 개발과 같은 uv 버전으로 uv.lock을 그대로 설치한다.
COPY --from=ghcr.io/astral-sh/uv:0.11.19 /uv /bin/uv

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    PYTHONUNBUFFERED=1 \
    PATH="/app/.venv/bin:$PATH"

WORKDIR /app

# 의존성 층을 소스와 분리해 코드만 바뀐 빌드는 설치를 다시 하지 않는다.
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev

COPY alembic.ini ./
COPY alembic ./alembic
COPY app ./app

RUN useradd --system --uid 10001 --no-create-home saerok
USER saerok

EXPOSE 8000

# 세션 폐기 목록이 프로세스 메모리에 있으므로 API 프로세스는 하나만 띄운다.
# 개발용 scripts/run_backend.sh의 --reload는 Windows 이벤트 루프 대응이라 쓰지 않는다.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1", "--no-access-log"]
