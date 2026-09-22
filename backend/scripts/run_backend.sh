#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIRECTORY="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIRECTORY"

export SAEROK_AI_SERVER_URL="${SAEROK_AI_SERVER_URL:-http://127.0.0.1:8001}"

BACKEND_HOST="${SAEROK_BACKEND_HOST:-127.0.0.1}"
BACKEND_PORT="${SAEROK_BACKEND_PORT:-8000}"

exec uv run uvicorn app.main:app \
  --host "$BACKEND_HOST" \
  --port "$BACKEND_PORT" \
  --reload \
  --no-access-log
