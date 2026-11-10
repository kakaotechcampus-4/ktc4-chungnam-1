# 이전 보안 점검 26건의 최종 처리 상태

작성일: 2026-11-11, KST. [최종 보고서](README.md), [남은 작업](follow-up.md).

## 판정과 집계 기준

11월 8일 run-2의 commit `42938250d87b6e6273d368ba4127af729cc95ea8`에서 기록한 확정 문제 4건과 조건부 확인 22건을 소스 스냅샷 `951307b9dfc8862f38673fb57e469a175807f110` 및 날짜가 있는 수정 기록과 대조했다. 게시 전 #317의 병합을 확인해 14번 설명을 갱신했다. 이후 앱 UX, 카드 v3와 LLM 재시도의 전체 보안 재검토는 별도다.

이 표는 기존 지적의 처리 이력이다. 새 공격 재현을 하지 않았으므로 과거 심각도를 현재 운영 환경에 그대로 부여하지 않는다. 번호 하나당 최종 분류 하나만 적용한다.

| 최종 분류 | 건수 | 번호 |
|---|---:|---|
| 직접 경로 수정 병합 | 7 | 03, 05, 07, 09, 10, 11, 14 |
| 일부 보완 | 3 | 06, 08, 26 |
| 기존 원인 코드 잔존 | 3 | 13, 22, 23 |
| 조건부 확인 | 6 | 02, 04, 12, 16, 21, 25 |
| PM 보류 | 1 | 15 |
| 팀 수정 범위 제외 | 4 | 01, 17, 19, 24 |
| 현재 추가 수정 없음 | 2 | 18, 20 |
| 합계 | 26 | 당시 확정 4, 조건부 22 |

확정 4건 중 03번은 관련 수정이 병합됐고 Caddy 적용 기록도 있다. 13, 22, 23번은 과거 재현 원인이 소스에 남아 있다. 조건부 22건의 현재 분류는 수정 6, 일부 보완 3, 조건부 6, PM 보류 1, 제외 4, 현재 추가 수정 없음 2건이다.

## 항목별 근거

