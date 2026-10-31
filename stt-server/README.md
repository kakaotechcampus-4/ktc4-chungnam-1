# 새록 STT 서버

개인 GPU에서 STT 파이프라인을 실행하는 FastAPI 서버다. 현재 BE는 Tailscale 사설망으로 연결한다.
현재 배포 기준은 [ADR-006의 2026-10-31 보완](../docs/architecture/decisions/ADR-006-server-side-ai-processing.md#개인-gpu와-tailscale-임시-연결-2026-10-31-보완)을 따른다.

현재 구현 범위는 S3 Presigned GET URL 또는 허가된 로컬 WAV 파일을 입력으로 받아 Whisper ASR과
pyannote 화자 분리를 순서대로 실행하고, 두 결과를 시간축으로 결합하여 반환하는 흐름까지다.

음성 입력은 Provider로 분리되어 있으며 S3와 로컬 입력 모두 같은 STT 서비스와 모델 실행 로직을
사용한다. 운영 요청은 WAV/PCM 16-bit/16kHz/mono 규격만 받는다.

## 개인 GPU와 Tailscale 운영

GPU와 BE 서버는 관리자가 등록·승인한 tailnet에 연결한다. 담당자 설명상 현재 접근 범위는
승인된 tailnet 기기이며, BE 한 대만 허용하는 정책의 적용·검증 완료를 뜻하지 않는다.
기기별 접속 권한은 실제 Tailscale Grants/ACL 정책을 확인한다. BE만 허용해야 하는 경우에는
BE → GPU의 TCP `8001`을 허용하고 기존 전체 허용 규칙도 함께 좁힌다.

현재 운영에서는 아래 실행 방법으로 GPU 자신의 Tailscale IP에 바인딩한다.
별도 공개 경로가 없다면 인터넷에서 해당 IP만 알아서는 접속할 수 없다.
이전 공개 터널, Tailscale Funnel과 포트포워딩 등 다른 경로가 남아 있는지도 확인한다.
실제 주소와 인증값은 저장소, 이슈와 PR에 남기지 않는다.

GPU 접속 제한 확인은 이문영, BE 설정과 정상 분석 확인은 김민혁이 맡는다.
이 문서 변경에서는 원격 환경의 설정이나 다음 검증을 실행하지 않았다.

- 현재 tailnet에 등록된 기기와 STT 포트에 접근 가능한 범위를 확인한다.
- BE 실행 환경(컨테이너 포함)에서 상태 확인과 합성 음성 분석 POST 성공을 확인한다.
- 허용 범위 밖의 기기에서 STT 접속이 차단되고 녹음 다운로드와 GPU 추론이 시작되지 않는지 확인한다.
- 적용 환경, 정상·차단 결과와 남은 조건을 이슈에 기록한다. `/health/live` 성공만으로 분석 성공을 보고하지 않는다.
- 이슈의 ‘BE만 허용’ 조건과 현재 승인 기기 범위의 차이는 이슈에서 조정 여부를 확인한다.

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
chmod +x scripts/run_stt_server.sh
./scripts/run_stt_server.sh
```

기본 주소는 `http://127.0.0.1:8001`이며 서버 내부에서만 접속할 수 있다.

```bash
curl http://127.0.0.1:8001/health/live
```

현재 BE 연결에는 `0.0.0.0` 대신 **GPU 서버 자신의 Tailscale IP**를 지정한다.
BE의 IP를 수신 주소로 넣지 않는다. 먼저 Tailscale에 연결하고 해당 주소가 GPU 서버에 할당되어 있는지 확인한다.

```bash
SAEROK_STT_HOST="<GPU 서버의 Tailscale IP>" ./scripts/run_stt_server.sh
```

BE의 STT 기본 주소는 `http://<GPU 서버의 Tailscale IP>:8001`이다.
위 예시의 자리표시자는 서버에서 실제 값으로 바꾼다. Tailscale IP로 바인딩한 뒤의 상태 확인도
같은 주소의 `/health/live`로 요청한다. 이 설정만으로 특정 BE만 허용되는 것은 아니다.
접근 범위와 검증은 [운영 안내](#개인-gpu와-tailscale-운영)를 따른다.

## 진행 로그

기본 실행에서는 INFO 단계 로그를 표준 오류(stderr)로 출력한다. 모델 로딩과 요청별
`pipeline`, `audio_prepare`(입력 준비·WAV 검증), `inference_wait`(모델 실행 대기),
`asr`, `diarization`, `alignment`의 시작·완료·실패 및 소요 시간을 확인할 수 있다.
마지막 `status=started` 단계가 현재 처리 중인 단계이며 모델 내부 진행률은 제공하지 않는다.
`trace`는 서버가 생성한 임의 번호로, 같은 요청의 로그를 연결한다.
요청 ID, 파일명, URL, 음성·전사 내용과 예외 메시지는 진행 로그에 기록하지 않는다.
HTTP 접근 로그는 계속 비활성화한다.

```bash
SAEROK_STT_LOG_LEVEL=INFO uv run stt-server
# 실패 로그만 표시
SAEROK_STT_LOG_LEVEL=ERROR ./scripts/run_stt_server.sh
```

허용 레벨은 `DEBUG`, `INFO`, `WARNING`, `ERROR`, `CRITICAL`이다.
`SAEROK_STT_PORT`로 포트를 지정할 수 있으며 기본값은 `8001`이다.

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
