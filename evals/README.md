# 평가 영역

검토 담당: 이문영, 이인성

상태: 평가 코드가 추가되기 전의 공통 구조와 원칙

## 평가 대상

- 이미지 분석 후보의 사실성
- STT 정확도와 처리 실패
- 화자 전환과 화자 식별
- 카드 안전성과 프로필 적합성
- 최근 기억 확인형 질문 차단
- 리포트 관찰값과 보호자 평가의 일치
- 확인되지 않은 이야기 생성 방지

## 예정 구조

    evals/
    ├─ cases/
    ├─ fixtures/
    ├─ expected/
    ├─ scripts/
    └─ results/
       ├─ baseline/
       └─ local/

- `cases/`: 테스트 목적, 입력과 기대 결과 경로
- `fixtures/`: 합성 자료 또는 사용 권한이 확인된 자료
- `expected/`: 사람이 검토한 기대 결과
- `scripts/`: 평가 실행과 비교 코드
- `results/baseline/`: 팀이 합의한 비교 기준
- `results/local/`: 개인 결과, GitHub 반입 금지

## 자료 원칙

- 실제 사용자 자료와 마스킹한 실제 자료를 사용하지 않음
- 합성 자료 또는 재배포 권한을 확인한 자료만 사용
- 자료의 출처, 라이선스와 생성 조건 기록
- 실제 이름, 시설명, 전사문과 음성을 테스트 고정값으로 사용하지 않음

## 케이스 최소 필드

```json
{
  "schemaVersion": 1,
  "caseId": "card-safety-001",
  "area": "cardGeneration",
  "description": "최근 기억 확인형 질문을 차단한다",
  "inputRef": "fixtures/profiles/card-safety-001.json",
  "expectedRef": "expected/card-safety-001.json",
  "tags": ["safety", "recentMemory"]
}
```

## 실행과 통과 기준

첫 평가 스크립트가 병합될 때 실제 실행 명령, 결과 해석과 통과 기준을 함께 기록한다. 동작하지 않는 명령과 검증하지 않은 기준은 적지 않는다.
