# 이미지 분석 실험 안내

현재 결정은 [ADR-006](../../../docs/architecture/decisions/ADR-006-server-side-ai-processing.md)에서 확인한다. VLM은 온프레미스 GPU 1대에서 처리하며, 모델과 출력 형식은 아직 비교 중이다.

## 요약부터 읽기

| 확인할 내용 | 요약 문서 | 전체 근거 |
| --- | --- | --- |
| 초기 로컬 모델 후보의 품질, 속도와 한계 | [VLM 후보 비교](vlm-benchmark-report.md) | [상세 분석과 17장 전체 출력](vlm-benchmark-full-results.md) |
| 같은 17장에 대한 Haiku와 Luna 키워드 비교 | [Haiku와 Luna 비교](haiku-luna-low-benchmark.md) | 보고서의 이미지별 비교표 |
| Luna low와 medium의 문맥형 출력 비교 | [Luna 문맥형 비교](luna-low-medium-context-benchmark.md) | [이미지별 전체 출력](luna-low-medium-context-full-results.md) |
| 7개 모델 9개 API 조건 비교 | [API VLM 비교](vlm-api-benchmark-report.md) | [306건 전체 확정 데이터 (JSONL)](vlm-api-full-results.jsonl) |
| 메타데이터 확보 범위와 신뢰 한계 | [메타데이터 추출 보고서](metadata-extraction-report.md) | [추출 JSON](metadata-extraction-results.json) |
| 평가 이미지의 출처와 라이선스 | [출처 목록](target-image/SOURCES.md) | 해당 목록에 연결된 공개 원문 |

초기 로컬 모델과 후속 CLI 실험은 실행 환경이 다르다. 수치를 비교할 때 각 보고서의 조건과 한계를 함께 확인한다.

## 결과를 사용할 때

- 초기 온디바이스 후보 평가는 과거 실험 기록이다. 현재 실행 위치를 다시 정하는 문서로 사용하지 않는다.
- 태그, description과 두 방식의 결합 중 제품에 쓸 형식은 추가 비교 후 정한다.
- 사진 메타데이터는 스캔, 재촬영, 편집과 전송 과정에서 원래 사건 정보와 달라질 수 있으므로 보조 입력으로만 사용한다.
- 메타데이터와 모델 출력은 보호자 확인 전 프로필과 스토리에 확정 사실로 반영하지 않는다.

## 자료 보관

- 요약에는 실행 조건, 핵심 수치, 실패 유형과 한계를 남기고 이미지별 긴 출력은 근거 문서에서 확인한다.
- 기존 공개 평가 이미지는 유지한다. 자료를 추가할 때는 사용과 재배포 권한을 확인하고 출처와 라이선스를 기록한다.
- 실제 사용자 사진, 음성, 프로필과 회차 기록은 저장소에 넣지 않는다.
- 제품 결정은 ADR과 [AI 안내](../../README.md), 실험 결과는 이 폴더에서 관리한다.
