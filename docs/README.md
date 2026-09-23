# 문서 안내

이 문서는 새록 저장소의 문서 지도다. 같은 내용이 여러 곳에 있을 때 아래 정본을 우선한다.

## 목적별 문서

| 알고 싶은 내용 | 먼저 읽을 문서 | 상세 문서 |
| --- | --- | --- |
| 제품 대상, 범위와 미정 사항 | [PM 제품 기준](pm/README.md) | [테크스펙](tech-spec.md) |
| 진행 중인 작업과 주간 운영 | [GitHub 이슈](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/issues) | [주간 운영](pm/weekly-operations.md), [12주 학습 목표](pm/12-week-team-goals.md) |
| Flutter 구현과 실행 | [FE README](../app/README.md) | [환경 설정](../app/SETUP.md), [디자인 기준](../app/DESIGN.md) |
| FastAPI 구현과 실행 | [BE README](../backend/README.md) | 코드와 테스트 |
| STT와 이미지 분석 | [AI README](../local_ai/README.md) | [이미지 분석 실험](../local_ai/docs/image_tagging/README.md) |
| 평가 자료와 실행 상태 | [평가 README](../evals/README.md) | `evals/cases/`, `evals/expected/` |
| 공통 JSON 형식 | [데이터 계약](architecture/data-contracts.md) | [합성 목 데이터](architecture/mock/README.md) |
| 기술 결정과 변경 이유 | [ADR 목록](architecture/decisions/README.md) | 개별 ADR |
| 개인정보와 동의 | [법률 검토](legal/README.md) | [동의안](legal/consent-draft.md), [기능 대응표](legal/consent-mapping.md) |
| 이슈 작성과 Git, PR 절차 | [협업 규칙](../CONTRIBUTING.md) | PR 템플릿 |
| 발표 준비 | [발표 예상 질문](pm/presentation-qna.md) | 과거 준비 자료, 현재 구현 정본 아님 |

## 문서의 역할

| 종류 | 포함하는 내용 | 포함하지 않는 내용 |
| --- | --- | --- |
| README | 현재 상태, 확정된 기준, 실행 방법과 상세 링크 | 긴 실험 출력과 과거 논의 전문 |
| 테크스펙 | 제품과 기술의 현재 청사진 | 객체별 전체 JSON 예시와 실험 원문 |
| 데이터 계약 | 객체, 필드, 상태와 변경 규칙 | 제품 소개와 실험 결과 |
| ADR | 하나의 기술 결정, 이유와 대안 | 계속 바뀌는 작업 목록 |
| 실험 보고서 | 입력, 조건, 결과, 한계와 재현 정보 | 제품의 최종 결정인 것처럼 쓴 권고 |
| 이슈 | 짧은 작업 목표, 담당, 완료 조건과 결과 링크 | 긴 설계 설명과 실험 원문 |
| 주간 보고 | 사용자가 실제로 할 수 있는 흐름, 완료와 이월 및 막힌 작업의 이슈와 PR 링크 | 미완료 작업을 복사한 새 주간 작업 목록 |

## 갱신 원칙

- 같은 규칙의 상세 설명은 정본 한 곳에만 쓰고 다른 문서는 링크한다.
- 문서로 설명을 옮겨도 미완료 작업의 추적 위치는 이슈에 남긴다. 작성과 완료 처리는 [협업 규칙](../CONTRIBUTING.md)을 따른다.
- 제품 범위가 바뀌면 PM 문서, 구조가 바뀌면 영역 README와 ADR, JSON이 바뀌면 데이터 계약을 갱신한다.
- 과거 ADR과 실험 결과는 삭제하지 않고 대체 상태 또는 근거 문서로 남긴다.
- 회의 녹화, 전사와 로컬 회의록은 저장소에 올리지 않는다.
