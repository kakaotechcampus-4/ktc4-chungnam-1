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
# 카드 생성 패키지(saerok-local-ai)는 pyproject가 ../ai를 가리켜 /ai에 둔다. ai/는 compose의 additional_contexts로 받는다.
COPY pyproject.toml uv.lock ./
COPY --from=ai pyproject.toml /ai/
RUN uv sync --frozen --no-dev --no-install-package saerok-local-ai

COPY --from=ai common /ai/common
COPY --from=ai card_generation /ai/card_generation
COPY --from=ai report_generation /ai/report_generation
COPY --from=ai proposal_generation /ai/proposal_generation
RUN uv sync --frozen --no-dev

COPY alembic.ini ./
COPY alembic ./alembic
COPY app ./app

RUN useradd --system --uid 10001 --no-create-home saerok
USER saerok

EXPOSE 8000

# 개발 서버는 API 프로세스 하나로 띄운다. 세션 폐기 기록은 DB에 있어 프로세스 수의 제약은 아니다.
# 개발용 scripts/run_backend.sh의 --reload는 Windows 이벤트 루프 대응이라 쓰지 않는다.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1", "--no-access-log"]
