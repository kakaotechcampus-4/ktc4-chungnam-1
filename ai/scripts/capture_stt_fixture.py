"""Run both local models once and save reusable STT pipeline fixtures."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path

from ai.api.schemas import LocalSpeechAnalysisRequest
from ai.stt.schemas import AsrResult, DiarizationResult, SpeechAnalysisResult


ASR_MODEL_NAME = "large-v3-turbo"
DIARIZATION_MODEL_NAME = "pyannote/speaker-diarization-community-1"


def capture_fixture(
    payload: LocalSpeechAnalysisRequest,
) -> tuple[AsrResult, DiarizationResult, SpeechAnalysisResult]:
    """Run the two models and return their raw and combined results."""

    # Importing the application loads the GPU models, so keep it inside the
    # explicit capture path rather than module import used by unit tests.
    from ai.main import app

    artifacts = app.state.speech_analysis_service.analyze_with_artifacts(
        payload.to_speech_analysis_request()
    )
    return artifacts.asr, artifacts.diarization, artifacts.combined


def write_fixture(
    output_directory: Path,
    payload: LocalSpeechAnalysisRequest,
    asr_result: AsrResult,
    diarization_result: DiarizationResult,
    combined_result: SpeechAnalysisResult,
    *,
    overwrite: bool,
) -> None:
    """Write model outputs without silently replacing an existing fixture."""

    output_directory.mkdir(parents=True, exist_ok=True)
    output_files = {
        "asr.json": asr_result.model_dump_json(by_alias=True, indent=2),
        "diarization.json": diarization_result.model_dump_json(
            by_alias=True,
            indent=2,
        ),
        "combined.json": combined_result.model_dump_json(by_alias=True, indent=2),
        "metadata.json": json.dumps(
            {
                "generatedAt": datetime.now(timezone.utc).isoformat(),
                "analysisId": payload.analysis_id,
                "audioFileName": payload.audio_file_name,
                "language": payload.language,
                "speakerCount": payload.speaker_count,
                "asrModel": ASR_MODEL_NAME,
                "diarizationModel": DIARIZATION_MODEL_NAME,
                "modelRevisions": None,
            },
            ensure_ascii=False,
            indent=2,
        ),
    }

    existing_files = [
        output_directory / name
        for name in output_files
        if (output_directory / name).exists()
    ]
    if existing_files and not overwrite:
        names = ", ".join(path.name for path in existing_files)
        raise FileExistsError(
            f"fixture 파일이 이미 있습니다: {names} (--force로 덮어쓸 수 있습니다.)"
        )

    for name, content in output_files.items():
        (output_directory / name).write_text(f"{content}\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="실제 ASR·diarization 출력을 모델 없는 회귀 테스트용 JSON으로 저장합니다."
    )
    parser.add_argument("--audio-file-name", required=True)
    parser.add_argument("--output-directory", required=True, type=Path)
    parser.add_argument("--analysis-id", default="fixture_capture")
    parser.add_argument("--language", default="ko")
    parser.add_argument("--speaker-count", default=2, type=int)
    parser.add_argument("--force", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    payload = LocalSpeechAnalysisRequest(
        analysisId=args.analysis_id,
        language=args.language,
        speakerCount=args.speaker_count,
        audioFileName=args.audio_file_name,
    )
    results = capture_fixture(payload)
    write_fixture(
        args.output_directory,
        payload,
        *results,
        overwrite=args.force,
    )


if __name__ == "__main__":
    main()
