import os

os.environ["PYANNOTE_METRICS_ENABLED"] = "0"

import torch
from pyannote.audio import Pipeline


pipeline = Pipeline.from_pretrained(
    "pyannote/speaker-diarization-community-1",
)

device = torch.device("cuda" if torch.cuda.is_available() else "")
print(f"Using device: {device}")
pipeline.to(device)

output = pipeline(
    "docs/stt-mobile-benchmark/data/kcsc/WAV/generated/A0051_S0001_0_G0101_G0102.wav",
    num_speakers=2,
)

for turn, speaker in output.exclusive_speaker_diarization:
    print(f"{turn.start:.3f}s ~ {turn.end:.3f}s: {speaker}")