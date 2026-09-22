# 새록 AI 서버

온프레미스 GPU 환경에서 STT와 VLM 파이프라인을 실행하기 위한 FastAPI 서버다.

현재 구현 범위는 S3 Presigned GET URL 또는 허가된 로컬 WAV 파일을 입력으로 받아 Whisper ASR과
pyannote 화자 분리를 순서대로 실행하고, 두 결과를 시간축으로 결합하여 반환하는 흐름까지다.

음성 입력은 Provider로 분리되어 있으며 S3와 로컬 입력 모두 같은 STT 서비스와 모델 실행 로직을
사용한다. 운영 요청은 WAV/PCM 16-bit/16kHz/mono 규격만 받는다.

## 백엔드 연동

음성 분석 API는 `POST /internal/v1/speech-analyses`다. 백엔드는 음성 처리 동의를 확인한 요청만
보내고 동의 이력을 보관한다. AI 서버는 동의 정보를 별도 필드로 받지 않는다.

```json
{
  "schemaVersion": 1,
  "analysisId": "analysis_demo_001",
  "language": "ko",
  "speakerCount": 2,
  "audioSource": {
    "type": "s3PresignedGet",
    "downloadUrl": "https://example-bucket.s3.ap-northeast-2.amazonaws.com/audio.wav?...",
    "downloadUrlExpiresAt": "2026-09-22T15:10:00+09:00",
    "sizeBytes": 123456,
    "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  },
  "dataExpiresAt": "2026-09-22T16:00:00+09:00"
}
```

AI 서버는 URL 만료, 허용된 S3 호스트, 크기, SHA-256과 WAV 규격을 확인한다. 다운로드 파일은
모델 처리 성공 여부와 관계없이 요청이 끝날 때 삭제한다. Presigned URL과 전사 내용은 로그에
남기지 않는다.

## 로컬 음성으로 반복 테스트

현재 로컬 테스트에서는 `docs/stt-mobile-benchmark/data/kcsc/WAV`에 있는 KCSC WAV 파일을 사용한다.
별도의 폴더로 복사하지 않고 요청에 파일 이름만 전달한다.

개발 환경에서는 같은 API에 `localFile` 입력을 전달한다.

```json
{
  "schemaVersion": 1,
  "analysisId": "analysis_test_001",
  "language": "ko",
  "speakerCount": 1,
  "audioSource": {
    "type": "localFile",
    "audioFileName": "A0051_S0001_0_G0101.wav"
  }
}
```

로컬 Provider는 `docs/stt-mobile-benchmark/data/kcsc/WAV`와 `audioFileName`을 합쳐 경로를 만든다.
절대 경로와 상위 폴더 접근은 허용하지 않는다.
같은 파일을 `large-v3-turbo`와 pyannote 화자 분리 모델에 순서대로 전달하고, ASR 단어가 가장 오래
겹치는 exclusive 화자 구간에 단어를 배정한다. 단어 타임스탬프가 없는 ASR 구간은 구간 전체를
정렬 단위로 사용한다. 화자 구간과 겹치지 않거나 서로 다른 화자와 같은 시간만큼 겹치는 전사
단위의 `speakerLabel`은 `null`로 둔다.

응답에는 전체 텍스트와 화자별 전사 구간이 포함된다. 각 구간은 시작·종료 시각, pyannote가 만든
화자 군집 라벨, 구간 텍스트와 ASR 단어 목록을 가진다. `SPEAKER_00` 같은 라벨은 파일 안의 화자
군집을 뜻하며 보호자 또는 피보호자 역할을 의미하지 않는다.

운영 환경에서는 `SAEROK_ENVIRONMENT=production`을 설정하면 로컬 입력이 기본으로 비활성화된다.
`SAEROK_ALLOW_LOCAL_AUDIO`, `SAEROK_LOCAL_AUDIO_DIRECTORY`, `SAEROK_S3_ALLOWED_HOST_SUFFIXES`와
`SAEROK_MAX_AUDIO_BYTES`로 입력 정책을 조정할 수 있다. 실제 키와 Presigned URL은 환경 변수나
문서에 저장하지 않는다.

## 실행

```bash
chmod +x scripts/run_ai.sh
./scripts/run_ai.sh
```

혹은

```bash
uv run ai
```

기본 주소는 `http://127.0.0.1:8001`이다.

```bash
curl http://127.0.0.1:8001/health/live
```

## 테스트

```bash
PYTHONPATH=src uv run python -m unittest discover -s tests -v
```

결합 로직 테스트는 모델을 호출하지 않는다. 작은 합성 ASR·화자 분리 fixture로 경계 조건을
검증하고, 이미 저장된 실제 ASR 출력도 고정 입력으로 사용한다. 실제 diarization 출력 fixture는
허가된 동일 음성으로 두 모델의 결과를 함께 생성한 뒤 추가한다.

GPU 환경에서 실제 두 모델의 출력을 한 번 저장하려면 다음 명령을 사용한다. 출력 폴더에는
`asr.json`, `diarization.json`, `combined.json`과 실행 메타데이터가 생성된다. KCSC처럼 재배포할 수
없는 입력에서 만든 결과는 `tests/fixtures/`가 아니라 Git에서 제외된 로컬 폴더에 저장한다.

```bash
PYTHONPATH=src uv run python scripts/capture_stt_fixture.py \
  --audio-file-name generated/A0051_S0001_0_G0101_G0102.wav \
  --speaker-count 2 \
  --output-directory tests/results/local/stt-two-speakers
```
