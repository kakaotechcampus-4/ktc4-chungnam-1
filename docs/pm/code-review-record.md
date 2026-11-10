# 주요 PR 코드 리뷰 기록

GitHub PR에 남은 코드 리뷰 가운데 주요 기록을 모았다. 멘토 리뷰는 매주 `develop → main` PR에서, 팀 리뷰는 `develop` 대상 PR에서 했다. 리뷰 규칙은 [협업 규칙](../../CONTRIBUTING.md)의 "팀 내부 PR"과 "멘토 리뷰 PR"에 있다. 집계 기준 시각은 2026-11-11 KST다.

## 요약

- 멘토 리뷰 PR 8건이 모두 수정 요청 1회 뒤 승인으로 끝났다. 멘토 리뷰는 17건(수정 요청 8, 승인 9)이다.
- 멘토 지적은 주로 실패 경로(작업이 끝나지 않는 경우, 다시 보낼 수 없는 경우, 예외에서 빠지는 로그)와 PR 범위에 관한 것이었다. 지적을 받은 다음 주 PR에서 처리 결과를 답하고 재리뷰를 요청했다.
- 팀 내부 리뷰가 GitHub 리뷰 기능으로 남은 PR은 develop 병합 PR 210건 중 17건이다. 나머지 검토는 PR 대화 댓글과 디스코드에서 했다.

## 멘토 리뷰

