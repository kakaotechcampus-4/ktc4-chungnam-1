# 보안 점검에서 찾은 항목과 처리 결과

11월 8일 점검에서는 시험으로 확인한 문제 4개와 추가 확인 후보 22개를 기록했다. 이 문서는 그 26개가 어떻게 처리됐는지 설명한다. [최종 보고서](README.md), [남은 작업](follow-up.md).

당시 시험으로 확인한 문제는 로그인 전 큰 파일 수신, 짧은 음성 파일 재검사, STT 강제 종료 후 임시 파일 잔존, WAV 파일 해석 차이였다. 이 중 큰 파일 수신에는 수정 코드와 서버 제한 적용 기록이 있다. 나머지 3개는 원인 코드가 남아 있다. 최신 운영 환경에서 다시 시험한 결과는 아니다.

아래는 항목을 처리 상태별로 나눈 표다. 같은 항목을 두 곳에 넣지 않았으며 합계는 26개다.

## 수정 코드가 병합된 항목 7개

| 확인했던 내용 | 처리 결과와 남은 범위 | 코드 |
|---|---|---|
| 로그인 확인 전에 큰 파일을 계속 받는 문제 | #278에서 파일을 해석하기 전 로그인 정보와 실제 받은 크기를 검사하도록 수정했다. 서버 앞단의 크기 제한도 11월 9일 적용 기록이 있다. | [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/backend/app/api/body_limits.py) |
| 순서를 기다리는 카드 작업을 실패로 처리 | #286에서 아직 시작하지 않은 작업과 실행 중인 작업을 구분했다. | [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/backend/app/services/card_generation_jobs.py) |
| 사진 분석 동의를 철회해도 AI 설명을 다시 사용 | #288에서 저장된 AI 설명을 지우고 호출 전 동의를 재확인한다. #291은 삭제된 근거를 새 카드 입력에서 제외한다. 과거 카드에 이미 들어간 문장까지 전부 지우는 기능은 별도다. | [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/backend/app/services/photo_analysis_pipeline.py) |
| 잘못된 로그인 정보가 반복 조회와 DB 연결을 차지 | #290에서 로그인 검사를 DB 연결보다 먼저 수행한다. Google 공개키의 동시 조회를 합치고, 유효한 저장 키가 있을 때 모르는 키를 다시 조회하는 간격을 제한한다. | [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/backend/app/services/google_identity.py) |
| 한 계정에 알림 받을 기기를 계속 추가 | #285에서 계정별 5대로 제한하고 동시에 등록해도 한도를 검사한다. | [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/backend/app/services/push_devices.py) |
| 리포트 작업을 새로 만들면 재시도 횟수가 초기화 | #285에서 작업 번호 대신 면회를 기준으로 3회까지 재요청하도록 바꿨다. | [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/backend/app/services/speech_analysis_jobs.py) |
| 한 계정이 짧은 음성 변환을 동시에 계속 요청 | #285에서 계정별 동시 2개로 제한했다. #317은 11월 11일 02:15 KST 병합됐으며 대기 기본값 90초와 선택적 서버 전체 상한을 추가했다. 전체 상한은 기본적으로 꺼져 있다. | [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/backend/app/services/account_slots.py) |

## 수정이 남은 음성 파일 처리 문제 3개

| 확인했던 내용 | 처리 결과와 남은 범위 | 코드 |
|---|---|---|
| 짧은 음성 파일의 두 번째 검사로 요청 처리가 지연 | 최초 검사는 별도 작업 흐름에서 처리하지만, 다시 WAV를 읽는 부분은 요청 처리 흐름을 붙잡을 수 있다. 이 부분의 수정이 남아 있다. | [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/backend/app/services/speech_transcription.py) |
| STT 강제 종료 후 임시 녹음이 남음 | 정상 종료 때는 임시 파일을 지운다. 강제 종료 후 남은 파일을 재시작 때 정리하는 처리는 확인되지 않았다. 일반 서버가 만든 음성 조각과는 다른 위치의 파일이다. | [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/stt-server/src/stt_server/audio/providers.py) |
| 음성 파일 검사와 실제 해석 결과가 다름 | 형식 정보가 중복된 비정상 WAV를 검사 도구와 실제 음성 처리 도구가 다르게 해석하는 문제다. 이 차이를 해결한 변경은 확인되지 않았다. | [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/stt-server/src/stt_server/audio/validation.py) |

