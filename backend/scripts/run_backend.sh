#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIRECTORY="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIRECTORY"

BACKEND_HOST="${SAEROK_BACKEND_HOST:-127.0.0.1}"
BACKEND_PORT="${SAEROK_BACKEND_PORT:-8000}"

exec uv run uvicorn app.main:app \
  --host "$BACKEND_HOST" \
  --port "$BACKEND_PORT" \
  --reload \
  --no-access-log