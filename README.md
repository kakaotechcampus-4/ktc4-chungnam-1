# 새록

새록은 보호자가 면회 전에 확인된 생애 정보와 지난 면회의 반응을 참고해 대화 소재를 준비하고, 면회에서 확인된 이야기를 다음 회차에 활용하도록 돕는 Android 우선 Flutter 앱이다.

## 현재 상태

| 영역 | 현재 구현 |
| --- | --- |
| FE | 합성 목 데이터를 사용하는 Flutter MVP 화면 흐름 |
| BE | FastAPI 기준 환경, 공통 오류 응답, 안전한 요청 로그와 상태 확인 API |
| AI | STT 평가 자료, VLM 후보 비교와 이미지 분석 실험 기록 |
| 공통 | 데이터 계약, 합성 목 데이터, ADR와 협업 규칙 |

실제 인증, 사용자 데이터 저장, 녹음과 STT 연동, AI 생성 파이프라인과 운영 배포는 아직 완성되지 않았다.

## 먼저 읽을 문서

1. [문서 안내](docs/README.md): 목적에 맞는 정본 찾기
2. [PM 제품 기준](docs/pm/README.md): 제품 범위와 미정 사항
3. [협업 규칙](CONTRIBUTING.md): 브랜치, 리뷰와 문서 갱신 규칙
4. 담당 영역 README: [FE](app/README.md), [BE](backend/README.md), [AI](local_ai/README.md), [평가](evals/README.md)

구현 세부 사항은 [테크스펙](docs/tech-spec.md), [데이터 계약](docs/architecture/data-contracts.md), [ADR](docs/architecture/decisions/README.md)에서 확인한다.

## 저장소 구조

| 경로 | 역할 |
| --- | --- |
| `app/` | Flutter 앱과 화면 |
| `backend/` | FastAPI 기준 환경과 처리 파이프라인 |
| `local_ai/` | STT, VLM과 생성 모델 검증 |
| `evals/` | 평가 자료, 기대 결과와 평가 코드 |
| `docs/pm/` | 제품 범위와 PM 결정 |
| `docs/architecture/` | 공통 계약과 기술 결정 |
| `docs/legal/` | 개인정보와 동의 검토 |

## 개발 시작

1. `develop`을 최신 상태로 갱신한다.
2. 루트 `AGENTS.md` 또는 `CLAUDE.md`와 담당 영역의 같은 지침을 읽는다.
3. 담당 영역 README에서 검증된 실행 명령을 확인한다.
4. 최신 `develop`에서 작업 브랜치를 만들고 구현 및 검증 후 `develop` 대상 PR을 올린다.

실제 사용자 자료, 마스킹한 실제 자료, 시크릿, 로컬 DB와 모델 파일은 저장소에 올리지 않는다. 상세 기준은 루트 지침과 [협업 규칙](CONTRIBUTING.md)을 따른다.
