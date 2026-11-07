import importlib.util
from pathlib import Path
from types import ModuleType, SimpleNamespace
import unittest
from unittest.mock import patch
from unittest.mock import Mock

from stt_server.runtime_settings import RuntimeSettings
from stt_server.stt.runtime import AsrRuntime


class RuntimeSettingsTest(unittest.TestCase):
    def test_defaults_preserve_the_current_gpu_configuration(self) -> None:
        settings = RuntimeSettings.from_environment({})
        self.assertEqual(settings.asr_compute_type, "float16")
        self.assertEqual(settings.cuda_device_index, 0)
        self.assertEqual(settings.torch_cuda_device, "cuda:0")

    def test_shared_gpu_settings_use_the_same_device_for_both_models(self) -> None:
        settings = RuntimeSettings.from_environment({
            "SAEROK_STT_ASR_COMPUTE_TYPE": "float32",
            "SAEROK_STT_CUDA_DEVICE_INDEX": "2",
        })
        self.assertEqual(settings.asr_compute_type, "float32")
        self.assertEqual(settings.cuda_device_index, 2)
        self.assertEqual(settings.torch_cuda_device, "cuda:2")

    def test_accepts_explicit_supported_compute_types(self) -> None:
        for compute_type in (
            "float16", "float32", "int8", "int8_float16", "int8_float32", "bfloat16",
        ):
            with self.subTest(compute_type=compute_type):
                settings = RuntimeSettings.from_environment({
                    "SAEROK_STT_ASR_COMPUTE_TYPE": compute_type,
                })
                self.assertEqual(settings.asr_compute_type, compute_type)

    def test_rejects_invalid_compute_types_without_falling_back(self) -> None:
        for compute_type in ("", "auto", "fp16", "not-supported"):
            with self.subTest(compute_type=compute_type):
                with self.assertRaisesRegex(RuntimeError, "ASR_COMPUTE_TYPE"):
                    RuntimeSettings.from_environment({
                        "SAEROK_STT_ASR_COMPUTE_TYPE": compute_type,
                    })

    def test_rejects_invalid_device_indices(self) -> None:
        for device_index in ("", "-1", "1.5", "all", "not-an-index"):
            with self.subTest(device_index=device_index):
                with self.assertRaisesRegex(RuntimeError, "CUDA_DEVICE_INDEX"):
                    RuntimeSettings.from_environment({
                        "SAEROK_STT_CUDA_DEVICE_INDEX": device_index,
                    })

    def test_settings_do_not_change_after_environment_is_modified(self) -> None:
        environment = {"SAEROK_STT_CUDA_DEVICE_INDEX": "2"}
        settings = RuntimeSettings.from_environment(environment)
        environment["SAEROK_STT_CUDA_DEVICE_INDEX"] = "3"
        self.assertEqual(settings.cuda_device_index, 2)


class AsrRuntimeConfigurationTest(unittest.TestCase):
    @patch("stt_server.stt.runtime.WhisperModel")
    def test_defaults_keep_the_model_and_precision(self, model) -> None:
        runtime = AsrRuntime(settings=RuntimeSettings())
        model.assert_called_once_with(
            "large-v3-turbo", device="cuda", device_index=0, compute_type="float16",
        )
        self.assertIs(runtime.model, model.return_value)

    @patch("stt_server.stt.runtime.WhisperModel")
    def test_forwards_shared_gpu_settings_without_changing_the_model(self, model) -> None:
        AsrRuntime(settings=RuntimeSettings(
            asr_compute_type="float32", cuda_device_index=2,
        ))
        model.assert_called_once_with(
            "large-v3-turbo", device="cuda", device_index=2, compute_type="float32",
        )

    @patch("stt_server.stt.runtime.WhisperModel")
    def test_direct_runtime_construction_reads_environment(self, model) -> None:
        with patch.dict("os.environ", {
            "SAEROK_STT_ASR_COMPUTE_TYPE": "float32",
            "SAEROK_STT_CUDA_DEVICE_INDEX": "3",
        }):
            AsrRuntime()
        model.assert_called_once_with(
            "large-v3-turbo", device="cuda", device_index=3, compute_type="float32",
        )

    @patch("stt_server.stt.runtime.WhisperModel")
    def test_invalid_environment_does_not_start_model_loading(self, model) -> None:
        with patch.dict("os.environ", {"SAEROK_STT_CUDA_DEVICE_INDEX": "-1"}):
            with self.assertRaises(RuntimeError):
                AsrRuntime()
        model.assert_not_called()

    @patch("stt_server.stt.runtime.WhisperModel")
    def test_model_load_failure_is_not_replaced_with_a_different_model(self, model) -> None:
        model.side_effect = RuntimeError("synthetic GPU initialization failure")
        with self.assertRaisesRegex(RuntimeError, "synthetic GPU"):
            AsrRuntime(settings=RuntimeSettings())
        self.assertEqual(model.call_count, 1)


class ApplicationRuntimeWiringTest(unittest.TestCase):
    def test_application_assigns_both_models_to_the_requested_gpu(self) -> None:
        self._check_application(cuda_available=True, expected_device="cuda:3")

    def test_existing_diarization_cpu_fallback_is_preserved(self) -> None:
        self._check_application(cuda_available=False, expected_device="cpu")

    def _check_application(self, *, cuda_available: bool, expected_device: str) -> None:
        # 모델을 내려받지 않고 실제 앱 생성 함수에 설정이 전달되는지 확인한다.
        torch = ModuleType("torch")
        torch.device = Mock(side_effect=lambda device: device)
        torch.cuda = SimpleNamespace(is_available=lambda: cuda_available)
        pyannote = ModuleType("pyannote")
        audio = ModuleType("pyannote.audio")
        audio.Pipeline = type("Pipeline", (), {"from_pretrained": Mock()})
        module_path = Path(__file__).parents[1] / "src" / "stt_server" / "main.py"
        spec = importlib.util.spec_from_file_location("stt_application_wiring_test", module_path)
        self.assertIsNotNone(spec)
        self.assertIsNotNone(spec.loader)
        module = importlib.util.module_from_spec(spec)
        with (
            patch.dict("sys.modules", {"torch": torch, "pyannote": pyannote, "pyannote.audio": audio}),
            patch.dict("os.environ", {
                "SAEROK_STT_ASR_COMPUTE_TYPE": "float32",
                "SAEROK_STT_CUDA_DEVICE_INDEX": "3",
            }),
            patch("stt_server.stt.runtime.WhisperModel") as whisper,
        ):
            spec.loader.exec_module(module)
        whisper.assert_called_once_with(
            "large-v3-turbo", device="cuda", device_index=3, compute_type="float32",
        )
        audio.Pipeline.from_pretrained.assert_called_once_with(
            "pyannote/speaker-diarization-community-1",
        )
        audio.Pipeline.from_pretrained.return_value.to.assert_called_once_with(expected_device)
        self.assertIsNotNone(module.app.state.speech_analysis_service)


if __name__ == "__main__":
    unittest.main()
