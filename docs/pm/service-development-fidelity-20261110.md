# 새록 서비스 개발 결과 보고서

최초 기획, 주요 변경과 검증 결과

작성: 김영석 | 갱신: 2026년 11월 11일 00:28 KST

새록의 최초 목표는 보호자가 면회 대화를 준비하고, 함께 나눈 이야기를 기록해 다음 면회에 이어 쓰도록 돕는 것이었다. 현재 **프로필과 사진 입력 → 대화 카드 준비 → 녹음과 소감 → 리포트와 이야기 후보 → 보호자 확인 → 다음 카드 추천**의 핵심 흐름이 구현됐다. 실제 면회에서도 승인한 이야기가 다음 카드의 근거로 사용된 기록이 있다.

개발 중에는 모바일 성능, 보호자의 입력 부담과 실제 사용 결과에 맞춰 처리 방식과 화면을 바꿨다. 이 보고서는 멘토 심사 ④ 서비스 개발 충실성에 맞춰, 최초 기획의 목적이 현재 기능에 어떻게 반영됐는지와 변경 이유, 검증 및 개선 결과를 정리한다.

## 1. 기획한 핵심 기능과 현재 구현

최초 비교 기준은 [8월 31일 테크스펙](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/b087bb3d/docs/tech-spec.md)이다. 현재 구현은 이후 회의와 PM 결정으로 조정한 범위를 함께 적용했다.

