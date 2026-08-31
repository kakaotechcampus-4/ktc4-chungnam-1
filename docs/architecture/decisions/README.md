# ADR 운영

ADR은 앱, AI와 BE의 구조를 바꾸는 기술 결정에 사용한다. 담당 README에는 현재 선택을 기록하고, ADR에는 선택 이유와 영향을 기록한다.

## 파일 이름

    ADR-001-decision-title.md

## 상태

- `proposed`
- `accepted`
- `rejected`
- `superseded`

## 템플릿

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

## 현재 ADR

| 문서 | 상태 | 결정 |
| --- | --- | --- |
| [ADR-001](ADR-001-consent-and-temporary-processing.md) | accepted | 동의 구조와 원본 자료의 최대 24시간 서버 임시 처리 경계 |
| [ADR-002](ADR-002-android-application-id.md) | accepted | Android Application ID를 `com.saelog.app`으로 통일 |