| 번호 | 이전 지적 | 11월 8일 판정 | 최종 분류 | 수정과 남은 조건 |
|---|---|---|---|---|
| 01 | 로컬 시뮬레이션의 Host/Origin 제한 | 당시 검증 필요 | 팀 수정 범위 제외 | PM이 11월 9일 팀 제품 코드의 이번 수정 대상에서 제외. 고쳤다는 뜻은 아님. [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/ai/simulation/web.py) |
| 02 | 외부 Android intent와 내부 재시도 경로 | 당시 검증 필요 | 조건부 확인 | Manifest에는 MAIN/LAUNCHER만 있고 VIEW/BROWSABLE은 없음. 다른 설치 앱의 명시 intent, Flutter 전달, 로그인/선택 프로필 유지와 자동 요청 조합은 실행 검증 필요. 일반 웹링크나 무인증 공격으로 단정하지 않음. [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/app/lib/app/router.dart) |
| 03 | 인증 전 multipart 무제한 수신 | 당시 확인 | 직접 경로 수정 병합 | #278이 본문 해석 전 토큰 검사와 실제 수신 바이트 제한을 추가. Caddy 제한도 11월 9일 적용 기록 있음. [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/backend/app/api/body_limits.py) |
| 04 | 중단된 S3 multipart 조각 잔존 가능성 | 당시 검증 필요 | 조건부 확인 | 완료 전 multipart part는 객체 삭제와 별도. 11월 8일 lifecycle은 없었지만 잔존 part는 0개였음. 현재 잔존 여부와 중단 후 자동 정리 범위는 미확인. [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/backend/app/services/audio_storage.py) |
| 05 | 대기 카드 작업의 잘못된 기한 만료 | 당시 검증 필요 | 직접 경로 수정 병합 | #286이 worker 실행 중 상태와 미선점 대기를 구분. [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/backend/app/services/card_generation_jobs.py) |
| 06 | 원문 생성 로그와 무제한 입력 확대 | 당시 검증 필요 | 일부 보완 | #291 원문 제거/과거 행 변환, #282 입력 상한. 로그 전체 누적량/보관기한은 별도. [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/backend/app/services/card_generation_log.py) |
| 07 | 사진 AI 철회 후 저장 설명 재사용 | 당시 검증 필요 | 직접 경로 수정 병합 | #288 저장 AI 설명 삭제/호출 전 재확인, #291 삭제 근거 제외. 과거 카드의 파생 문장까지 전부 지우는 것은 아님. [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/backend/app/services/photo_analysis_pipeline.py) |
| 08 | 계정별 카드 생성 예산 없음 | 당시 검증 필요 | 일부 보완 | 입력 수/길이, 턴/시간 제한은 있으나 계정별 일일 호출량/금액 상한 없음. [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/backend/app/services/card_sets.py) |
| 09 | unknown kid 재조회와 DB 연결 점유 | 당시 검증 필요 | 직접 경로 수정 병합 | #290 인증을 DB 앞에 이동하고 공개키 조회 공유/유효 캐시 재조회 간격 적용. [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/backend/app/services/google_identity.py) |
| 10 | 계정별 푸시 기기 무제한 | 당시 검증 필요 | 직접 경로 수정 병합 | #285 계정별 기기 5개 제한과 동시 등록 보호. [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/backend/app/services/push_devices.py) |
| 11 | 리포트 새 작업 ID로 재시도 한도 초기화 | 당시 검증 필요 | 직접 경로 수정 병합 | #285 면회별 3회 한도로 변경. [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/backend/app/services/speech_analysis_jobs.py) |
| 12 | 빠른 음성 삭제의 완료 확인/버전 처리 | 당시 검증 필요 | 조건부 확인 | 면회 음성의 빠른 경로는 DeleteObject 후 상태 기록. 짧은 전사는 삭제 성공 후에도 대기열을 유지해 일반 실행기의 HEAD 404 확인을 거침. 11월 8일 음성 버킷 NeverEnabled로 당시 버전 잔존 조건은 없었음. 현재 설정은 미조회. [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/backend/app/services/speech_analysis_pipeline.py) |
| 13 | 짧은 STT의 동기 WAV 파싱 | 당시 확인 | 기존 원인 코드 잔존 | 기존 confirmed의 원인 존속. 최초 검사는 스레드로 넘기지만 짧은 전사의 async 함수에서 동기 wave.open 재검사를 함. #285 동시 2건 제한과 별개. 이번에는 재현하지 않음. [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/backend/app/services/speech_transcription.py) |
| 14 | 짧은 STT의 계정별 무제한 동시 요청 | 당시 검증 필요 | 직접 경로 수정 병합 | #285 계정별 2건. #317은 11월 11일 02:15 KST 병합됐으며 짧은 대기 기본값 90초와 선택적 전역 상한을 추가했다. 전역 상한 기본값은 제한 없음. [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/backend/app/services/account_slots.py) |
| 15 | S3 삭제 실행기 자동 실행 없음 | 당시 검증 필요 | PM 보류 | 삭제 큐/도구 구현. PM이 시험 자료 보존을 위해 실행과 예약을 출시 전 처리로 보류. [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/backend/app/workers/storage_deletion.py) |
| 16 | 과거 DB 복원 시 탈퇴/철회/폐기 재적용 | 당시 검증 필요 | 조건부 확인 | 자동 복원 금지와 사전 승인 절차는 있음. 승인한 과거 백업을 복원할 때 이후의 탈퇴/철회/토큰 폐기를 재적용하는 자동 절차는 미구현. 실제 개인정보 부활 사건을 확인한 것은 아님. [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/backend/docs/release-safety.md) |
| 17 | 운영진 AWS 배포 역할의 관리 범위 | 당시 검증 필요 | 팀 수정 범위 제외 | AWS는 운영진 관리 영역으로 팀 수정 범위에서 제외했다. 설정 확인 후보를 팀 미해결 취약점으로 집계하지 않는다. [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/.github/workflows/deploy.yml) |
| 18 | develop의 미검토 배포 로직 사용 가능성 | 당시 검증 필요 | 현재 추가 수정 없음 | 기존 PM 승인, main/develop 배포 범위와 본인 승인 허용을 유지한다. 이번 보고서로 새 강제 승인 규칙을 추가하지 않는다. [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/.github/workflows/deploy.yml) |
| 19 | 운영자 PAT의 팀 workflow 접근 | 당시 검증 필요 | 팀 수정 범위 제외 | 운영진 관리 토큰으로 팀 보안 이슈에서 제외한다. 값이나 상세 설정을 이 문서에 싣지 않는다. [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/.github/workflows/assign-mentor.yml) |
| 20 | 업로드 서명키와 비검토 빌드 | 당시 검증 필요 | 현재 추가 수정 없음 | 11월 11일 저장소, production 환경과 저장소에 제공되는 조직 시크릿 목록에 ANDROID_UPLOAD 키가 없었다. 실제 키 유출 근거 없음. 키 누락 시 debug 서명 경고와 모드 표시가 있다. APK가 서명되지 않았다는 뜻은 아니다. [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/.github/workflows/release-build.yml) |
| 21 | STT 오류 로그의 presigned URL | 당시 검증 필요 | 조건부 확인 | 다운로드 오류의 cause가 원래 URL을 보유하는 경로는 남음. 실제 운영 로그 노출은 이번에 확인하지 않음. BE 로그 개선과 STT 예외 체인을 구분. [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/stt-server/src/stt_server/audio/providers.py) |
| 22 | STT 강제 종료 후 임시 음성 잔존 | 당시 확인 | 기존 원인 코드 잔존 | 기존 confirmed. 정상 finally 정리는 있어도 강제 종료/재시작 정리 경로는 확인되지 않음. BE 조각 정리와 다른 저장 위치. [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/stt-server/src/stt_server/audio/providers.py) |
| 23 | WAV 중복 fmt의 검증/디코더 해석 차이 | 당시 확인 | 기존 원인 코드 잔존 | 기존 confirmed. Python 검증과 실제 디코더 해석 차이를 해결한 변경 없음. [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/stt-server/src/stt_server/audio/validation.py) |
| 24 | STT API의 호출자 인증/네트워크 접근 | 당시 검증 필요 | 팀 수정 범위 제외 | 11월 11일 AWS worker의 Tailscale 기본 주소, worker 실행과 GPU peer 온라인을 확인했다. PM은 기존 사설망 운영을 유지하기로 했다. 접근 우회나 공개 노출을 확인한 것이 아니며 GPU ACL 전수 검증 완료로 바꾸어 기록하지 않는다. [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/stt-server/src/stt_server/main.py) |
| 25 | 모델의 고정되지 않은 revision/체크포인트 로딩 | 당시 검증 필요 | 조건부 확인 | 모델 revision의 불변 SHA 고정 확인 안 됨. CK offline 설정은 있으나 주 서버 캐시/다운로드 정책 미확인. [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/stt-server/src/stt_server/main.py) |
| 26 | 호출자 timeout 후에도 GPU 작업 계속 | 당시 검증 필요 | 일부 보완 | 요청 시작 전 만료와 24시간 초과 검사, #299 긴 음성 분할은 있음. 잠금 대기 이후/실행 중 기한 재확인과 호출자 취소의 작업 중단 전파가 남은 범위. [코드](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/blob/951307b9dfc8862f38673fb57e469a175807f110/stt-server/src/stt_server/stt/service.py) |

