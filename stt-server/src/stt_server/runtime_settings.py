"""모델과 API는 유지하고 GPU별 실행 설정과 전사 옵션을 분리한다.

전사 옵션 기본값(VAD 켬, 앞 문장 조건 끔)은 2026-11-09 ck에서 실제 어르신과 자녀의 대화
녹음으로 비교한 결과다(docs/vad-condition-comparison-20261109.md). 문제가 생기면 코드를
바꾸지 않고 환경 변수로 되돌릴 수 있다.
"""

from collections.abc import Mapping
from dataclasses import dataclass
import os


_COMPUTE_TYPES = frozenset(
    {"float16", "float32", "int8", "int8_float16", "int8_float32", "bfloat16"}
)
# 기존 SAEROK_ALLOW_LOCAL_AUDIO처럼 1/yes/on도 참으로 받되, 알아볼 수 없는 값은 기본값으로
# 넘어가지 않고 거절한다(되돌리려다 오타로 다른 동작이 되지 않게).
_BOOLEANS = {"true": True, "1": True, "yes": True, "on": True,
             "false": False, "0": False, "no": False, "off": False}


def _boolean(values: Mapping[str, str], name: str, default: bool) -> bool:
    raw = values.get(name)
    if raw is None:
        return default
    parsed = _BOOLEANS.get(raw.strip().lower())
    if parsed is None:
        raise RuntimeError(f"{name}는 true/false(또는 1/0, yes/no, on/off)여야 합니다.")
    return parsed


@dataclass(frozen=True)
class RuntimeSettings:
    asr_compute_type: str = "float16"
    cuda_device_index: int = 0
    # 말소리 구간만 전사한다. 무음과 소음에서 지어낸 말을 줄인다.
    asr_vad_filter: bool = True
    # 앞 구간 전사를 다음 구간의 조건으로 넘기지 않는다. 같은 말을 되풀이하는 환각을 줄인다.
    asr_condition_on_previous_text: bool = False

    @property
    def torch_cuda_device(self) -> str:
        return f"cuda:{self.cuda_device_index}"

    @classmethod
    def from_environment(
        cls, environment: Mapping[str, str] | None = None,
    ) -> "RuntimeSettings":
        values = os.environ if environment is None else environment
        compute_type = values.get("SAEROK_STT_ASR_COMPUTE_TYPE", "float16").strip()
        if compute_type not in _COMPUTE_TYPES:
            raise RuntimeError("SAEROK_STT_ASR_COMPUTE_TYPE이 지원하는 설정값이 아닙니다.")
        try:
            device_index = int(values.get("SAEROK_STT_CUDA_DEVICE_INDEX", "0"))
        except ValueError:
            raise RuntimeError("SAEROK_STT_CUDA_DEVICE_INDEX는 0 이상의 정수여야 합니다.") from None
        if device_index < 0:
            raise RuntimeError("SAEROK_STT_CUDA_DEVICE_INDEX는 0 이상의 정수여야 합니다.")
        return cls(
            asr_compute_type=compute_type,
            cuda_device_index=device_index,
            asr_vad_filter=_boolean(values, "SAEROK_STT_ASR_VAD_FILTER", True),
            asr_condition_on_previous_text=_boolean(
                values, "SAEROK_STT_ASR_CONDITION_ON_PREVIOUS_TEXT", False,
            ),
        )
