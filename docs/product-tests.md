# 제품 테스트 CI

`.github/workflows/product-tests.yml`은 develop과 main 대상 PR, 수동 실행에서
Flutter 정적 검사와 테스트, Python 정적 검사, BE 테스트, AI 단위 테스트, STT 계약과 파이프라인 테스트를 각각 실행한다.
기존 운영진의 멘토 배정, PR 형식 확인과 디스코드 알림 workflow는 수정하지 않는다.

[배포 후보 빌드](deploy-workflows.md)(`release-build.yml`)는 `workflow_call`로 이 workflow를 불러 배포 후보 커밋에서 같은 검사를 다시 실행한다.

## 범위와 실행

| 작업 위치 | 명령 | 검사 범위 |
| --- | --- | --- |
| `app/` | `flutter pub get --enforce-lockfile`, `flutter analyze`, `flutter test` | 고정 의존성, Dart 정적 검사와 기존 앱 테스트 |
| `backend/` | `uv sync --locked`, `uv run --locked pytest -ra` | API, 서비스, migration과 실제 PostgreSQL 저장 검사 |
| `backend/` | 테스트 뒤 `app.openapi()`를 `openapi.json`으로 저장해 `openapi-schema` 결과물로 14일 보관 | 서버가 실제로 여는 API 경로와 요청, 응답 형식. 손으로 쓴 명세와 경로 목록이 같은지는 테스트(`test_api_spec_routes.py`)가 따로 본다 |
| `backend/` | `uv run --locked --with mypy==2.2.0 mypy --follow-imports=silent --ignore-missing-imports app` | BE 코드 전체의 타입 검사. 첫 결과로 오류 수를 확인하기 전까지 실패해도 CI를 막지 않는다(`continue-on-error`). 그 뒤 범위와 막을지를 정한다 |
| `ai/` | `uv sync --locked`, `uv run --locked pytest -ra` | 카드, 리포트와 변경 제안의 단위 테스트 및 카드 자료 조회 DB 검사 |
| `backend/` + `app/` | `uv run --locked python scripts/run_app_server_e2e.py --flutter <flutter>` | 앱과 실제 BE의 E2E. 앱의 실제 API 코드로 실제 BE, 카드와 음성 worker, PostgreSQL을 잇고 구글 로그인, 모델, S3, STT만 합성으로 바꾼다. 가입부터 푸시 기기 등록과 해제, 두 번째 면회와 탈퇴까지([FE README](../app/README.md#앱과-실제-서버-e2e)). 화면, 실제 마이크와 기기, 실제 푸시 발송과 수신, 사진 분석 worker는 보지 않는다 |
| `stt-server/` | `uv sync --locked`, `PYTHONPATH=src uv run --locked python -m unittest discover -s tests -v` | 입력 검증, 화자 정렬, 오류 처리와 합성 응답을 사용하는 파이프라인 검사 |
| 저장소 루트 | `uvx ruff@0.17.3 check --select E9,F63,F7,F82 backend ai stt-server` | Python 문법 오류, 정의되지 않은 이름, 잘못된 비교 같은 실행 전에 알 수 있는 오류. 형식과 스타일 규칙은 아직 넣지 않음 |

Flutter 3.44.8, Python 3.12와 uv 0.11.26을 사용한다. Python과 Dart 의존성은
저장소의 lockfile을 따른다. action은 확인한 커밋에 고정했다.
`setup-uv` v6는 annotated tag 객체가 아닌 실제 커밋
`d0cc045d04ccac9d8b7881df0226f9e82c39688e`를 참조한다.

STT 테스트는 CPU 실행기에서 모델 호출을 대역으로 처리한다. 모델 다운로드를 막도록
`HF_HUB_OFFLINE=1`을 지정한다. 현재 테스트가 실제 pyannote 결과 타입을 사용하므로
프로젝트 lockfile의 PyTorch와 pyannote 의존성도 설치하며 TorchCodec 로딩용 FFmpeg와
Python 공유 라이브러리를 설치한다. 단위 검사 전에 160개 표본의 합성 무음 WAV를
TorchCodec으로 직접 읽고 채널 수, 표본 수와 16kHz를 확인한다. import 경고만 남긴 채
오디오 디코딩이 고장난 환경이 통과하지 않도록 하는 검사다. 실제 ASR이나 화자 분리
모델을 호출하지 않으며 무음에 리포트를 생성하지 않는다.
의존성 설치 용량과 시간이 크지만 운영 모델 파일이나 GPU, Hugging Face 토큰은 필요하지 않다.
검사 통과가 Whisper 인식 정확도나 실제 화자 분리 품질을 의미하지 않는다.

BE 작업은 GitHub 실행기 안에 PostgreSQL 17을 띄운다. 공개된 예시 비밀번호는
그 일회성 테스트 DB에만 쓰며 팀 서버 비밀번호가 아니다. 기존 fixture가 테스트마다
별도 DB를 만들고 제거한다. 운영 DB, S3, Google 계정과 ML API 키는 사용하지 않는다.
로컬에서 BE 전체 검사를 할 때도 `SAEROK_TEST_DATABASE_URL`은 생성과 삭제가 허용된
전용 테스트 PostgreSQL만 가리켜야 한다. 값이 없으면 DB 검사가 건너뛰어지므로
그 실행을 DB 통합 검사 통과로 기록하지 않는다.

AI 작업에도 별도의 PostgreSQL 서비스를 둔다. `TOPIC_REC_TEST_DATABASE_URL`은
이 서비스의 `saelog_ai_ci`를 가리킨다. AI fixture는 해당 DB에 `init.sql`을 적용하며
기존 테이블을 지우므로 운영 DB나 개발 중인 DB를 연결하면 안 된다. CI의 두 DB는
서로 다른 실행기에 있으며 실제 모델은 호출하지 않는다.

이 CI는 실제 모델 품질, GPU 실행, Android 마이크와 화면 잠금, Play 서명 빌드,
실제 서버 배포나 다음 회차까지의 실기기 성공을 보장하지 않는다. 해당 검사는
별도 결과로 남긴다. 실패한 검사나 필요한 테스트를 지워 통과시키지 않는다.

## 권한과 적용 전 확인

- PR의 코드는 읽기 권한으로 실행한다. `pull_request_target`과 저장소 시크릿을 사용하지 않는다.
- checkout 인증정보를 저장하지 않으며 배포, 댓글, PR 수정 단계가 없다.
- 같은 PR의 새 실행이 시작되면 이전 테스트 실행만 취소한다. 운영 worker에는 영향이 없다.
- GitHub에 게시하기 전에는 로컬 명령 실행과 workflow 검사 결과를 기록한다.
  실제 Actions 실행 성공은 게시 후 별도로 확인해야 한다.
- 필수 상태 검사 지정은 별도의 저장소 설정 변경이다. 이 파일 추가만으로
  브랜치 보호나 자동 병합, 자동 배포를 켜지 않는다.
