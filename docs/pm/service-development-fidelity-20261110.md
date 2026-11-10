# 새록 서비스 개발 충실성 보고서

작성: 김영석 | 확인 기준: 2026년 11월 10일 22:05 KST

멘토 심사 ④ **서비스 개발 충실성, 15점**의 질문인 “기획한 핵심 기능을 충실히 구현하고, 서비스 가치를 높이는 범위의 기능까지 완성도 있게 개발했는가”에 대응한다. 최초 요구사항, 개발 중 결정 변경, 현재 구현과 검증 결과를 대조했다.

## 1. 종합 결과

새록은 처음 정한 **프로필 입력 → 대화 카드 → 녹음과 소감 → 전사와 리포트 → 이야기 확인 → 다음 대화 카드**의 연결을 구현했다. 보호자가 직접 대화하고, AI가 제안한 이야기는 보호자가 반영하는 제품 원칙도 유지했다.

확인된 성과와 남은 범위는 다음과 같다.

- 최초 정보, 사진 설명, 승인한 이야기와 지난 주제 반응을 카드 생성에 전달한다. 다음 카드에서 승인한 이야기를 다시 사용한 실제 기록도 있다.
- 처음의 단말 중심 구상은 성능 시험과 역할 조정을 거쳐 서버 처리로 바뀌었다. 카드와 리포트 생성, 사진 분석, 저장 API까지 연결됐다.
- 실사용에서 찾은 긴 녹음 처리, 지나치게 짧은 리포트, 적은 이야기 후보, 자동 분류 누락을 수정했다. 리포트와 이야기 추출은 같은 녹음의 수정 전후를 비교했다. 긴 녹음 분할은 최신 배포 후 실제 연결 재시험이 남았다.
- 생애 시기별 보기와 원클릭 변경 되돌리기 등 최초 요구사항 일부는 남아 있다. 이들을 현재 일대기나 수정 기능과 같은 것으로 계산하지 않는다.
- 기술적 연결이 성공해도 사용자가 대화에 도움을 받았는지는 별도다. 11월 10일 관찰에서는 개인화가 약한 첫 카드와 답하기 어려운 질문이 확인됐다. 장기간 재사용과 보호자 부담 감소는 아직 입증하지 않았다.

따라서 이 항목의 근거는 **핵심 흐름의 구현, 변경 이유가 남은 범위 조정, 실제 사용 결과를 고친 과정**이다. 모든 최초 요구사항과 실제 사용상의 문제가 해결됐다고 보고하지 않는다.

## 2. 비교 기준과 현재 버전

### 최초 기획의 기준

기준 문서는 저장소에 처음 올라온 [2026년 8월 31일 테크스펙, `b087bb3d`](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/b087bb3d/docs/tech-spec.md)이다. 문서 자체의 작성 기준일은 8월 24일이다. 이후 고친 문서를 최초 기획으로 소급하지 않았다.

당시 핵심 대상은 경도인지장애부터 경도 치매 단계 부모를 면회하는 보호자였다. 목표는 안부 뒤에 꺼낼 소재를 준비하고, 면회에서 얻은 정보를 다음 면회에 이어 쓰는 것이었다. 진단, 치료 효과, AI의 대화 대행, 피보호자 직접 인지훈련은 처음부터 범위 밖이었다. 카드 수, 모델, 추가 질문의 실시간 생성 여부는 당시 미정이었다.

### 코드, 배포와 검증의 구분