수정 병합 7건은 지적한 직접 경로의 조치다. 모든 파생 사본, 운영 설정과 실패 조건까지 해결했다는 뜻은 아니다. 예를 들어 사진 AI 설명 재사용 차단은 과거 카드의 문장 삭제와, 계정별 동시 수 제한은 일일 금액 제한과 구분한다.

## 구분해서 읽을 항목

- 백업 정리 timer는 11월 9일 적용 기록이 있다. S3 삭제 실행기의 자동 운영은 PM 보류다.
- 사진 AI 설명 삭제, 원본 객체 삭제와 이전 버전 삭제는 서로 다른 작업이다.
- BE 임시 조각과 STT 다운로드 임시 파일은 저장 위치와 프로세스가 다르다.
- STT 파일 처리 3건과 Tailscale 연결은 별개다. 기존 사설망 운영은 이번 수정 대상에서 제외했다.
- GitHub 배포 승인 절차 유지와 운영진 관리 항목의 범위 제외를 새 보안 수정으로 세지 않는다.
- 범위 제외와 현재 추가 수정 없음은 취약점 수정 완료를 뜻하지 않는다.
- 제품 CI와 합성 E2E는 현재 외부 서비스의 안전성을 전부 입증하지 않는다.
- 프롬프트 인젝션 저항성과 가족 관계 및 사진 설명의 사실 정확성은 별도 평가다.

11월 8일 점검은 commit `42938250d87b6e6273d368ba4127af729cc95ea8`을 대상으로 확정 4건과 조건부 22건을 기록했다. 이 표에는 항목과 현재 코드 근거를 남겼고, 개인 환경의 재현 원본과 설정 조회 기록은 공개 저장소에 싣지 않았다. 관련 수정의 작성자와 병합 시각은 [PR 이력](pr-history.md)에서 확인한다.