## 일부 보완했고 추가 작업이 있는 항목 3개

| 확인했던 내용 | 처리 결과와 남은 범위 | 코드 |
|---|---|---|
| 생성 로그에 원문이 쌓이고 입력 자료가 계속 커짐 | #291에서 원문을 로그에서 제거하고 과거 기록을 바꾸는 처리를 추가했다. #282에서 입력 상한을 뒀다. 로그 전체 보관기한과 누적량 제한은 남아 있다. | [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/backend/app/services/card_generation_log.py) |
| 하루 동안 반복 사용하는 AI 비용에 상한이 없음 | 입력 수와 길이, AI 호출 단계와 대기 시간은 제한한다. 계정별 하루 생성 횟수나 금액 제한은 별도다. | [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/backend/app/services/card_sets.py) |
| 요청이 끝나도 GPU가 계속 음성을 처리할 수 있음 | 작업 시작 전 만료와 24시간 초과 검사, 긴 음성 분할은 있다. 실행 순서를 기다린 뒤의 재확인과 처리 중 취소 전달은 보완할 범위다. | [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/stt-server/src/stt_server/stt/service.py) |

## 문제가 생기는 조건을 더 확인할 항목 6개

| 확인했던 내용 | 처리 결과와 남은 범위 | 코드 |
|---|---|---|
| 다른 앱이 새록의 내부 화면을 열어 요청할 가능성 | 일반 웹링크를 받는 설정은 없고 로그인과 선택한 프로필이 필요하다. 다른 설치 앱이 특정 화면을 직접 열었을 때 실제 요청까지 이어지는지는 확인해야 한다. | [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/app/lib/app/router.dart) |
| 중간에 끊긴 큰 파일 업로드 조각이 남을 가능성 | 파일을 여러 조각으로 나누어 올리다 중단되면 완성 파일과 별도로 정리해야 한다. 11월 8일 조회에서는 조각이 0개였으며 현재 잔존을 확인한 것은 아니다. | [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/backend/app/services/audio_storage.py) |
| 음성 삭제 요청 성공 후 파일이 정말 없어졌는지 확인 | 면회 음성의 빠른 삭제는 삭제 요청 성공 뒤 상태를 기록한다. 짧은 음성 변환은 별도 삭제 목록을 남겨 파일이 없다는 응답까지 확인한다. 11월 8일 음성 저장소에는 이전 버전 보관이 꺼져 있었고 현재 설정은 재조회하지 않았다. | [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/backend/app/services/speech_analysis_pipeline.py) |
| 예전 백업 복원 후 탈퇴와 동의 철회를 다시 반영 | 복원은 사전 승인이 필요하다. 다만 백업 이후의 탈퇴, 동의 철회와 로그인 정보 폐기를 자동으로 다시 반영하는 절차가 없다. 실제 삭제 자료가 되살아난 사건을 확인한 것은 아니다. | [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/backend/docs/release-safety.md) |
| STT 오류 기록에 임시 파일 접근 주소가 남을 가능성 | 다운로드 오류의 원인 정보에 원래 주소가 남는 코드가 있다. 운영 로그에 그 주소가 실제로 출력되는지는 확인되지 않았다. | [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/stt-server/src/stt_server/audio/providers.py) |
| 음성 모델을 어떤 버전으로 설치하는지 고정 | 학교 CK 예비 서버에는 이미 받은 모델을 쓰는 설정이 있다. 승인한 모델 버전이나 파일 확인값을 고정하는지, 주 서버가 어떻게 내려받는지는 별도 확인이다. | [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/stt-server/src/stt_server/main.py) |

## PM 결정으로 보류했다가 운영에 적용한 작업 1개

