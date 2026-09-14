# ADR 운영

ADR은 앱, AI와 BE의 구조를 바꾸는 기술 결정에 사용한다. 담당 README에는 현재 선택을 기록하고, ADR에는 선택 이유와 영향을 기록한다.

## 현재 결정

| 문서 | 상태 | 결정 |
| --- | --- | --- |
| [ADR-001](ADR-001-consent-and-temporary-processing.md) | accepted | 동의 구조와 원본 자료의 최대 24시간 임시 처리 |
| [ADR-002](ADR-002-android-application-id.md) | accepted | Android Application ID는 `com.saelog.app` |
| [ADR-005](ADR-005-flutter-state-management-and-routing.md) | accepted | Riverpod 상태 관리와 go_router 화면 이동 |
| [ADR-006](ADR-006-server-side-ai-processing.md) | accepted | STT와 VLM은 온프레미스 GPU 1대에서 처리 |

accepted는 결정이 확정됐다는 뜻이며 구현이나 배포 완료를 뜻하지 않는다.

<details>
<summary>대체된 제안 2건</summary>

| 문서 | 상태 | 대체 관계 |
| --- | --- | --- |
| [ADR-003](ADR-003-parallel-stt-validation.md) | superseded | 온디바이스 STT 병렬 검증, ADR-006으로 대체 |
| [ADR-004](ADR-004-python-fastapi-reference-environment.md) | superseded | FastAPI와 온디바이스 병렬 검증, ADR-006으로 대체. 로컬 검증 원칙 유지 |

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