| PR | 내용 | 수정 요청에서 짚은 것 | 승인 |
| --- | --- | --- | --- |
| [#17](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/17) | MVP 화면 흐름과 공통 개발 기반 | repository에 쓰기 경로가 없음, 계약에 없는 값이 정상값으로 바뀜, 처리 못 한 예외에서 요청 로그와 `X-Request-ID`가 빠짐, Flutter 검사 결과 첨부 ([9/10 리뷰](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/17#pullrequestreview-5162001905)) | 9/15. 미평가 카드를 `neutral`로 쓰는 규칙이 계약에 없음, 500 오류 traceback 기록 ([리뷰](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/17#pullrequestreview-5204369135)) |
| [#48](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/48) | 구글 로그인과 온프레미스 GPU 결정 | 알림 동의가 FE는 선택, BE는 필수로 어긋남, 로그인 구현을 main에 올릴 근거, 모르는 `kid`에 JWKS를 두 번 받음 ([9/17 리뷰](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/48#pullrequestreview-5230178814)) | 9/19 ([리뷰](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/48#pullrequestreview-5255629701)) |
| [#70](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/70) | 구글 로그인 연동, STT 요청 전달 API, 협업 규칙 개선 | STT 요청의 시간 초과와 연결 실패 테스트가 없음 ([9/23 리뷰](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/70#pullrequestreview-5291610275)) | 9/26. PR을 완료 가능한 작업 단위로 나누는 연습을 권함 ([리뷰](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/70#pullrequestreview-5325497124)) |
| [#81](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/81) | 면회 녹음, 비동기 음성 분석, 보호자 위로 화면 | worker가 죽으면 그 면회가 끝나지 않음, 실패한 면회를 다시 보낼 방법이 없음 ([10/1 리뷰](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/81#pullrequestreview-5373721907)) | 10/3. AI 서버의 입력 오류가 모두 500, import 시점 모델 적재 ([리뷰](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/81#pullrequestreview-5400173365)) |
| [#101](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/101) | 다중 프로필 화면, BE 공통 구조, 개발 서버 배포 준비 | 남은 흐름의 연결 계획, 작업 임대 만료를 넣으며 생긴 결정 ([10/8 리뷰](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/101#pullrequestreview-5452739121)) | 10/10. 복구 범위와 순서, 자동 재시도 1회, 보관 기준을 별도 PR로 나눈 판단이 적절하다고 봄 ([리뷰](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/101#pullrequestreview-5479016436)) |
| [#122](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/122) | 프로필, 카드, 면회 API와 보호자 확인 화면 통합 | 10/14 통합 계획과 실제 PR의 차이, 카드 생성이 "만드는 중"에서 끝나지 않는 경로 ([10/15 리뷰](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/122#pullrequestreview-5529340294)) | 10/19 ([리뷰](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/122#pullrequestreview-5565966469)). 승인 시점 코드만 #168로 main에 반영 |
| [#169](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/169) | 사진과 일대기 서버 연결, STT 운영 보완 | STT 서버가 공개 주소로 열렸는데 호출자를 확인하지 않음 ([10/30 리뷰](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/169#pullrequestreview-5708083570)) | 10/31. STT 접근 제한(#172)과 worker 종료 유예(#173) 후속 확인 ([리뷰](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/169#pullrequestreview-5721678791)) |
| [#230](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/230) | 카드 재생성, 분석 복구, AI 품질과 운영, 자동 검사 보완 | 화자를 확인하지 못한 회차는 리포트를 못 받고 다시 요청할 방법이 없음, 리포트 의료 표현 검사가 인용문까지 잡을 수 있음 ([11/5 리뷰](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/230#pullrequestreview-5778396716)) | 11/7 ([리뷰](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/230#pullrequestreview-5812767149)) |

### 멘토 리뷰 뒤 바꾼 것

| 지적 | 바꾼 것 |
| --- | --- |
| #81 worker가 죽으면 면회가 끝나지 않고, 실패한 면회를 다시 보낼 수 없음 | 작업 임대 만료와 재시도, 분석 실패 후 다시 요청을 추가(#101 이후) |
| #122 여러 생성 작업을 한 PR에 담고 순서를 전제로 쌓은 구조 | PR 범위 규칙 "독립적으로 검증할 작업 단위"를 추가([#127](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/127)) |
| #169 STT 서버 호출자 확인 없음 | 접근 제한을 이슈 [#172](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/issues/172)로 등록해 추적 |
| #230 화자 미확인 회차의 리포트 | 화자 정보가 부족해도 리포트와 제안을 만들도록 변경([#251](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/251), 11/6), 앱 여정 테스트와 문서 갱신([#253](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/253)) |

## 팀 내부 리뷰

리뷰 기능으로 의견을 주고받은 주요 PR이다. 승인 리뷰만 남은 PR은 확인한 내용을 적었다.

| PR | 내용 | 리뷰에서 다룬 것 | 결과 |
| --- | --- | --- | --- |
| [#33](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/33) | 이미지 분석 모델 비교 | 비교에 쓴 프롬프트 원문이 해시로만 있음 | 프롬프트 원문과 JSON Schema를 추가 |
| [#34](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/34) | 모바일 STT 벤치마크 | 출처와 재배포 권한이 확인되지 않은 녹음 파일이 들어감 | 수정 요청 뒤 녹음, 정답 전사문, 대형 결과를 빼고 승인 |
| [#36](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/36), [#37](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/37) | 온프레미스 GPU 처리 결정(ADR-006) | 자체 GPU 장비 사용 제안, STT 모델과 화자 분리 방식 | #36은 상태 문구 정정, #37은 장비와 모델 선택을 논의 |
| [#84](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/84) | DB 스키마 제안 | 주제 추천 방향(`up`, `down`)과 보호자 선택의 구분 | 리뷰 댓글로 필드 의미를 정리 |
| [#97](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/97) | 주제 카드 생성과 다음 면회 반영 흐름 | 사진 설명 사용 방식, 분류 6개의 용도, 거절 후보 복구, 이야기 시기 정보, 카드 평가와 주제 피드백 구분 | 질문 6건에 답하고 문서 수정 |
| [#137](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/137) | 일대기 서버 연결(FE) | API 명세와 필드가 맞는지 | 승인 |
| [#212](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/212) | 카드 설명 의료 표현 검사 | 카드에만 둔 검사 규칙을 공통 함수로 합치자는 의견 | 논의 뒤 검사 범위를 고쳐 병합 |
| [#179](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/179), [#222](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/222), [#244](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/244), [#250](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/250), [#255](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/255) | 앱 동의 관리, 카드 생성 대기, 면회 이어하기, 접근성, 디자인 리뉴얼 | 요청한 동작이 실제로 되는지, 충돌 정리 뒤 기존 변경이 남았는지, 실기기 확인 결과 | 승인 뒤 병합 |
| [#157](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/157), [#243](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/243), [#252](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/252), [#253](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/253) | 서버 로그 제한, 앱 README, 앱 버전, 리포트 여정 테스트 | 변경이 코드와 문서에 맞는지, 배포 때 할 일 | 승인 뒤 병합 |

## 집계 방법

```bash
gh pr list -R kakaotechcampus-4/ktc4-chungnam-1 --state all --limit 400 --json number,author,state,baseRefName,reviews
gh api repos/kakaotechcampus-4/ktc4-chungnam-1/pulls/<번호>/reviews
gh api repos/kakaotechcampus-4/ktc4-chungnam-1/pulls/<번호>/comments
```
