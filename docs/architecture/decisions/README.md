# ADR 운영

ADR은 앱, AI와 BE의 구조를 바꾸는 기술 결정에 사용한다. 담당 README에는 현재 선택을 기록하고, ADR에는 선택 이유와 영향을 기록한다.

## 현재 결정

| 문서 | 상태 | 결정 |
| --- | --- | --- |
| [ADR-001](ADR-001-consent-and-temporary-processing.md) | accepted, 사진 보관과 AI 분석의 가입 시 선택 동의 및 계정별 저장은 2026-10-14 PM 확정 | 가입 화면에서 두 동의를 각각 받고 기존 계정 이력에 저장. 유효한 동의는 반복 요청하지 않으며 미동의자는 기능 사용 시 요청. 피보호자별 확인과 휴대폰 접근은 별도. 구현과 삭제 검증은 후속 작업 |
| [ADR-005](ADR-005-flutter-state-management-and-routing.md) | accepted | Riverpod 상태 관리와 go_router 화면 이동 |
| [ADR-006](ADR-006-server-side-ai-processing.md) | accepted, 후속 방향 정정 | STT는 GPU 서버, 사진 설명과 카드 및 리포트는 ML API 활용. 9월 14일 일괄 GPU 결정은 과거 기록으로 구분. 실제 사용자 자료 전송 조건 별도 확인 |
| [ADR-007](ADR-007-google-social-login.md) | proposed | 구글 로그인과 백엔드 ID 토큰 직접 검증, ADR-006의 인증과 계정 저장 부분을 구체화. 저장 항목 등 공동 검토 필요 |
| [ADR-008](ADR-008-stt-pipeline.md) | proposed | 면회 WAV 접수 후 PostgreSQL 작업 상태와 worker를 사용하는 비동기 STT·리포트 처리. 재시도와 리포트 계약 공동 검토 필요 |
| [ADR-009](ADR-009-android-application-id-saerok.md) | accepted | Android Application ID와 Kotlin 패키지는 `app.saerok.android`. ADR-002를 대체 |

accepted는 결정이 확정됐다는 뜻이며 구현이나 배포 완료를 뜻하지 않는다. ADR-007의 `proposed` 표기는 구글 로그인 방향에 대한 PM 동의를 되돌리는 뜻이 아니며 계정 저장 항목 등 남은 검토안을 확정하지 않기 위한 표시다.

서버 중심 데이터 관리 보완은 [PR #37](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/37), 로그인 설계와 계정 계약은 [PR #38](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/38)에서 다룬다. 두 변경은 ADR-006과 ADR-007을 함께 읽으며 확인한다.

<details>
<summary>대체된 결정 3건</summary>

| 문서 | 상태 | 대체 관계 |
| --- | --- | --- |
| [ADR-002](ADR-002-android-application-id.md) | superseded | Android Application ID `com.saelog.app`, ADR-009로 대체 |
| [ADR-003](ADR-003-parallel-stt-validation.md) | superseded | 온디바이스 STT 병렬 검증과 단말 우선 저장, ADR-006으로 대체 |
| [ADR-004](ADR-004-python-fastapi-reference-environment.md) | superseded | 온디바이스 병렬 검증과 단말 우선 저장, ADR-006으로 대체. 로컬 FastAPI 검증 원칙 유지 |

</details>

## 파일 이름

    ADR-001-decision-title.md

## 상태

- `proposed`: 검토 중
- `accepted`: 결정 확정
- `rejected`: 채택하지 않음
- `superseded`: 다른 ADR로 대체됨

## 템플릿

<details>
<summary>새 ADR을 작성할 때 펼치기</summary>

```md
# ADR-번호: 결정 제목

상태:
담당:
결정일:
관련 Issue:

## 배경

## 결정

## 검토한 대안

## 영향

## 검증

## 재검토 조건
```

</details>

## ADR이 필요한 변경

- 로컬 저장과 서버 처리 경계
- Flutter와 로컬 AI 연결 구조
- 외부 LLM 또는 외부 STT 도입
- 원본 자료 처리 위치
- 공통 데이터 계약의 하위 호환성을 깨는 변경
- 별도 백엔드 배포 여부
- 인증과 암호화 구조

화면 문구, 일반 오류 수정, 테스트 추가와 기존 구조 안의 소규모 변경에는 ADR을 만들지 않는다.

기존 결정을 바꾸면 이전 ADR을 삭제하지 않고 `superseded`로 보존한다.

<a id="현재-adr"></a>
현재 목록은 위 [현재 결정](#현재-결정)에 모았다.
