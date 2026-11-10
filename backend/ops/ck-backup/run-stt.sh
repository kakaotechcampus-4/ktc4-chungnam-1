#!/bin/sh
set -eu

runtime_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SAEROK_CK_CONFIG_FILE:-$runtime_dir/runtime.env}"
: "${SAEROK_CK_APP_DIR:?ck STT app directory is required}"
: "${HF_HOME:?offline model cache directory is required}"
: "${SAEROK_STT_CUDA_DEVICE_INDEX:?GPU index is required}"
: "${SAEROK_STT_ASR_COMPUTE_TYPE:?compute type is required}"

export HF_HOME HF_HUB_OFFLINE=1 PYANNOTE_METRICS_ENABLED=0
export SAEROK_STT_CUDA_DEVICE_INDEX SAEROK_STT_ASR_COMPUTE_TYPE
# 전사 옵션은 runtime.env에 적었을 때만 넘긴다. 적지 않으면 서버 기본값(VAD 켬, 앞 문장 조건 끔)을 쓴다.
export SAEROK_STT_ASR_VAD_FILTER SAEROK_STT_ASR_CONDITION_ON_PREVIOUS_TEXT
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export SAEROK_ENVIRONMENT=production SAEROK_ALLOW_LOCAL_AUDIO=false
export TMPDIR="$runtime_dir/audio-temp"
export LD_LIBRARY_PATH="$SAEROK_CK_APP_DIR/.venv/lib/python3.12/site-packages/nvidia/cublas/lib:$SAEROK_CK_APP_DIR/.venv/lib/python3.12/site-packages/nvidia/cudnn/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
mkdir -p "$TMPDIR"
chmod 700 "$TMPDIR"
cd "$SAEROK_CK_APP_DIR"
exec .venv/bin/python -m uvicorn stt_server.main:app --host 127.0.0.1 --port 18001 --workers 1 --no-access-log --log-level warning