| 대상 | 이번 보고서에서 확인한 기준 |
| --- | --- |
| 최신 develop | `a9271fade0d68e3ace32e28a336b9087ad75e4b6`. 11월 10일 20:45 KST 커밋. 제품 코드는 `a855c87e`와 같고 그 뒤 변경은 README다 |
| 최신 운영 배포 기록 | 11월 10일 14:37 KST 완료한 [Deploy 실행 42762899876](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/actions/runs/42762899876), `a855c87e`. DB 백업과 격리 복원, worker 중지, 빌드, migration, 컨테이너 교체와 사후 점검 성공을 Actions 단계에서 확인했다. 배포 후 DB revision은 `5d2e8b1c9a47`이다. 서버에는 새로 접속하지 않았다 |
| 최신 코드 자동 검사 | [Product tests 실행 42810053493](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/actions/runs/42810053493), head `a9271fad`. Python 정적 검사, BE와 PostgreSQL, 앱과 BE E2E, Flutter, AI, STT의 6개 작업 성공. 실제 모델과 마이크 품질 시험은 포함하지 않는다 |
| GitHub 배포 APK | [release 페이지](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/releases/tag/release)에 11월 10일 18:01 KST 갱신한 `saerok-b6bd248a-prod-release.apk`가 있다. 안내된 기준 `b6bd248a`는 [#294](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/294)까지이며 [#296](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/296)~[#299](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/299)와 열린 앱 PR은 포함하지 않는다. APK 자체를 새로 설치해 확인하지는 않았다 |
| Play | 이번 보고서에서 콘솔을 조회하지 않았다. GitHub APK 갱신이나 BE 배포를 Play 최신판 게시로 표시하지 않는다 |
| main과 미병합 작업 | develop에서 main으로 보내는 [PR #230](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/230)은 열려 있다. 본문의 구현 판단은 develop 기준이다. 열린 [#300](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/300)~[#314](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/314), [#316](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/316), [#317](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/317)은 7절에서 따로 다룬다 |

20:45 KST의 Deploy workflow 실행도 성공으로 보이지만, 그 실행은 PR 검사이며 실제 배포 작업은 건너뛰었다. 위 표는 수동 실행의 `Deploy to production` 단계가 성공한 기록을 기준으로 삼았다.

## 3. 최초 요구사항과 현재 구현 대조

‘구현’은 해당 동작의 코드와 연결을 확인했다는 뜻이다. 모든 기기와 사용자에게 안정적이거나 유용하다는 뜻은 아니다. 실행 근거는 6절에 별도로 적었다.

| 최초 요구사항 | 현재 사용자가 할 수 있는 일 | 판정과 남은 차이 | 확인 근거 |
| --- | --- | --- | --- |
| FR-001 프로필과 생애 정보 입력, 수정 | 기본 정보와 직업, 고향, 취미, 가족을 저장하고 수정한다. 일대기에 이야기를 직접 추가하거나 고친다. 여러 프로필을 관리한다 | 구현. 세부 정보의 짧은 음성 입력도 연결됐으나 대기 시간 보완 [#317](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/317)은 미병합이다 | [프로필 API](../../backend/app/api/routes/profiles.py), [이야기 저장](../../backend/app/services/life_facts.py), [앱의 이야기 저장 연결](../../app/lib/features/life_story/life_story_providers.dart) |
| FR-002 사진에서 이야기 단서 얻기 | 사진을 올리고, 분석에 동의하면 설명을 만든다. 사용자가 고친 설명은 서버에 저장하며 다음 생성에 우선 사용한다 | 구현 방식 변경. 메타데이터는 제외했다. 사진 설명을 별도 승인 없이 카드에 사용하지만 승인된 생애 사실로 자동 저장하지 않는다 | [사진 분석](../../backend/docs/photo-analysis.md), [사진 설명 API](../../backend/app/api/routes/profile_photos.py), [#205](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/205), [#257](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/257), [#288](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/288), [#294](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/294) |
| FR-003 필수 동의와 녹음 전 확인 | 가입 필수 동의, 선택 동의 변경, 마이크 권한과 녹음 시작 안내가 있다. 서버는 음성 제출 시 필수 동의를 확인한다 | 계정 단위 흐름 구현. 피보호자별 대리 권한 확인과 기록을 별도 절차로 완성한 상태는 아니다. 사진 보관 동의 설명은 이후 처리방침 변경과 이전 설계가 달라 문서 정리가 필요하다 | [동의 API](../../backend/app/api/routes/auth.py), [음성 제출 검사](../../backend/app/services/speech_analysis_pipeline.py), [현재 테크스펙 FR-003](../tech-spec.md#기능-요구사항), [처리방침](../legal/PRIVACY.md) |
| FR-004 개인화 대화 소재 생성 | 최초 정보, 사진 설명, 확인된 이야기와 지난 주제를 살펴 카드 12장을 만든다. 첫 질문과 꼬리 질문, 근거를 제공한다 | 구현. 초기 정보가 입력에 있어도 최종 카드에 충분히 선택된다는 보장은 없다. 실제 첫 추천의 개인화 부족은 개선 대상으로 남았다 | [생성 입력 구성](../../backend/app/services/card_sets.py), [카드 생성 구조](../../ai/card_generation/README.md), [실사용 보고 PR #314](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/314) |
| FR-005 대화가 멈췄을 때 추가 지원 | 미리 만든 꼬리 질문과 보충 카드로 소재를 바꾼다 | 결정한 MVP 구현. 면회 중 발화를 듣고 실시간으로 새 질문을 생성하는 기능은 제공하지 않는다 | [카드 설계 5절](../architecture/card-generation-flow.md#5-주제-생성-분류와-면회-중-질문), [추가 카드 화면](../../app/lib/features/visit/add_cards_screen.dart) |
| FR-006 녹음 시작, 종료와 처리 상태 | 기기에서 녹음하고 소감과 함께 제출한다. 분석 대기, 완료와 실패를 확인하고 재요청한다 | 구현. 화면 잠금과 다른 앱 사용 중 녹음 유지 보완 [#302](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/302)는 아직 열려 있다. 서버의 긴 녹음 분할 [#299](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/299)와 구분한다 | [음성 처리](../../backend/docs/async-speech-analysis.md), [복구](../../backend/docs/speech-recovery.md), [#299](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/299), [#302](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/302) |
| FR-007 STT와 화자 처리 | 녹음을 전사하고 구간 시각과 화자 라벨을 리포트 생성에 전달한다. 빈 전사는 실패로 처리한다 | 구현. 화자 라벨은 보호자와 어르신 역할의 확정값이 아니다. 라벨이 적다는 이유로 결과 생성을 막지 않는 방향으로 바뀌었다 | [화자 처리 기준](../../backend/docs/speaker-fact-boundary.md), [STT 서버](../../stt-server/README.md), [#251](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/251) |
| FR-008 관찰값 리포트 | 대화 본문과 카드별 요약, 보호자 반응을 리포트로 본다 | 일부 구현. 발화 시간, 응답 지연, 화제 지속 시간을 수치로 계산해 보여주는 기능은 현재 리포트 응답과 화면에서 확인되지 않는다. 텍스트 요약을 수치 관찰값 구현으로 계산하지 않는다 | [현재 리포트 응답](../../backend/app/schemas/reports.py)의 `VisitReport`, [리포트 화면](../../app/lib/features/report/report_screen.dart) |
| FR-009 보호자 평가와 제안 확인 | 전체 소감과 카드별 사용 여부, 반응을 제출한다. 이야기 후보를 고치거나 빼고, 주제 조정 행동을 확인해 반영한다 | 구현. AI가 추천 제외를 제안해도 화면에서 미리 선택하지 않으며 보호자가 선택해야 한다. 3회마다 받는 별도 중간평가는 다른 미완료 기능이다 | [평가 저장](../../backend/app/services/evaluations.py), [변경 사항 확인 화면](../../app/lib/features/report/changes_screen.dart), [승인 저장](../../backend/app/services/proposals.py) |
| FR-010 승인 전 임시 보관과 승인 후 되돌리기 | 승인 전 후보는 이야기와 분리한다. 반영 전 후보 삭제를 화면에서 되돌릴 수 있고, 저장한 이야기는 일대기에서 직접 수정한다 | 일부 구현과 범위 변경. 이미 승인한 변경을 이력으로 되돌리는 기능은 없다. 거절 후보 30일 보관과 복구 API도 현재 연결되지 않았다 | [제안 저장](../../backend/app/services/proposals.py), [이야기 승인과 복구 설계](../architecture/card-generation-flow.md#이야기-후보의-승인-거절과-복구) |
| FR-011 생애 시기별 이야기 축적 | 가족, 취미, 일, 고향, 친구, 여행, 기타로 나눈 일대기를 읽고 수정한다. AI가 후보에 붙인 분류를 승인 시 저장한다 | 축적과 주제별 보기 구현. 생애 시기별 보기는 출시 이후로 미룬 결정이다. 현재 분류 안에서는 초기 세부 정보가 앞에 오고, 추가 이야기는 등록한 순서다. 최근 이야기 요약은 최신 등록순이다 | [일대기 모델과 정렬](../../app/lib/features/life_story/life_story.dart), [분류 승인](../../backend/app/services/proposals.py), [#125](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/125), [#295](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/295) |
| FR-012 다음 회차에 확인된 정보와 반응 반영 | 승인한 이야기, 기존 주제와 지난 카드 반응을 다음 생성에 전달한다. 더 자주, 덜 자주, 추천 제외 선택을 반영하고, 정정한 정보는 다음 준비에서 카드 묶음을 다시 만들 때 사용한다 | 구현. 새 이야기 저장 즉시 이미 만든 카드를 바꾸지는 않는다. 다음 생성의 입력 반영과 실제 카드 선택은 구분한다. 장기간 반복 사용의 효과 검증은 남았다 | [카드 입력 구성](../../backend/app/services/card_sets.py), [추천 점수](../../ai/card_generation/README.md#선호-점수), [두 번째 면회 검사](../../backend/docs/second-visit-verification.md), [#161](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/161), [#171](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/171), [#277](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/277) |

## 4. 바뀐 기획과 변경 이유

변경의 적절성은 원래 해결하려던 보호자의 문제를 유지하는지, 이유와 결정 기록이 있는지, 잃은 기능이나 새 부담을 명시했는지로 판단했다.

| 변경 | 결정과 이유 | 현재 반영 및 평가 |
| --- | --- | --- |
| 단말 AI와 단말 중심 저장 → 서버 처리와 서버 저장 | 9월 14일 팀 결정, 9월 15일 저장 경계 보완. 모바일 후보의 지연, 품질과 자원 한계 및 FE와 BE의 역할 중복을 확인했다. [ADR-006](../architecture/decisions/ADR-006-server-side-ai-processing.md)에 시험 근거와 대안이 남아 있다 | STT는 GPU 서버, 카드와 리포트 및 사진 설명은 ML API, 데이터는 BE와 PostgreSQL로 연결했다. 핵심 흐름을 구현하기 위한 변경이었다. 네트워크, 서버 가동과 개인정보 처리 부담은 추가됐다 |
| 사진 후보 별도 확인 → 설명 활용과 선택 수정 | 10월 11일 PM 정정 문서에 이미 합의한 방향을 반영했다. [PR [#97](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/97)의 결정 확인](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/97#discussion_r4183313066), ADR-006 후속 정정. 제외하기로 한 메타데이터도 정리했다 | 별도 확인 화면 부담을 줄이고 앨범 수정은 남겼다. 사진 설명을 실제 직업이나 가족관계의 확정 사실로 취급하지 않아야 한다 |
| 실시간 추가 질문 여부 미정 → 첫 질문과 꼬리 질문 사전 준비 | 9월 23일 기준과 [주제 카드 설계](../architecture/card-generation-flow.md#첫-질문과-꼬리-질문). 면회 전 준비하고 보호자가 필요할 때 선택하는 MVP로 범위를 정했다 | 대화 중 생성 응답을 기다리지 않는다. 실제 발화에 맞춘 실시간 질문은 빠진다. 최초 확정 요구인 “소재가 필요할 때 추가 지원”은 보충 카드로 유지했다 |
| 생애 시기별 일대기 → 주제 분류와 등록순 우선 | 이문영이 10월 15일 시기 추론의 어려움과 입력 부담을 제기했고, 김영석이 10월 16일 00:09 KST에 [출시 이후 생애 시기별 보기](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/125#issuecomment-6195369719)로 정했다 | 이야기를 읽고 쌓는 기능은 유지했다. 생애 시기별 구성은 명시적으로 미완료다. 관련 실제 사진을 이야기마다 연결하는 기능도 기본 그림으로 대체된 현재 범위와 구분한다 |
| 분류 직접 선택안 → AI 기본 분류, 필요할 때 수정 | 김민혁은 10월 16일 개발량과 선택 정확도를 이유로 직접 선택안을 제시했다. 김영석은 10월 18일 02:04 KST에 [사용자 부담을 줄이는 AI 분류 방향](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/125#issuecomment-6237227173)을 제안하고 당시 배포 범위는 BE 판단을 요청했다. [#139](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/issues/139)로 이어졌다 | 초기에는 저장 연결이 빠져 모두 기타였고, 11월 10일 병합한 [#295](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/295)가 AI 출력부터 승인 저장까지 연결했다. 사용자가 매번 분류를 먼저 고를 필요는 없다. 분류를 위한 별도 호출은 없다 |
| 수정할 때마다 생성 또는 일부 카드 교체 검토 → 다음 준비에서 12장 재생성 | 10월 16일 PM 기준 이후 일부 교체도 검토했으나, 김영석의 [10월 31일 02:50 KST 댓글](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/161#issuecomment-6529648361)이 회의에서 전체 12장 재생성으로 정했음을 확인한다 | [#171](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/171) 앱 처리 후 [#161](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/161) 서버 처리를 병합했다. 정정 때문에 사용할 수 없는 묶음은 막고 누적 정정을 한 번에 반영한다. 생성 중에는 관련 정보 수정이 거절되므로 기다리는 부담은 남는다. 새로운 이야기 추가는 기존 카드 오류와 구분해 다음 생성부터 쓴다 |
| 이야기 삭제 → 관련 주제 비선호 추정안 철회 | 10월 22일 멘토 권고 후 김영석이 [PM 변경안](mentoring-followup-20261022.md#삭제와-추천-제외의-구분)에 삭제와 추천 의사를 분리했다 | 삭제한 이야기는 새 입력에서 빼고, 별도 명시적 제외 선택을 추천 정책에 쓴다. 과거 카드와 면회 기록까지 자동 삭제하지 않는다. 삭제를 감정 평가로 확대하지 않는 방향이다 |
| 화자 라벨 부족 시 생성 차단 → 문맥 추론과 보호자 확인 | 이문영의 [PR #251](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/251), 11월 6일 17:34 KST 병합. 듣기만 한 참여자나 인원 입력 오류로 라벨 수가 달라질 수 있고, 같은 전사로 재요청해도 계속 막힌다는 이유로 차단을 제거했다. 작성자의 [17:40 KST 정정 댓글](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/251#issuecomment-6680822233)은 문맥으로 이야기 후보도 만들고 보호자가 확인하는 방향을 명시한다 | 불완전한 화자 분리에서도 기록을 제시한다. 대신 인물 귀속은 모델이 틀릴 수 있다. 모든 결과에 코드로 화자 미확인 표시를 붙인다는 과거 설명은 현행 동작과 다르다 |
| 과거 경험 위주, 적은 후보와 짧은 리포트 → 현재 생각과 계획도 후보로 받고 화제별 요약 | 김영석의 10월 19일 방향을 실제 출력과 대조했다. 11월 9일 면회에서 긴 대화를 짧게 요약하고 후보가 적게 나오는 문제를 찾아 [#295](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/295)로 수정했다 | 이야기 후보는 코드 상한 30개로 받고, 아픈 경험은 표시해 선택하게 한다. 1건 비교에서 후보와 요약의 내용이 늘었다. 카드 문안의 과거 경험 지향과 미래 계획 후보의 관계는 아직 남은 제약이다 |
| 승인된 변경 되돌리기 → 일대기에서 직접 수정 | [주제 카드 설계](../architecture/card-generation-flow.md#이야기-후보의-승인-거절과-복구)는 현재 계약에 승인 취소가 없고, 승인된 이야기는 직접 고친다고 명시한다 | 잘못된 정보를 바로잡는 목적은 일부 충족한다. 변경 이력 복원과 같은 기능은 아니다. 최초 되돌리기를 제외한 별도 결정 이유까지는 이번 확인에서 찾지 못해, 전부 완료로 처리하지 않는다 |

카드 12장은 최초 기획의 “3장을 주기로 한 확정안”을 어긴 결과로 보지 않는다. 최초 테크스펙에는 카드 수가 미정이며, 이후 선택용 9장과 보충용 3장, 카드별 첫 질문 1개와 꼬리 질문 3개로 계약을 구체화했다.

## 5. 핵심 사용을 보완한 추가 개발

| 추가하거나 보완한 기능 | 보호자에게 필요한 이유 | 현재 범위 |
| --- | --- | --- |
| 짧은 음성으로 프로필 정보 입력 | 긴 글을 직접 적는 부담을 줄인다 | FE [#146](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/146)과 BE [#214](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/214) 연결. 서버 대기 시간과 전체 동시 요청 제한 [#317](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/317)은 검토 중 |
| 사진 설명 서버 저장과 첫 카드 사진 대기 | 사진을 올렸는데 첫 추천에 쓰이지 않거나 수정한 설명이 사라지는 문제를 줄인다 | [#205](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/205), [#257](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/257), [#294](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/294). 분석 실패 시 재시도 또는 준비된 사진만 쓰는 선택 제공 |
| 분석 재요청과 기기 녹음 공유 | 실패한 면회 기록을 포기하지 않고 다시 처리하거나 파일을 꺼낼 수 있다 | [#213](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/213), [#296](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/296). 서버 전사 재사용은 기한과 횟수 제한이 있고 모든 실패를 자동 재시도하지 않는다 |
| 30분 초과 녹음 분할 | 긴 면회 한 건이 STT 호출 제한에 걸리는 문제에 대응한다 | [#299](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/299) 병합, 최신 BE 배포에 포함. 조각 전사 후 합치며 기기 원본은 전체 녹음으로 유지. 최신 배포 후 긴 실사용 녹음 재시험 기록은 별도 확인 필요 |
| 리포트 완료 알림, 홈 처리 상태와 새 버전 안내 | 분석을 기다리는 동안 앱을 계속 보고 있지 않아도 되고, 실패나 구버전 문제를 알 수 있다 | 푸시 [#247](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/247)~[#249](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/249), 새 버전 [#232](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/232)~[#233](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/233). 상태 안내를 더 명확하게 하는 [#307](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/307), [#310](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/310)은 미병합 |
| 지난 카드 조회와 좋아요 | 지난 질문을 다시 찾아보고 좋았던 주제를 다음 준비에 활용한다 | [#162](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/162), [#177](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/177). 회차의 카드 반응과 주제의 더 자주, 덜 자주 선택은 구분한다 |
| 아픈 기억 표시와 추천 제외의 직접 선택 | AI가 중요한 경험을 임의로 지우지 않고, 보호자가 다룰지 정할 수 있다 | [#295](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/295), [#297](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/297). 표시와 제외 선택은 서로 다른 기능이다. 민감한 순간을 캐묻지 않도록 하는 문안 규칙은 실제 출력 평가가 계속 필요하다 |
| 접근성, 재실행 복구, 자동 검사와 승인 배포 | 화면을 읽거나 중단 뒤 돌아오는 과정에서 기록을 잃지 않고, 변경 후 핵심 연결이 유지되는지 검사한다 | 접근성 [#208](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/208), [#266](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/266)과 복구 [#244](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/244), [#262](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/262), E2E [#218](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/218), [#226](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/226), [#258](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/258), CI [#211](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/211), 배포 [#256](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/256). 추가 실사용 화면 개선 [#300](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/300)~[#313](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/313)은 진행 중 |

추가 개발은 프로필 입력, 대화 준비, 기록 유지와 다음 면회 연결을 보완했다. CI와 배포 도구의 존재를 대화 기능의 유용성 검증으로 대체하지는 않는다.

## 6. 실행과 사용 결과

| 시점과 조건 | 확인한 결과 | 해석 범위와 자료 |
| --- | --- | --- |
| 11월 4일, 합성 대화로 실제 외부 연결 실행 | 실제 S3, STT와 생성 모델을 연결한 API 및 에뮬레이터 흐름, 이야기 승인과 다음 회차 반영 기록 | 당시 버전의 실행이다. 최신 기기 전체 성공을 뜻하지 않는다. [멘토 심사 근거표 3번과 8번](mentor-evidence.md) |
| 11월 8일, 운영 `42938250`, 합성 및 공개 자료를 순차 제출 | 면회 요청 44회 중 리포트 대상 35회 완료. 무음과 소음 9회 중 4회는 리포트가 만들어지는 문제도 확인. 사진 86건 완료, 완료 알림 39건 수신 | 동시 사용자 시험이 아니다. 카드 생성 중앙값 45.5초, 업로드부터 리포트까지 중앙값 18.5초는 해당 입력과 당시 환경의 수치다. [운영 안정성 시험](../../backend/docs/stability-test-20261108.md) |
| 11월 9일, 허가받은 실제 면회 녹음 1건의 생성 결과 비교 | 수정 전 리포트 309자와 이야기 후보 2개에서, 수정 후 약 1,400자와 14개 후보로 변했다. 자동 분류도 확인했다 | 같은 녹음의 생성 단계 비교이며 수정판으로 운영 DB를 덮어쓴 시험은 아니다. PM이 확인한 단일 사례다. [실제 면회 수정 검증](real-visit-validation-20261109.md), [#295](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/295) |
| 11월 10일, 실사용자 관찰과 저장 기록 확인 | 첫 회차의 리포트 생성, 이야기 2개 저장, 다음 카드 2장이 그 이야기를 근거로 사용한 기록. 두 번째 회차는 빈 전사로 실패 | PM 보고 [#314](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/314)는 열려 있다. 본 보고서에서 운영 DB를 다시 조회하지 않고 공개 보고 내용을 대조했다. 첫 입력의 개인화 부족, 답하기 어려운 질문과 빈 전사 원인은 구분해야 한다. [보고서 PR #314](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/314) |
| 11월 10일 20:45 KST 시작, 최신 develop CI | 정적 검사, 앱, BE와 PostgreSQL, AI, STT, 앱과 BE E2E 작업 성공 | E2E는 실제 API와 DB를 쓰지만 Google, S3, STT와 모델은 합성으로 바꾼다. 실제 마이크, 화자 정확도와 AI 출력 품질은 확인하지 않는다. [CI 실행](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/actions/runs/42810053493), [검사 범위](../product-tests.md) |

### 실사용 결과가 보여 준 남은 문제

11월 10일 보고에서는 최초 카드 12장 중 일반 소재가 10장이고 비어 있는 초기 정보를 묻는 카드가 2장이었다. 초기 정보가 생성 입력에 전달됐지만 이를 직접 근거로 한 최종 카드가 없었다. 다음 생성에서는 승인한 이야기 두 개를 근거로 삼은 카드가 나왔다. **입력 전달과 다음 정보 재사용은 확인됐지만, 첫 추천이 개인의 상황에 충분히 맞는지는 개선이 필요하다.**

이번 참여자는 PM 설명상 중증 치매 사례였다. 대화를 이어 가기 어려웠다는 현장 결과는 기존에 경도인지장애와 경도 치매 보호자를 우선 대상으로 정한 방향과 맞았다. 중증 사용의 어려움만으로 원래 대상에게 도움이 되는지 판단할 수는 없다. 불명확한 표현은 현장에서도 발음을 알아듣기 어려웠다는 확인이 있으므로 모두 STT 오류로 집계하지 않았다. 두 번째 회차의 `EMPTY_TRANSCRIPT` 원인은 별도 미확인이다.

짧은 단어 단서 제공은 이 관찰에서 나온 개선 제안이다. 현재 카드의 첫 질문과 꼬리 질문을 단어 추천 기능으로 설명하지 않는다. 재사용률, 준비 부담 변화, 개인화 카드와 일반 카드의 블라인드 선택 비교는 아직 결과를 확보하지 못했다.

## 7. 미완료 범위와 열린 PR

### 기획과 비교했을 때 남은 범위

| 항목 | 현재 상태 | 보고와 후속 처리 기준 |
| --- | --- | --- |
| 생애 시기별 보기와 이야기별 실제 사진 연결 | 주제 분류, 등록순과 기본 그림으로 제공. 생애 시기별 보기는 [#125](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/125)의 출시 이후 결정 | 현재 일대기 제공 범위를 그대로 설명하고, 연도별 또는 생애 시기별 구성 완료로 쓰지 않는다. 사진 연결은 [#125](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/125)에서 작업량에 따라 이월하는 조건부 방향이었다 |
| 승인 변경 이력 복원, 거절 후보 30일 복구 | 승인된 이야기 직접 수정과 제출 전 화면 되돌리기만 확인 | 원클릭 승인 취소, 거절 후 30일 복구와 구분한다. 관련 설계 문구를 구현 완료 근거로 쓰지 않는다 |
| 발화 시간과 응답 지연 등 수치 리포트, 저신뢰 결과 수동 대체 | 텍스트 리포트와 보호자 소감, 빈 전사 실패 및 재요청이 현재 경로 | 초기 수치 요구와 실패 시 수동 입력 대체를 모두 충족했다고 쓰지 않는다. 소감 입력만으로 리포트를 완성하는 별도 경로는 확인되지 않았다 |
| 3회마다 중간평가, 대화 내용별 추가 피드백 질문 | [#154](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/154)의 PM 변경안에는 있으나 현재 앱, API와 저장 연결은 확인되지 않음 | 매회 소감이나 기존 more, less, exclude 확인과 같은 기능으로 계산하지 않는다. 제출 범위 포함 여부의 후속 판단이 필요하다 |
| 첫 카드 적합성과 대상에 맞는 질문 | 실제 입력을 쓰는 코드가 있지만 11월 10일 사례에서 개인화가 약함 | [#314](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/314)의 후속 품질 항목으로 남긴다. 단어 단서와 현재 상황 반영은 새 개선 제안이며 구현 완료가 아니다 |
| 장시간 및 동시 사용, 백그라운드 녹음 | 긴 녹음 분할은 [#299](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/299)로 들어왔다. 순차 시험 결과는 있지만 여러 계정의 대기와 처리량 검증은 부족하다. [#302](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/302), [#317](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/317) 미병합 | 카드 worker가 작업을 차례로 가져오는 구조와 생성 제한을 구분한다. [#286](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/286)은 다른 작업을 처리하는 동안 기다리는 카드를 시작 지연만으로 실패시키지 않게 했지만 처리량 확대를 검증한 것은 아니다 |
| 개인정보 삭제와 보관 운영 | 삭제 실행기와 백업 정리 코드가 있다. 최신 배포 성공만으로 정기 실행과 실제 삭제 완료를 입증하지 못함 | 별도의 운영 기록으로 확인한다. 이번 보고서에서 서버 설정과 보관 자료를 조회하거나 변경하지 않았다 |

### 확인 시점에 열린 PR

아래 내용은 PR의 목적과 현재 상태를 정리한 것이다. 병합 가능 판정이나 수정 완료 승인이 아니다. [#300](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/300)~[#314](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/314)와 [#316](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/316)은 김영석, [#317](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/317)은 김민혁 작성이다. 이번 보고서 작업에서는 각 PR의 전체 테스트를 다시 실행하지 않았다.

| 구분 | PR | 완료 범위에 아직 넣지 않은 내용 |
| --- | --- | --- |
| 녹음 유지와 시작 | [#300](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/300), [#301](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/301), [#302](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/302), [#303](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/303) | 종료한 회차의 잘못된 녹음 재개, 녹음 표시, 화면 잠금과 다른 앱 사용 중 녹음, 시작 대기와 실패 안내 |
| 권한과 세션 | [#304](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/304), [#305](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/305) | 마이크 설정 이동, 로그인 만료 안내와 녹음 정리 |
| 카드와 진행 상태 | [#306](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/306), [#307](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/307), [#308](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/308) | 꼬리 질문 넘기기, 홈 진행과 실패 표시, 카드 더 보기와 선택 영역 |
| 입력과 접근성 | [#309](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/309), [#310](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/310), [#311](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/311), [#312](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/312), [#313](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/313) | 로그인 문구, 약관 스크롤, 업데이트 배너, 입력 초안, 날짜와 나이 입력, 큰 글자 |
| 검증 보고 | [#314](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/314), [#316](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/316) | 실사용 관찰과 프롬프트 인젝션 시험 보고. 문서 병합과 제품 기능 반영은 별개다. [#316](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/316)의 시험 수치를 이번에 재현하지 않아 안전성의 추가 확정 근거로 쓰지 않았다 |
| 짧은 음성 입력 | [#317](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/317) | 앱보다 오래 서버가 기다리는 문제와 서버 전체 동시 요청 상한. 제한값 적용은 PM 검토가 남아 있다 |
| main 제출 | [#230](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/230) | develop 통합 제출. 열려 있으므로 본 보고서의 기능이 main에 모두 들어갔다고 쓰지 않는다 |

열린 이슈 수로 미개발 기능 수를 계산하지 않았다. 예를 들어 [#139](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/issues/139)는 열려 있지만 이야기 후보 AI 분류와 승인 저장은 [#295](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/295)에서 구현됐다.

## 8. 심사 항목에 대한 정리

**기획한 핵심 기능의 구현:** 대화 전 준비, 실제 녹음과 분석, 보호자 확인, 이야기 축적과 다음 추천까지 코드가 연결됐고 자동 검사 및 실제 처리 기록이 있다. 후보 확인을 거치지 않고 새 이야기를 사실로 저장하지 않는 원칙은 유지했다.

**변경 사유의 적절성:** 모바일 성능에 따른 서버 전환, 면회 중 대기 부담을 줄이는 사전 질문 준비, 기록을 잃지 않기 위한 비동기 처리와 복구는 원래 사용자 목적에 연결된다. 생애 시기별 보기의 이월도 결정 기록이 있다. 반면 승인 후 되돌리기와 수치 리포트처럼 충분한 대체 또는 완료 근거가 없는 항목은 남은 기능으로 명시했다.

**서비스 가치를 높인 개발:** 입력을 돕는 음성 전사와 사진 설명, 정정 후 카드 재생성, 긴 녹음 분할, 리포트 완료 알림, 직접 고치는 일대기와 접근성 보완을 추가했다. 실제 사용에서 드러난 문제를 PR과 비교 시험으로 이어 간 기록이 있다.

**완성도 판단의 한계:** 실사용에서 확인한 순환은 중요한 근거지만 표본이 작고, 최초 카드의 개인화와 질문 난이도 문제가 남았다. 최신 BE, 최신 앱, 실제 마이크와 실제 모델을 모두 연결한 재시험 및 원래 목표 대상의 반복 사용 관찰이 필요하다. 이 보고서는 자체 점수나 임의의 완성률을 부여하지 않는다.

## 9. 이번 보고서의 확인 방법

- 최초 테크스펙을 최초 커밋에 고정하고, 현재 PM 기준과 ADR, 카드 설계, 멘토링 후 변경안을 대조했다.
- develop `a9271fad`의 카드 입력 구성, 6개 읽기 도구, 승인 저장, 현재 리포트 응답, 일대기 분류와 정렬, 음성 처리와 복구 연결을 정적으로 확인했다. 도구는 BE가 준비한 입력을 조회하며 모델이 운영 DB에 직접 접속하는 구조가 아니다.
- GitHub에서 열린 PR, 관련 결정 댓글과 병합 시각, Product tests 작업 결과, 실제 배포 단계와 Releases 첨부 목록을 조회했다. 배포 단계가 건너뛰어진 workflow 성공은 배포 근거에서 제외했다.
- 11월 8일 안정성 시험, 11월 9일 실제 면회 비교, [#314](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/314)의 11월 10일 실사용 보고는 각각의 조건과 한계를 유지해 인용했다. 과거 결과를 최신 버전 재시험으로 바꾸지 않았다.
- 이번 작업에서는 앱 실행, 모델 호출, 운영 서버 접속과 DB 조회를 새로 하지 않았다. 실제 사용자 이름, 계정, 전사문, 리포트 전문과 내부 식별자는 옮기지 않았다.
- 기존 문서에 남은 `83695093` 배포 기준이나 “실사용 관찰 없음”은 그 문서의 갱신 시점 기록으로 구분했다. 본 보고서는 위 확인 시점의 별도 대조 결과이며, 과거 검증 기록을 덮어쓰지 않는다.