| 확인했던 내용 | 처리 결과와 남은 범위 | 코드 |
|---|---|---|
| 저장소 파일 삭제를 자동으로 실행 | 삭제 목록과 실행 도구는 구현됐다. 시험 자료를 보존하기 위해 PM이 실제 실행과 예약을 보류했다가, 11/11 승인으로 [#341](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/341)의 5분 주기 실행과 사진 과거 버전 삭제를 운영에 적용했다([#185](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/issues/185)). | [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/backend/app/workers/storage_deletion.py) |

## 이번 팀 수정 범위에서 제외한 항목 4개

| 확인했던 내용 | 처리 결과와 남은 범위 | 코드 |
|---|---|---|
| 개인 PC에서 사용하는 AI 시험 도구 | PM이 11월 9일 팀 제품의 이번 수정 범위에서 제외했다. 코드가 수정됐다는 뜻은 아니다. | [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/ai/simulation/web.py) |
| 운영진이 관리하는 AWS 배포 권한 | 운영진 관리 영역으로 팀 수정 범위에서 제외했다. 설정 확인 후보를 팀 미해결 취약점으로 집계하지 않는다. | [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/.github/workflows/deploy.yml) |
| 운영진 자동화에 사용하는 공용 토큰 | 운영진 관리 항목으로 팀 보안 이슈에서 제외했다. | [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/.github/workflows/assign-mentor.yml) |
| Tailscale로 연결한 STT 서버 | 기존 사설망 연결과 서버 온라인 상태를 확인했으며 PM 결정에 따라 운영 방식을 유지한다. 공개 노출이나 우회가 확인된 것이 아니며 모든 접근 규칙을 시험한 것도 아니다. | [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/stt-server/src/stt_server/main.py) |

## 현재 추가 수정이 없는 항목 2개

| 확인했던 내용 | 처리 결과와 남은 범위 | 코드 |
|---|---|---|
| 누가 어떤 브랜치를 배포할 수 있는지 | 기존 PM 승인과 main/develop 배포 범위를 유지한다. 이 보고서로 새 승인 규칙을 추가하지 않는다. | [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/.github/workflows/deploy.yml) |
| 앱 업로드 서명키의 노출 가능성 | 11월 11일 확인한 GitHub 비밀 설정에는 업로드 키가 없었다. 키가 없으면 개발용 서명 사용을 경고하고 표시한다. 현재 키 유출 문제로 보지 않으며 향후 등록할 때 접근 범위를 확인한다. | [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/.github/workflows/release-build.yml) |

## 혼동하기 쉬운 부분

- **백업 정리와 음성 파일 삭제**: 백업 정리 예약 작업은 11월 9일 적용 기록이 있다. S3 파일 삭제는 11월 11일부터 5분 주기로 자동 실행된다.
- **사진 설명 삭제와 원본 삭제**: 분석 동의를 끄면 AI 설명을 지우는 것과, 저장소의 사진 및 이전 버전을 삭제하는 것은 다른 작업이다.
- **동시 요청 수와 하루 비용**: 동시에 두 개만 처리해도 하루 종일 반복하면 비용이 쌓인다.
- **인젝션 시험과 사실 정확성**: 자료 속 명령을 따르지 않는 것과 가족 관계나 사진을 정확히 설명하는 것은 별도로 평가한다.
- **수정 병합과 배포**: 변경을 develop에 합친 시점과 실제 앱 또는 서버에 적용한 시점을 구분한다.

## 근거를 확인하는 방법

각 행의 코드 링크는 검토한 버전 `951307b9`에 고정돼 있다. 최초 점검 버전은 `42938250`이다. 짧은 음성 대기와 전체 동시 수 제한은 이후 병합된 #317의 설명을 반영했다. 추가 앱 화면 변경, 카드 프롬프트 3판과 LLM 재시도의 전체 보안 재검토는 별도다.

작성자와 병합 날짜는 [관련 PR 이력](pr-history.md)에 있다. 개인 환경의 재현 원본, 실제 사용자 자료와 설정 조회 기록은 공개 저장소에 싣지 않았다.
