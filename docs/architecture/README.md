# 아키텍처 기준

## 현재 방향

    Flutter 앱
    → 단말 로컬 저장
    → 동의 범위의 온프레미스 GPU 서버 추론
    → 카드 및 리포트 처리
    → 보호자 확인
    → 프로필과 이야기 반영

모델 추론은 AI 담당자의 자택 GPU를 활용한 온프레미스 서버에서 수행한다([ADR-006](decisions/ADR-006-on-premise-gpu-inference.md)). GPU 서버 임대와 외부 LLM 서비스 도입은 미정이다. 녹음과 이미지 원본은 동의한 기능에 필요한 경우 암호화하여 관리하기로 한다.

## 역할 경계

| 영역 | 책임 |
| --- | --- |
| FE | Flutter 화면, 녹음 상태 화면, 사용자 권한, 앱 생명주기와 합의된 인터페이스 연동 |
| AI | 녹음 라이브러리, 음성 형식, 모델 선택과 실행 환경, 품질 기준, GPU 서버 구성·배포·운영 |
| BE | 단말 데이터 구조와 로컬 DB, 앱·서버 연동, 처리 파이프라인과 데이터 경계 |
| QA | 평가 자료, 기준 정답, 평가 방식과 통과 기준 |

공통 데이터 계약은 FE, AI와 BE가 공동 관리한다. 하위 호환성을 깨는 변경은 ADR과 관련 README 갱신이 필요하다.

## 문서

- 통합 테크스펙: [tech-spec.md](../tech-spec.md)
- 공통 형식: [data-contracts.md](data-contracts.md)
- 기술 결정: [decisions](decisions/README.md)
- 개인정보와 법률: [legal](../legal/README.md)
