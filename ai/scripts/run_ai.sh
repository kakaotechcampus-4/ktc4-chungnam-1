#!/usr/bin/env bash

PROJECT_DIRECTORY="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIRECTORY"

PYTHON_SITE_PACKAGES="$(uv run python -c 'import sysconfig; print(sysconfig.get_path("purelib"))')"

export LD_LIBRARY_PATH="$PYTHON_SITE_PACKAGES/nvidia/cublas/lib:$PYTHON_SITE_PACKAGES/nvidia/cudnn/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

exec uv run ai