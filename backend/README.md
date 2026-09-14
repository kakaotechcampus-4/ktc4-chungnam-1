# BE 영역

담당 리더: 김민혁. 현재 코드는 Python 3.12와 FastAPI의 개발용 골격이며 실제 STT, VLM, 인증과 저장 API는 아직 연결되지 않았다.

MVP의 STT와 VLM은 [ADR-006](../docs/architecture/decisions/ADR-006-server-side-ai-processing.md)에 따라 온프레미스 GPU 1대에서 처리한다. 장비와 운영 방식은 미정이며, 이 FastAPI 골격을 운영 배포 구조로 확정한 것은 아니다.

## 실행과 테스트

저장소 루트에서 최초 설정:

```powershell
cd backend
uv python install 3.12
uv sync
uv run python --version
```

이후 명령은 `backend/`에서 실행한다. 의존성과 가상 환경은 `uv`, 테스트는 `pytest`로 관리한다.

```powershell
uv run uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload --no-access-log
```

Android 에뮬레이터 또는 허가된 개발 단말과 합성 데이터로 연동할 때만 외부 인터페이스에 바인딩한다.

```powershell
uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload --no-access-log
```

```powershell
uv run pytest
```

| 확인 항목 | 위치 / 현재 범위 |
| --- | --- |
| 생존 확인 | `GET /health/live` |
| 준비 상태 | `GET /health/ready`. 외부 의존성이 없는 골격의 상태만 확인 |
| API 문서 | 실행 후 `http://127.0.0.1:8000/docs` |
| 오류 테스트 | [test_errors.py](tests/test_errors.py)의 404, 422, 503 응답 |
| 요청 로그 | 경로 템플릿만 기록하며 본문과 전사문을 기록하지 않음 |

처리되지 않은 500 예외에서는 요청 완료 로그와 `X-Request-ID` 응답 헤더가 누락되는 보완 작업이 남아 있다. 모델과 저장소가 연결되면 readiness에도 실제 의존성 점검을 추가한다.

## 담당과 다음 결정

| 범위 | BE 작업 / 함께 정할 내용 |
| --- | --- |
| 모델 실행 | AI와 입력 형식, 모델 로딩, 자원 해제, STT 및 화자 처리 파이프라인 검토 |
| 앱 연동 | [공통 데이터 계약](../docs/architecture/data-contracts.md)의 입력 검증, 응답과 상태 전달 |
| 작업 처리 | 타임아웃, 재시도 상한, 취소, 장애 복구와 수동 전환 |
| 단말 저장 | DB, 스키마, 암호화와 마이그레이션 |
| 운영 | PM, AI와 GPU 장비 및 운영 방식 결정. 모델 파일 배포와 무결성 확인 |
| 데이터 이동 | 업로드 허용 필드, 인증, 마스킹, 임시 파일과 로그의 삭제 확인 |
| 외부 서비스 | 외부 LLM 중계 필요 여부와 개인정보 처리 조건 확인 |

모델과 품질 기준은 AI와 공동 검토한다. 새 구조 결정은 입력과 출력, 저장 여부, 실패 조건, 보안 영향, 검증 방법과 재검토 조건을 ADR에 기록한다.

## 데이터 처리 기준

    앱에서 녹음 및 기능 동의 확인
    → 암호화 전송과 서버 임시 처리
    → STT 또는 VLM 결과 반환
    → 원본 즉시 삭제와 삭제 결과 확인
    → 보호자 검토
    → 단말 저장

이 흐름은 구현해야 할 기준이다. 프로필, 전사문과 회차 기록의 기본 저장 위치는 사용자 단말이며 원본의 서버 보관은 처리 완료 후 즉시 삭제, 최대 24시간이다. 실제 사용자 자료와 마스킹한 실제 자료는 개발 골격의 테스트에 사용하지 않는다.

직접 식별정보와 허용 목록 밖의 원본은 외부 AI로 보내지 않는다. 데이터 경로 변경 전 [법률 문서](../docs/legal/README.md), [동의 및 임시 처리 ADR](../docs/architecture/decisions/ADR-001-consent-and-temporary-processing.md)과 데이터 흐름을 갱신한다. 외부 업체의 이름, 국가, 목적, 항목, 보유기간과 자체 학습 여부가 정해지기 전에는 실제 사용자 자료로 호출하지 않는다.
