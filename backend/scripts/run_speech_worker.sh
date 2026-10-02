#!/usr/bin/env bash
set -euo pipefail

uv run python -m app.workers.speech_analysis "$@"
