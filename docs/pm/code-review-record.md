# 주요 PR 코드 리뷰 기록

GitHub PR에 남은 코드 리뷰 가운데 주요 기록을 모았다. 멘토 리뷰는 매주 `develop → main` PR에서, 팀 리뷰는 `develop` 대상 PR에서 했다. 리뷰 규칙은 [협업 규칙](../../CONTRIBUTING.md)의 "팀 내부 PR"과 "멘토 리뷰 PR"에 있다. 집계 기준 시각은 2026-11-11 KST다.

## 요약

- 멘토 리뷰 PR 8건이 모두 수정 요청 1회 뒤 승인으로 끝났다. 멘토 리뷰는 17건(수정 요청 8, 승인 9)이다.
- 멘토 지적은 주로 실패 경로(작업이 끝나지 않는 경우, 다시 보낼 수 없는 경우, 예외에서 빠지는 로그)와 PR 범위에 관한 것이었다. 지적을 받은 다음 주 PR에서 처리 결과를 답하고 재리뷰를 요청했다.
- 팀 리뷰는 대부분 PR 대화 댓글로 했다. 작성자가 아닌 사람이 남긴 200자 이상 댓글이 107개 PR에 175개 있다. GitHub 리뷰 기능(승인, 수정 요청)으로 남은 것은 27개 PR이다.

## 멘토 리뷰