| 최초 요구사항 | 현재 제공하는 기능 | 구현과 변경 근거 |
| --- | --- | --- |
| FR-001 프로필과 생애 정보 | 기본 정보와 직업, 고향, 취미, 가족 정보를 저장하고 수정한다. 일대기에 이야기를 직접 추가하거나 고칠 수 있다. 글 입력을 돕는 짧은 음성 전사도 연결했다 | [프로필 API](../../backend/app/api/routes/profiles.py), [이야기 저장](../../backend/app/services/life_facts.py), [짧은 전사](../../backend/docs/short-speech-transcription.md) |
| FR-002 사진에서 대화 단서 얻기 | 등록 사진의 설명을 AI가 만들고 카드 생성에 활용한다. 보호자가 수정한 설명은 서버에 저장하고 우선 사용한다 | [사진 분석](../../backend/docs/photo-analysis.md), [첫 카드 사진 준비 #294](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/294). 사진 메타데이터와 별도 설명 승인 단계는 기존 결정에 따라 제외했다 |
| FR-003 동의와 녹음 전 확인 | 가입 동의와 설정의 동의 관리, 기능별 권한 확인을 제공한다. 서버에서도 음성 제출에 필요한 동의를 검사한다 | [동의 API](../../backend/app/api/routes/auth.py), [음성 제출 검사](../../backend/app/services/speech_analysis_pipeline.py), [처리방침 #293](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/293) |
| FR-004 개인화 대화 카드 | 초기 정보, 사진 설명, 승인한 이야기와 지난 주제 반응을 참고해 카드 12장을 만든다. 카드에는 첫 질문, 꼬리 질문과 근거가 있다 | [입력 구성](../../backend/app/services/card_sets.py), [카드 생성 구조](../../ai/card_generation/README.md). 에이전트가 6개 읽기 도구로 필요한 자료를 찾고, 후보 선정과 문안 검사를 거친다 |
| FR-005 대화 중 추가 지원 | 준비한 꼬리 질문과 보충 카드로 대화를 이어 간다. 대화가 잘 이어지면 앱이 개입하지 않는다 | [9월 23일 이후 적용한 사전 준비 방식](../architecture/card-generation-flow.md#첫-질문과-꼬리-질문). 실시간 질문 생성은 현재 MVP 범위에서 제외했다 |
| FR-006 녹음과 처리 상태 | 녹음, 소감 저장, 제출, 분석 상태와 결과 조회를 연결했다. 기기에 남은 녹음으로 재제출하고 파일을 공유할 수 있다 | [비동기 분석](../../backend/docs/async-speech-analysis.md), [실패 복구](../../backend/docs/speech-recovery.md), [파일 공유 #296](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/296). 백그라운드 녹음 보완 #302는 구현 및 실기기 확인 보고 후 병합 대기다 |
| FR-007 전사와 화자 처리 | Whisper 전사와 화자 구분 결과를 리포트 생성에 전달한다. 빈 전사는 실패로 처리하며, 화자 라벨이 부족할 때는 대화 문맥과 보호자 확인을 활용한다 | [STT 서버](../../stt-server/README.md), [현재 화자 처리 기준](../../backend/docs/speaker-fact-boundary.md), [#251](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/251) |
| FR-008 면회 리포트 | 대화 본문과 카드별 요약, 보호자 반응을 정리한다. 긴 대화의 여러 화제를 담도록 생성 방식을 보완했다 | [리포트 응답](../../backend/app/schemas/reports.py), [실제 면회 결과 보완 #295](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/295). 현재 리포트는 텍스트 중심이며, 초기 구상의 발화량과 응답 지연 수치는 제공하지 않는다 |
| FR-009 보호자 평가와 확인 | 면회 만족도, 어르신 반응, 카드 사용 여부와 반응을 저장한다. 이야기 후보를 수정하거나 제외하고, 주제 조정 행동을 선택해 반영한다 | [평가 저장](../../backend/app/services/evaluations.py), [변경 사항 확인 화면](../../app/lib/features/report/changes_screen.dart). AI의 추천 제외 제안은 보호자의 선택 후 적용한다 |
| FR-010 확인한 정보 반영과 정정 | 승인 전 후보와 저장된 이야기를 구분한다. 제출 전 후보 제외는 되돌릴 수 있고, 저장한 이야기는 일대기에서 직접 수정한다. 정정은 다음 카드 준비에 반영한다 | [현재 PM 기준](README.md#카드와-이야기의-현재-기준), [승인 저장](../../backend/app/services/proposals.py). 초기의 승인 취소 방식은 현재 계약의 직접 수정 방식으로 정리됐다 |
| FR-011 이야기 축적 | 승인한 이야기를 가족, 취미, 일, 고향, 친구, 여행, 기타로 모아 보여준다. AI가 분류를 붙이고 사용자는 필요할 때 수정한다. 최근 이야기와 전체 목록을 제공한다 | [일대기 분류와 정렬](../../app/lib/features/life_story/life_story.dart), [분류 저장 #295](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/295). 생애 시기별 보기는 출시 이후 확장으로 분리했다 |
| FR-012 다음 면회에 반영 | 승인한 이야기, 지난 카드 반응과 더 자주, 덜 자주, 추천 제외 선택을 다음 생성에 전달한다. 사실 정정 후에는 다음 대화 준비에서 카드 묶음을 다시 만든다 | [카드 입력 구성](../../backend/app/services/card_sets.py), [추천 점수](../../ai/card_generation/README.md#선호-점수), [정정 반영 #161](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/161), [주제 결정 반영 #277](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/277) |

현재 제품은 보호자가 직접 대화하고 AI가 준비와 정리를 돕는 구조다. AI가 만든 이야기는 보호자가 확인한 뒤 일대기에 저장하며, 새 이야기 추가와 잘못된 사실 정정은 서로 다른 갱신 규칙으로 처리한다.

## 2. 개발 중 바꾼 결정과 이유

| 처음 검토한 방식 | 최종 적용한 방향과 이유 | 결정 및 결과 |
| --- | --- | --- |
| 단말에서 AI와 데이터 처리 | 모바일 모델의 지연, 품질과 자원 한계를 확인해 서버 처리로 전환했다. 앱, API, 생성 작업과 GPU 전사를 나눠 연결했다 | 9월 14일 팀 결정과 9월 15일 저장 경계 정리. [ADR-006](../architecture/decisions/ADR-006-server-side-ai-processing.md)에 시험과 대안 기록 |
| 사진 단서를 따로 확인한 뒤 사용 | 사진 설명은 카드 입력에 사용하고 보호자가 원할 때 고치도록 했다. 반복 확인 부담을 줄이되, 설명을 승인된 생애 사실로 자동 저장하지 않는다 | [사진 설명 사용 기준](../architecture/card-generation-flow.md#4-사진-설명은-바로-사용하고-앨범에서-선택적으로-수정) |
| 면회 중 추가 질문을 생성할지 검토 | 첫 질문과 꼬리 질문을 미리 준비했다. 보호자가 필요할 때 바로 꺼내 쓰도록 했다 | 9월 23일 회의 기준. [주제 카드 설계](../architecture/card-generation-flow.md#첫-질문과-꼬리-질문) |
| 일대기를 생애 시기별로 표시 | 시기를 추론하거나 사용자에게 계속 묻는 부담을 고려해, 주제별 분류와 등록순을 먼저 제공했다. 생애 시기별 보기는 출시 이후로 정했다 | 김영석의 [10월 16일 00:09 KST 결정](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/125#issuecomment-6195369719). 이야기 축적과 열람은 현재 기능으로 제공 |
| 사용자가 이야기 분류 선택 | AI가 이야기 후보를 만들 때 분류도 함께 반환하고, 사용자는 잘못됐다고 느낄 때 수정한다. 별도 분류 호출과 필수 선택 단계를 줄였다 | [#125 논의](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/125), [#139](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/issues/139)를 거쳐 11월 10일 [#295](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/295)에서 AI 출력과 승인 저장 연결 |
| 사실을 고칠 때마다 카드 생성 또는 일부 카드 교체 | 정정은 즉시 저장하고, 다음 대화 준비에서 누적 정정을 반영해 12장을 한 번에 다시 만든다. 사용자가 수정할 때마다 생성 비용과 대기를 반복하지 않도록 했다 | 김영석의 [10월 31일 02:50 KST 회의 결정 확인](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/161#issuecomment-6529648361). #171 앱과 #161 서버에 반영 |
| 이야기 삭제를 추천 비선호로 해석 | 삭제한 이야기는 새 입력에서 빼고, 추천 제외는 보호자가 명시적으로 선택했을 때 적용한다 | [10월 22일 멘토링 후 PM 변경](mentoring-followup-20261022.md#삭제와-추천-제외의-구분). 삭제 이유를 임의로 추측하지 않는 방향 |
| 화자 라벨이 부족하면 생성 차단 | 듣기만 한 참여자, 입력 인원 오류와 불완전한 화자 분리를 고려해 문맥으로 리포트와 후보를 만들고 보호자가 확인한다. 같은 전사로 재요청해도 계속 막히는 문제를 줄였다 | 이문영의 [#251 최종 설명, 11월 6일 17:40 KST](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/251#issuecomment-6680822233). 인물 관계의 단정은 후속 [#320](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/320)에서 보완해 11월 10일 23:53 KST에 병합 |

이러한 변경은 면회 준비, 이야기 기록과 다음 추천이라는 목적을 유지하면서 구현 방식과 사용자 부담을 조정한 것이다. 출시 이후로 미룬 기능과 현재 방식으로 대체한 기능은 별도로 구분한다.

## 3. 핵심 사용을 보완한 개발

| 보완 | 사용자가 얻는 도움 | 반영 근거 |
| --- | --- | --- |
| 짧은 음성 입력과 사진 설명 수정 | 긴 글을 쓰는 부담을 줄이고, 잘못된 사진 설명을 직접 바로잡을 수 있다 | [짧은 전사 #214](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/214), [설명 저장 #205](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/205) |
| 첫 카드 생성 전 사진 분석 대기 | 방금 등록한 사진을 첫 대화 카드에서도 활용한다 | [#294](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/294) |
| 분석 재요청, 녹음 복구와 파일 공유 | 한 번 실패했다고 면회 기록을 포기하거나 처음부터 다시 녹음하는 일을 줄인다 | [#213](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/213), [#262](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/262), [#296](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/296) |
| 30분 초과 녹음 분할 전사 | 긴 면회도 서버에서 나눠 처리하고 결과를 합친다 | [#299](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/299), 11월 10일 운영 BE 배포에 포함 |
| 리포트 완료 알림과 지난 카드 좋아요 | 분석을 기다리며 앱을 계속 볼 필요를 줄이고, 좋았던 질문을 다음 준비에 활용한다 | [알림 #247](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/247), [발송 #249](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/249), [지난 카드 #162](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/162), [좋아요 #177](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/177) |
| 이야기 자동 분류와 아픈 기억 표시 | 보호자가 모든 이야기를 직접 분류하지 않아도 되고, 다루기 어려운 기억을 보고 선택할 수 있다 | [#295](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/295), [일대기와 카드 연결 #297](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/297) |
| 접근성, 자동 검사와 승인 배포 | 화면을 읽고 조작하는 불편을 줄이며, 변경 후에도 핵심 흐름이 이어지는지 반복 검사한다 | [접근성 #266](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/266), [앱과 BE E2E #258](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/258), [승인 배포 #256](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/256) |

## 4. 검증과 실제 사용에서 개선한 내용

### 핵심 흐름과 출력 검증

| 검증 | 결과 | 근거와 조건 |
| --- | --- | --- |
| 실제 외부 연결과 다음 면회 순환 | 실제 S3, STT와 생성 모델로 API 및 에뮬레이터 흐름을 실행하고, 이야기 승인과 다음 카드 반영을 확인했다 | 11월 4일 합성 대화 시험. [멘토 심사 근거표 3번과 8번](mentor-evidence.md) |
| 운영 안정성 시험 | 리포트 대상 녹음 35회 모두 완료, 사진 86건 분석 완료, 리포트 알림 39건 수신 | 11월 8일 순차 실행. 녹음 업로드부터 리포트까지 중앙값 18.5초, 사진 설명 중앙값 12.5초. [시험 기록](../../backend/docs/stability-test-20261108.md) |
| 실제 면회 녹음의 생성 결과 개선 | 같은 녹음에서 리포트 309자와 이야기 후보 2개였던 결과를 화제별 약 1,400자와 후보 14개로 보완하고 자동 분류를 확인했다 | 11월 9일 허가받은 녹음 1건 비교. [검증 보고](real-visit-validation-20261109.md), [#295](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/295) |
| 실사용자의 이야기 누적과 재사용 | 첫 면회의 리포트, 이야기 2개 저장, 다음 카드 2장의 해당 이야기 재사용을 확인했다 | 11월 10일 [실사용 보고 #314](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/314). 같은 시험에서 첫 카드의 개인화 부족과 두 번째 회차의 빈 전사도 기록 |
| 프롬프트 인젝션 시험 | 이야기, 사진 설명과 전사 등에 넣은 지시를 실제 GPT-6 Luna 출력 28회 모두 따르지 않았다고 보고했다 | 11월 10일 [시험 보고 #316](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/316). 사진 속 글자를 직접 읽는 분석 단계는 시험 범위 밖 |
| 변경 후 자동 회귀 검사 | Python 정적 검사, BE와 PostgreSQL, 앱과 BE E2E, Flutter, AI, STT 6개 작업 성공 | develop `951307b9`의 [CI 실행](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/actions/runs/42838809211), 11월 11일 00:10 KST 완료. E2E의 외부 서비스는 합성 응답을 사용 |

### 발견한 문제와 후속 결과

- **무음과 소음에서 STT가 말을 지어낸 문제:** 11월 8일 시험 뒤 [#267](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/267)에서 구간별로 나뉜 알려진 문장과 5분 음성 입력 경계 오류를 수정했다. 이어 [#276](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/276)에서 VAD와 반복 억제 옵션을 적용했다. 비교 시험의 말소리 없는 녹음 21개에서 지어낸 말이 나온 경우는 기존 9개에서 2개로 줄었다. 일부 짧은 말을 놓치는 한계는 함께 기록했다. [전사 옵션 비교](../../stt-server/docs/vad-condition-comparison-20261109.md)
- **감사 인사만 남은 녹음:** “감사합니다”를 일괄 제거하면 실제 대화도 버리므로, PM은 이 정도의 오탐을 허용하기로 했다. 이미 해결한 문장 필터 문제와 구분한다. [운영 시험의 후속 결정](../../backend/docs/stability-test-20261108.md#발견한-문제)
- **너무 짧은 리포트와 적은 이야기 후보:** [#295](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/295)에서 화제별 요약, 현재 생각과 계획을 포함한 이야기 추출, 분류 저장을 보완했다. 아픈 기억 표시는 [#297](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/297)에서 일대기와 카드에 연결했다.
- **화면 잠금과 다른 앱 사용 중 녹음:** 이서형이 11월 10일 21:09 KST에 녹음 지속과 제출, 중단 안내 후 재개, 강제 종료 후 파일 복구를 실기기에서 확인했다고 보고했다. 화면 보완과 테스트 1,176개 통과도 함께 보고했다. [#302 댓글](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/302#issuecomment-6766923753). 구현과 실기기 확인 기록이 있으며 병합을 기다리는 상태다.

11월 10일 실사용 참여자는 PM 설명상 중증 치매 사례로, 대화를 이어 가기 어려웠다. 경도인지장애와 경도 치매 보호자를 먼저 대상으로 정했던 개발 방향과 일치하는 관찰이다. 최초 카드의 개인화와 짧은 단어 단서 제공은 개선 과제로 남겼다. 해당 관찰을 대상 전체의 사용성이나 효과로 확대하지 않는다.

## 5. 코드와 배포 상태

| 구분 | 11월 11일 00:28 KST 확인 상태 |
| --- | --- |
| develop | `951307b9dfc8862f38673fb57e469a175807f110`. #320 이야기 맥락, #321 사진 설명 보완과 #322, #323 협업 규칙 문서를 포함 |
| 확인한 운영 BE 배포 | 11월 10일 14:37 KST 완료한 [Deploy 실행](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/actions/runs/42762899876)에서 `a855c87e` 배포. DB 백업과 격리 복원, migration, 컨테이너 교체 및 사후 점검 성공. DB revision `5d2e8b1c9a47`. 이후 #320과 #321의 운영 배포 기록은 확인되지 않음 |
| GitHub APK | [release](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/releases/tag/release)의 `saerok-b6bd248a-prod-release.apk`, 11월 10일 18:01 KST 갱신. 이 앱 파일에 열린 앱 PR이 포함된 것은 아님 |
| main 통합 | [#230](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/230) 검토 중. 운영 BE 배포와 main 병합은 별도 절차 |

### 최근 병합된 AI 보완

- **이야기 후보의 인물 관계와 사건 맥락:** 김영석의 [#320](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/320)이 11월 10일 23:53 KST에 병합됐다. 프롬프트를 보완하고 AI 테스트 215개 통과를 보고했다. 실제 모델 비교는 별도 출력 한도를 쓴 단일 시험이며 관계 오류가 일부 남았다.
- **사진 설명의 인물별 특징과 행동:** 김영석의 [#321](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/321)이 11월 10일 23:54 KST에 병합됐다. AI 테스트 215개와 Linux BE 관련 테스트 54개 통과를 보고했다. 사진 5장 모델 시험에서 일부 오류 개선과 남은 세부 오류를 기록했다.

### 구현 후 검토 중인 보완

아래 작업은 구현 PR이 열려 있고, develop에 합치기 전 검토와 통합이 남아 있다. 각 작성자의 검사 보고와 미확인 범위를 함께 표시했다.

| 작업 | 작성 및 확인 상태 | PR |
| --- | --- | --- |
| 녹음 상태, 권한, 카드 조작, 입력과 큰 글자 개선 | 김영석의 수정 PR 검토 중. 이서형이 #302에 추가 수정과 실기기 확인 결과를 남김 | [#300](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/300)~[#313](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/313) |
| 짧은 음성 전사 대기 시간과 서버 전체 요청 상한 | 김민혁이 수정안과 테스트를 제출. 선택적 전체 요청 상한 적용은 PM 검토 대상 | [#317](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/317) |
| 카드에 사용한 사진 확대 | 김영석이 확대 화면, 녹음 상태 표시와 화면 검사를 제출 | [#318](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/318) |
| 정보가 적은 프로필의 일반 질문 개선 | jsut21이 카드 프롬프트 v3와 BE 기본값 변경을 제출. 실제 GPT-6 Luna로 v2와 v3 각 6회 비교를 보고했으며, BE 기본값 변경 검토 요청 | [#324](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/324) |
| 카드 생성 단계별 검증 도구 | jsut21이 시뮬레이션 입력을 BE 규칙과 맞추고 탐색, 비교, 선정과 작성 기록 화면을 제출. AI 테스트 131개와 1회차 시뮬레이션 확인을 보고 | [#325](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/325) |
| 프로필과 이야기의 사진 선택 | 김민혁이 앨범 사진을 이 기기에만 저장하는 기능을 제출. Flutter 테스트 1,153개 통과 보고. 실제 앨범 선택과 자동 백업 제외 확인은 남음 | [#326](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/326) |
| 생성 모델의 일시적 오류 재시도 | 이문영이 최대 1회 재시도와 엘리스 Claude 연결 준비를 제출. PR 본문은 비어 있으며 연결된 설계 문서에 합성 검사 결과를 기록. 재시도는 기본 비활성이고 실제 모델 호출과 자동 전환은 미검증 | [#327](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/327) |

실사용 보고 [#314](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/314)와 인젝션 시험 보고 [#316](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/316)도 문서 PR로 열려 있다. 보고서 병합 여부와 해당 시험의 실행 기록은 구분한다.

## 6. 후속 계획과 남은 차이

### 이미 방향을 정한 항목

- **생애 시기별 보기:** 출시 이후 확장. 현재 일대기는 주제별 분류, 등록순과 최근 이야기로 제공한다.
- **승인한 이야기 정정:** 현재는 일대기에서 직접 수정하고 다음 카드 준비에 반영한다. 승인 이력을 원클릭으로 복원하는 방식과 구분한다.
- **면회 중 실시간 질문 생성:** 현재 MVP에서 제외하고 미리 만든 질문과 보충 카드를 쓴다.
- **분석 실패 시 처리:** 소감은 유지하고, 사용할 수 있는 전사나 녹음으로 재요청한다. 소감만으로 정상 리포트를 완성하는 별도 기능은 확정한 범위가 아니다.

### 현재 제품에 없는 초기 구상과 검토안

| 항목 | 현재 정리 |
| --- | --- |
| 발화량과 응답 지연 등의 수치 | 초기 구상에는 있으나 현재 리포트는 대화 요약과 보호자 평가 중심이다. 수치 기능이 구현됐다고 설명하지 않는다 |
| 거절한 이야기 후보의 30일 복구 | PM 설계에는 남아 있으나 복구 API와 화면은 연결되지 않았다. 승인된 이야기 직접 수정과 별개의 기능으로 남아 있다 |
| 3회마다 중간평가와 대화별 추가 질문 | 10월 22일 PM 변경안에 추가하고 리더 검토 후 구현 범위를 정하기로 한 항목이다. 기존 매회 평가와 제안 확인은 구현돼 있으며, 추가 질문은 별도로 관리한다 |
| 이야기별 실제 사진 연결 | develop의 일대기는 기본 그림을 사용한다. #125의 조건부 후속 계획에 해당하는 기기 내 사진 선택 구현이 [#326](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/326)으로 제출돼 검토 중이다. 서버 사진 연결과 기기 간 공유는 포함하지 않으며, 카드 근거 사진 확대 #318과도 다른 기능이다 |

첫 카드의 개인화, 긴 녹음 분할의 실제 연결 재시험과 여러 사용자 동시 사용은 다음 품질 확인 항목이다. 정보가 적을 때의 일반 질문은 #324에서 보완 중이며, 입력한 개인 정보를 충분히 사용하는지는 별도 확인 항목으로 남긴다. 장기간 사용 효과는 후속 사용자 평가에서 확인한다. 기능 구현과 실제 효과 검증은 각각의 결과로 기록한다.

## 7. 개발 충실성에 대한 종합 정리

새록은 면회 전 준비, 녹음과 분석, 보호자 확인, 일대기 축적과 다음 추천이라는 핵심 흐름을 구현했다. 개발 중 바뀐 방식은 서버 성능, 대화 중 대기와 입력 부담, 실제 사용 결과를 고려한 결정이며, 관련 논의와 코드가 남아 있다.

추가 개발도 음성 입력, 사진 설명 수정, 정정 반영, 녹음 복구, 완료 알림과 접근성처럼 핵심 사용을 돕는 기능에 집중했다. 검증에서 발견한 문제는 수정 PR, 실제 출력 비교와 실기기 확인으로 이어졌다.

심사 근거는 **최종 합의한 핵심 기능의 연결, 변경 이유, 반복 검사와 실사용 개선 기록**이다. 초기 구상과의 차이, 출시 이후 계획, 검토 중인 구현은 위에서 각각 구분했다.

---

근거는 최초 테크스펙, 현행 PM 기준, 코드, 관련 PR 본문과 댓글 및 실행 기록이다. 이번 문서 개정에서는 제품 테스트나 운영 서버 접속을 새로 하지 않았으며, 각 시험은 본문에 적은 실행자와 조건의 기록을 인용했다. 실제 사용자 이름, 계정, 전사문과 리포트 전문은 포함하지 않았다.
