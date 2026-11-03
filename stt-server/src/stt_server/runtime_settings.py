"""모델과 API는 유지하고 GPU별 실행 설정만 분리한다."""

from collections.abc import Mapping
from dataclasses import dataclass
import os


_COMPUTE_TYPES = frozenset(
    {"float16", "float32", "int8", "int8_float16", "int8_float32", "bfloat16"}
)


@dataclass(frozen=True)
class RuntimeSettings:
    asr_compute_type: str = "float16"
    cuda_device_index: int = 0

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
        return cls(asr_compute_type=compute_type, cuda_device_index=device_index)