| PR | 내용 | 수정 요청에서 짚은 것 | 승인 |
| --- | --- | --- | --- |
| [#17](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/17) | MVP 화면 흐름과 공통 개발 기반 | repository에 쓰기 경로가 없음, 계약에 없는 값이 정상값으로 바뀜, 처리 못 한 예외에서 요청 로그와 `X-Request-ID`가 빠짐, Flutter 검사 결과 첨부 ([9/10 리뷰](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/17#pullrequestreview-5162001905)) | 9/15. 미평가 카드를 `neutral`로 쓰는 규칙이 계약에 없음, 500 오류 traceback 기록 ([리뷰](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/17#pullrequestreview-5204369135)) |
| [#48](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/48) | 구글 로그인과 온프레미스 GPU 결정 | 알림 동의가 FE는 선택, BE는 필수로 어긋남, 로그인 구현을 main에 올릴 근거, 모르는 `kid`에 JWKS를 두 번 받음 ([9/17 리뷰](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/48#pullrequestreview-5230178814)) | 9/19 ([리뷰](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/48#pullrequestreview-5255629701)) |
| [#70](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/70) | 구글 로그인 연동, STT 요청 전달 API, 협업 규칙 개선 | STT 요청의 시간 초과와 연결 실패 테스트가 없음 ([9/23 리뷰](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/70#pullrequestreview-5291610275)) | 9/26. PR을 완료 가능한 작업 단위로 나누는 연습을 권함 ([리뷰](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/70#pullrequestreview-5325497124)) |
| [#81](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/81) | 면회 녹음, 비동기 음성 분석, 보호자 위로 화면 | worker가 죽으면 그 면회가 끝나지 않음, 실패한 면회를 다시 보낼 방법이 없음 ([10/1 리뷰](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/81#pullrequestreview-5373721907)) | 10/3. AI 서버의 입력 오류가 모두 500, import 시점 모델 적재 ([리뷰](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/81#pullrequestreview-5400173365)) |
| [#101](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/101) | 다중 프로필 화면, BE 공통 구조, 개발 서버 배포 준비 | 남은 흐름의 연결 계획, 작업 임대 만료를 넣으며 생긴 결정 ([10/8 리뷰](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/101#pullrequestreview-5452739121)) | 10/10. 복구 범위와 순서, 자동 재시도 1회, 보관 기준을 별도 PR로 나눈 판단이 적절하다고 봄 ([리뷰](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/101#pullrequestreview-5479016436)) |
| [#122](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/122) | 프로필, 카드, 면회 API와 보호자 확인 화면 통합 | 10/14 통합 계획과 실제 PR의 차이, 카드 생성이 "만드는 중"에서 끝나지 않는 경로 ([10/15 리뷰](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/122#pullrequestreview-5529340294)) | 10/19 ([리뷰](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/122#pullrequestreview-5565966469)). 승인 시점 코드만 [#168](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/168)로 main에 반영, 10/28 멘토 승인 |
| [#169](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/169) | 사진과 일대기 서버 연결, STT 운영 보완 | STT 서버가 공개 주소로 열렸는데 호출자를 확인하지 않음 ([10/30 리뷰](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/169#pullrequestreview-5708083570)) | 10/31. STT 접근 제한(#172)과 worker 종료 유예(#173) 후속 확인 ([리뷰](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/169#pullrequestreview-5721678791)) |
| [#230](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/230) | 카드 재생성, 분석 복구, AI 품질과 운영, 자동 검사 보완 | 화자를 확인하지 못한 회차는 리포트를 못 받고 다시 요청할 방법이 없음, 리포트 의료 표현 검사가 인용문까지 잡을 수 있음 ([11/5 리뷰](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/230#pullrequestreview-5778396716)) | 11/7 ([리뷰](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/230#pullrequestreview-5812767149)) |

### 멘토 리뷰 뒤 바꾼 것

| 지적 | 바꾼 것 |
| --- | --- |
| #81 worker가 죽으면 면회가 끝나지 않고, 실패한 면회를 다시 보낼 수 없음 | 작업 임대 만료와 재시도, 분석 실패 후 다시 요청을 추가(#101 이후) |
| #122 여러 생성 작업을 한 PR에 담고 순서를 전제로 쌓은 구조 | PR 범위 규칙 "독립적으로 검증할 작업 단위"를 추가([#127](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/127)) |
| #169 STT 서버 호출자 확인 없음 | 접근 제한을 이슈 [#172](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/issues/172)로 등록해 추적 |
| #230 화자 미확인 회차의 리포트 | 화자 정보가 부족해도 리포트와 제안을 만들도록 변경([#251](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/251), 11/6), 앱 여정 테스트와 문서 갱신([#253](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/253)) |

## 팀 내부 리뷰: 리뷰 기능

리뷰 기능으로 의견을 주고받은 주요 PR이다. 승인 리뷰만 남은 PR은 확인한 내용을 적었다.

| PR | 내용 | 리뷰에서 다룬 것 | 결과 |
| --- | --- | --- | --- |
| [#35](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/35) | ADR-006 서버 처리 결정 문서 | PM 확정 범위(STT와 VLM의 서버 처리)보다 구체적인 운영 방식이 들어감 | 수정 요청 뒤 닫고 [#36](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/36)에서 범위를 줄여 다시 올림 |
| [#33](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/33) | 이미지 분석 모델 비교 | 비교에 쓴 프롬프트 원문이 해시로만 있음 | 프롬프트 원문과 JSON Schema를 추가 |
| [#34](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/34) | 모바일 STT 벤치마크 | 출처와 재배포 권한이 확인되지 않은 녹음 파일이 들어감 | 수정 요청 뒤 녹음, 정답 전사문, 대형 결과를 빼고 승인 |
| [#36](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/36), [#37](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/37) | 온프레미스 GPU 처리 결정(ADR-006) | 자체 GPU 장비 사용 제안, STT 모델과 화자 분리 방식 | #36은 상태 문구 정정, #37은 장비와 모델 선택을 논의 |
| [#84](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/84) | DB 스키마 제안 | 주제 추천 방향(`up`, `down`)과 보호자 선택의 구분 | 리뷰 댓글로 필드 의미를 정리 |
| [#97](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/97) | 주제 카드 생성과 다음 면회 반영 흐름 | 사진 설명 사용 방식, 분류 6개의 용도, 거절 후보 복구, 이야기 시기 정보, 카드 평가와 주제 피드백 구분 | 질문 6건에 답하고 문서 수정 |
| [#137](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/137) | 일대기 서버 연결(FE) | API 명세와 필드가 맞는지 | 승인 |
| [#212](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/212) | 카드 설명 의료 표현 검사 | 카드에만 둔 검사 규칙을 공통 함수로 합치자는 의견 | 논의 뒤 검사 범위를 고쳐 병합 |
| [#179](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/179), [#222](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/222), [#244](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/244), [#250](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/250), [#255](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/255) | 앱 동의 관리, 카드 생성 대기, 면회 이어하기, 접근성, 디자인 리뉴얼 | 요청한 동작이 실제로 되는지, 충돌 정리 뒤 기존 변경이 남았는지, 실기기 확인 결과 | 승인 뒤 병합 |
| [#157](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/157), [#243](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/243), [#252](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/252), [#253](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/253) | 서버 로그 제한, 앱 README, 앱 버전, 리포트 여정 테스트 | 변경이 코드와 문서에 맞는지, 배포 때 할 일 | 승인 뒤 병합 |

## 팀 내부 리뷰: PR 대화 댓글

### 팀원 사이 리뷰

| PR | 리뷰에서 다룬 것 | 결과 |
| --- | --- | --- |
| [#300](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/300), [#301](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/301), [#302](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/302) | FE 리드가 녹음 화면 변경을 실기기에서 확인, 카드 화면 간격과 녹음 전 안내 문구를 고침 | 확인 결과와 수정 커밋을 PR에 남김 |
| [#205](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/205), [#206](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/206), [#208](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/208), [#250](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/250) | 사진 설명 저장, 녹음 복구, TalkBack 낭독을 실기기(Galaxy S23+, Android 15)에서 확인. 카드 펼침 상태가 Android 16 미만에서 낭독되지 않는 점, 펼친 직후 "선택 안 됨"으로 읽는 점을 찾음 | 확인한 항목은 병합, 남은 항목은 후속으로 둠 |
| [#242](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/242), [#251](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/251) | 멘토가 짚은 화자 미확인 회차 문제를 실패로 남겨 재요청하는 대신, AI 리드가 리포트 생성의 화자 조건을 없애는 방법을 제안 | [#242](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/242)를 닫고 [#251](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/251)로 병합 |
| [#212](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/212), [#241](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/241) | 의료 효과 표현 검사가 정상 문장까지 막지 않도록 단어 포함 대신 문장 전체 일치로 좁히는 방향 | 카드와 리포트 검사를 같은 방식으로 맞춤 |
| [#198](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/198) | 리포트가 검사에 걸리면 다시 만드는 경로([#213](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/213))가 먼저 있어야 한다는 병합 순서, 생성 단계에서 미리 검사하는 방안 | 논의 뒤 병합 |
| [#161](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/161), [#171](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/171) | 정보를 고친 뒤 카드 묶음을 다시 만드는 동작. BE와 FE 병합 순서, 생성 중 정정을 막는 시간, 묶음 단위 재생성 결정 확인 | FE 작업 계획(#166)에 반영 |
| [#125](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/125) | 일대기 이야기의 분류 저장, AI 분류와 보호자 선택 중 무엇으로 할지, 시기순 정렬 | 이슈 #139로 분리 |
| [#136](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/136) | 사진 주소를 만들지 못할 때 목록 전체를 실패시킬지 그 항목만 사진 없이 보일지 | 그 항목만 `photo: null`로 처리 |
| [#123](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/123) | STT만 시험할 때 ML API 키 없이 worker를 띄우는 옵션, 임대가 만료된 작업이 리포트 생성까지 이어지는 문제 | STT 단독 실행 옵션과 늦게 도착한 결과를 저장하지 않는 처리 추가 |
| [#275](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/275) | BE 리드가 서버에서 빌드해 동작 확인, 실패하던 테스트를 고침 | 수정 커밋 뒤 병합 |

### PM 리뷰

PM이 팀원 PR에 남긴 200자 이상 댓글은 139개다. 대부분 병합 전 확인 결과(실행한 테스트 수, 충돌 여부, 배포 때 할 일)를 적은 댓글이고, 문제를 재현해 수정을 요청한 대표 사례는 아래와 같다.

| PR | 요청한 것 | 결과 |
| --- | --- | --- |
| [#175](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/175) | 세션 만료 자동 재로그인에서 늦게 도착한 만료 응답, 재로그인 중 계정 변경 등 경합 상황 | 3차례 보완 뒤 테스트 694개와 재현 테스트 42개 통과를 확인하고 병합 |
| [#179](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/179) | 동의 저장 중 화면 이동, 회원탈퇴 안내 화면이 저절로 닫힘, 로그인 만료 때 로그아웃 버튼이 사라짐 | 수정 확인 뒤 병합 |
| [#153](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/153) | 시간 초과로 끝낸 작업에 늦게 온 응답이 다음 AI 호출까지 이어지는 문제를 시험용 응답으로 재현 | 반복 시험 40회 통과를 확인하고 병합 |
| [#146](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/146) | 전사가 끝나기 전에 다음 답변을 녹음하면 새 녹음이 멈추고 지워질 수 있음 | 보완과 재현 테스트 추가 뒤 병합 |
| [#110](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/110) | 응답 없이 연결만 유지되는 모델 호출이 카드 생성 시간 제한을 넘김 | 보완 뒤 병합 |
| [#161](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/161) | PM이 앞서 전한 "카드 12장 전체 재생성" 기준을 정정하고, 고친 정보와 관련된 카드만 표시하도록 재검토 요청 | 기준 정정 뒤 병합 |
| [#95](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/95) | 마지막 프로필 삭제를 회원 탈퇴로 안내하는 흐름을 프로필 삭제와 계정 유지로 분리 | 반영 뒤 병합 |
| [#255](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/255) | 디자인 리뉴얼에서 설정의 알림 스위치가 실제 알림과 이어지지 않음 등 2건 | 수정 뒤 병합 |
| [#293](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/293) | 개인정보 처리방침의 동의 항목이 운영 코드와 다름 | 정정 뒤 병합 |

## 집계 방법

```bash
gh pr list -R kakaotechcampus-4/ktc4-chungnam-1 --state all --limit 400 --json number,author,state,baseRefName,reviews
gh api repos/kakaotechcampus-4/ktc4-chungnam-1/pulls/<번호>/reviews
gh api repos/kakaotechcampus-4/ktc4-chungnam-1/pulls/<번호>/comments
gh pr list -R kakaotechcampus-4/ktc4-chungnam-1 --state all --limit 400 --json number,author,comments
```
