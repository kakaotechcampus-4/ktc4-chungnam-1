# STT 파이프라인 설계

상태: S3·로컬 입력, ASR, 화자 분리와 결과 결합 흐름 구현

## 작업 맥락

백엔드와 별도로 온프레미스 RTX 3060 환경에서 AI 로직을 실행하는 서버를 구축한다. 현재는 단일
요청과 GPU 한 장만 고려하며, 비동기 작업과 작업 큐는 이후에 설계한다.

기본 흐름은 다음과 같다.

```text
음성 입력
→ ASR 전사
→ 화자 분리
→ 전사 구간과 화자 구간 매칭
→ 최종 결과 생성
```

ASR 보정은 현재 범위에 포함하지 않으며 결합 흐름 검증 뒤 추가한다.

## 음성 입력

음성 획득은 모델 실행과 분리된 Provider가 담당한다.

```text
S3AudioProvider ────┐
                    ├─ WAV 경로 → ASR → 화자 분리 → 결과 결합
LocalAudioProvider ─┘
```

운영 입력은 S3 Presigned GET URL에서 임시 파일로 스트리밍 다운로드한다. 크기와 SHA-256을 확인하고
WAV/PCM 16-bit/16kHz/mono 규격을 검증한 뒤 처리하며, 임시 파일은 요청 종료 시 삭제한다.

로컬 개발은 다음 폴더의 KCSC WAV 파일을 그대로 사용한다.

```text
docs/stt-mobile-benchmark/data/kcsc/WAV
```

로컬 요청은 운영 요청과 같은 API를 사용하고 `audioSource.type`만 `localFile`로 바꾼다.

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

운영 환경은 로컬 입력을 비활성화하며 로컬 Provider는 고정 폴더 밖의 경로를 거부한다.

## ASR과 화자 구간 결합

ASR 단어와 pyannote의 `exclusive_speaker_diarization` 구간 사이의 겹치는 시간을 계산한다. 가장
오래 겹치는 구간의 화자를 단어에 배정하며, 최대 겹침 시간이 서로 다른 화자 사이에서 같거나
겹치는 구간이 없으면 화자를 배정하지 않는다. 단어 타임스탬프가 없는 ASR 구간은 구간 전체를
fallback 단위로 사용한다.

최종 결과는 diarization 발화 구간 단위로 그룹화한다. 같은 화자 라벨이 나중에 다시 등장해도
서로 다른 diarization 발화 구간이면 합치지 않는다. 일반 `speaker_diarization` 결과도 별도로
보존하여 이후 겹말 판정에 사용할 수 있게 한다.

결합 코드는 모델 실행과 분리된 순수 함수이며 저장된 JSON fixture만으로 테스트한다.

## 다음 구현 순서

1. 허가된 동일 음성에서 생성한 실제 ASR·diarization 출력 fixture를 함께 저장한다.
2. 실제 출력 fixture의 예상 최종 결과를 사람 검토로 확정한다.
3. 로그 확률을 활용한 전사 보정 단계를 ASR과 정렬 사이에 연결한다.
4. 정상, 저신뢰도와 실패 결과 계약을 확정한다.
5. 백엔드와 실제 S3 환경에서 만료, 타임아웃과 재시도 정책을 통합 검증한다.
