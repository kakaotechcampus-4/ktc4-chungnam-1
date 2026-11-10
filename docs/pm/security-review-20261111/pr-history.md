# 보안 관련 PR 변경 이력

기준: 2026-11-11 02:34 KST 게시 전 확인. 기존 근거 PR 58건에 #324와 #327을 추가해 60건이며 모두 병합 상태다. 모든 병합 시각은 KST다. 작성자는 PR 작성 계정이며 병합자나 운영 설정 적용자를 뜻하지 않는다.

이 표는 이번 조사에서 보안 조치와 연결한 PR이다. 모든 PR을 보안 패치라고 부르지는 않는다. 품질, 운영 안정성과 동의 설명이 보안 경계에 영향을 주는 경우도 포함했다. 각 PR의 현재 동작과 제한은 [본 보고서](README.md)를 기준으로 읽는다.

| PR | 작성자 | 병합 시각(KST) | 상태 | 보안과 연결되는 변경 |
|---|---|---|---|---|
| [#32](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/32) | @lye5615 | 2026-09-18 20:42 | 병합 | 예외 응답과 요청 ID, 민감한 요청/예외 내용의 로그 노출 축소 |
| [#49](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/49) | @lye5615 | 2026-09-19 16:40 | 병합 | Google 공개키 조회와 동의 값 관련 보완 |
| [#82](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/82) | @Sogeum100g | 2026-10-01 03:41 | 병합 | WAV 데이터 누락과 잘린 파일 처리 보완 |
| [#86](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/86) | @Sogeum100g | 2026-10-05 01:16 | 병합 | 서버 로그아웃과 계정 탈퇴 |
| [#92](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/92) | @Sogeum100g | 2026-10-05 14:46 | 병합 | 업로드 사진 형식과 크기 검증 |
| [#119](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/119) | @decmoon05 | 2026-10-15 22:00 | 병합 | 동의 항목과 개인정보 처리 설명 정리 |
| [#134](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/134) | @Sogeum100g | 2026-10-17 22:17 | 병합 | 세션 폐기 이력을 DB에 보존 |
| [#156](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/156) | @Sogeum100g | 2026-10-26 00:59 | 병합 | Android 릴리스 서명 설정과 빌드 경로 |
| [#157](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/157) | @Sogeum100g | 2026-11-07 02:45 | 병합 | 컨테이너 로그 회전 |
| [#174](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/174) | @MoonYoung02 | 2026-11-02 01:13 | 병합 | 주 GPU 연결의 Tailscale 사용 안내 |
| [#175](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/175) | @heychaewong | 2026-11-03 00:43 | 병합 | 앱 재인증과 세션 처리 |
| [#179](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/179) | @heychaewong | 2026-11-03 19:12 | 병합 | 선택 동의 상태와 변경 이력 서버 연결 |
| [#189](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/189) | @decmoon05 | 2026-11-03 14:03 | 병합 | STT 예비 서버 전환 조건, 중복 재전송 제한 |
| [#190](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/190) | @decmoon05 | 2026-11-03 14:04 | 병합 | CK 예비 STT의 제한 SSH 연결 |
| [#193](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/193) | @decmoon05 | 2026-11-05 03:37 | 병합 | 공개 DB readiness의 고정 오류 응답과 내부 읽기 전용 운영 점검 분리 |
| [#194](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/194) | @decmoon05 | 2026-11-05 03:38 | 병합 | 배포 전 DB 백업과 복원 시험 |
| [#197](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/197) | @decmoon05 | 2026-11-05 03:38 | 병합 | 호스트 STT 연결 포트 보호 |
| [#203](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/203) | @decmoon05 | 2026-11-05 03:46 | 병합 | 음성 삭제 실패가 분석 결과를 덮어쓰지 않도록 분리 |
| [#204](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/204) | @decmoon05 | 2026-11-05 04:01 | 병합 | S3 삭제 실행기와 확인 절차 |
| [#211](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/211) | @decmoon05 | 2026-11-05 03:32 | 병합 | PR 제품 시험과 합성 흐름 검사. 실제 앱/BE 통합 E2E 추가는 #258로 구분 |
| [#213](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/213) | @decmoon05 | 2026-11-05 04:02 | 병합 | 실패 전사와 처리 기한 관리 |
| [#223](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/223) | @decmoon05 | 2026-11-05 04:24 | 병합 | 서버 음성과 기기 원본 보관 설명 구분 |
| [#224](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/224) | @decmoon05 | 2026-11-05 03:37 | 병합 | 개인정보 없는 운영 상태 검사 |
| [#227](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/227) | @decmoon05 | 2026-11-05 04:07 | 병합 | BE production 설정에서 docs, redoc, openapi.json 비활성화 |
| [#228](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/228) | @decmoon05 | 2026-11-05 04:07 | 병합 | 서버 음성 보관 상한과 처리 여유 조정 |
| [#240](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/240) | @decmoon05 | 2026-11-05 04:02 | 병합 | 프로필 사진 삭제와 연결 처리 |
| [#249](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/249) | @Sogeum100g | 2026-11-06 17:14 | 병합 | 앱 푸시 선택 동의 연결 |
| [#256](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/256) | @decmoon05 | 2026-11-07 15:46 | 병합 | 수동 배포의 대상 SHA와 실행 조건 검사 |
| [#257](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/257) | @decmoon05 | 2026-11-07 23:34 | 병합 | 사진 AI 분석 동의 연결 |
| [#258](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/258) | @decmoon05 | 2026-11-07 23:34 | 병합 | Flutter 앱 API와 실제 BE/worker/DB를 연결하는 PR E2E 추가. 외부 서비스는 합성 |
| [#260](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/260) | @decmoon05 | 2026-11-08 00:08 | 병합 | 이미 배포된 worker의 제한된 재시작 절차 |
| [#261](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/261) | @decmoon05 | 2026-11-08 02:36 | 병합 | AI 분석 미동의 시 수동 설명 경로 |
| [#263](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/263) | @decmoon05 | 2026-11-08 02:36 | 병합 | 알려진 STT 환각 문장을 제거하고 빈 전사에서 후속 리포트 중단 |
| [#267](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/267) | @decmoon05 | 2026-11-08 16:46 | 병합 | 여러 인접 구간으로 쪼개진 알려진 STT 환각 문장 검사 확대 |
| [#272](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/272) | @decmoon05 | 2026-11-08 22:16 | 병합 | 사진 전송 전 동의 안내 |
| [#276](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/276) | @decmoon05 | 2026-11-09 03:24 | 병합 | VAD 켬, 앞 문장 조건 끔으로 STT 환각 감소. 품질 조치이며 별도 배포 필요 |
| [#277](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/277) | @decmoon05 | 2026-11-09 04:24 | 병합 | 확인 대기 이야기 후보의 오래된 승인 방지 |
| [#278](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/278) | @decmoon05 | 2026-11-09 04:24 | 병합 | 본문 선제 크기 제한과 업로드 사전 토큰 확인 |
| [#279](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/279) | @decmoon05 | 2026-11-09 04:24 | 병합 | 기한 지난 전사와 삭제된 작업의 AI 호출 차단 |
| [#280](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/280) | @decmoon05 | 2026-11-09 04:34 | 병합 | STT 완료 후 정체된 작업의 처리 상태 보완 |
| [#281](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/281) | @decmoon05 | 2026-11-09 13:35 | 병합 | 사진 분석 시각과 삭제 중 경합 처리 |
| [#282](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/282) | @decmoon05 | 2026-11-09 13:35 | 병합 | 프로필/사진/이야기 수와 본문 길이 상한 |
| [#283](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/283) | @decmoon05 | 2026-11-09 13:35 | 병합 | 고아 음성/중단 사진 업로드 삭제 예약 |
| [#284](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/284) | @decmoon05 | 2026-11-09 13:36 | 병합 | 동의 StrictBool과 일회용 가입 토큰 |
| [#285](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/285) | @decmoon05 | 2026-11-09 13:36 | 병합 | 짧은 전사 동시 2건, 푸시 5대, 리포트 재시도 3회 |
| [#286](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/286) | @decmoon05 | 2026-11-09 13:36 | 병합 | worker 대기 카드 작업을 실패로 오인하지 않도록 수정 |
| [#287](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/287) | @decmoon05 | 2026-11-09 13:37 | 병합 | DB 백업 14일 정리와 systemd timer |
| [#288](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/288) | @decmoon05 | 2026-11-09 13:37 | 병합 | 사진 AI 철회 시 저장 설명 삭제와 호출 전 동의 재확인 |
| [#289](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/289) | @decmoon05 | 2026-11-09 13:37 | 병합 | 취소/삭제 후 늦은 카드 결과가 저장되지 않도록 보완 |
| [#290](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/290) | @decmoon05 | 2026-11-09 13:45 | 병합 | 토큰 확인을 DB 앞으로 이동, unknown kid 재조회 결합 |
| [#291](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/291) | @decmoon05 | 2026-11-09 14:23 | 병합 | 카드 생성 로그 원문 제거, 삭제된 근거 제외 |
| [#293](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/293) | @Sogeum100g | 2026-11-10 00:22 | 병합 | 새 개인정보처리방침. 사진 보관과 AI 분석 동의 설명 |
| [#297](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/297) | @decmoon05 | 2026-11-10 11:52 | 병합 | 민감한 이야기 표시를 승인 후보, 저장 이야기, v2 카드로 유지. AI 안전/품질 조치 |
| [#299](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/299) | @decmoon05 | 2026-11-10 12:43 | 병합 | 긴 녹음 30분 분할, 조각 처리와 정리 |
| [#316](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/316) | @decmoon05 | 2026-11-11 02:08 | 병합 | 프롬프트 인젝션 합성 입력 28회 시험 보고서. 새 방어 코드 추가와 구분 |
| [#317](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/317) | @Sogeum100g | 2026-11-11 02:15 | 병합 | 짧은 STT 대기 기본값 90초와 선택적 서버 전체 동시 상한. 전역 상한 기본값은 제한 없음 |
| [#320](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/320) | @decmoon05 | 2026-11-10 23:53 | 병합 | 이야기 후보의 가족 관계/문맥 오인 보완. 품질 조치로 별도 구분 |
| [#321](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/321) | @decmoon05 | 2026-11-10 23:54 | 병합 | 사진 분석의 관찰/추정과 설명 오류 보완. 품질 조치로 별도 구분 |
| [#324](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/324) | @jsut21 | 2026-11-11 02:16 | 병합 | 카드 프롬프트 v3와 BE 기본값 변경. v2 인젝션 시험과 별도 |
| [#327](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/327) | @MoonYoung02 | 2026-11-11 02:18 | 병합 | 일시적 LLM 오류 재시도와 전송 전 조건 재검사. 기본 꺼짐, 운영 자동 전환 미완료 |

## 11월 8일 점검 이후 처리 순서

1. 11월 8일 run-2 점검은 commit `42938250d87b6e6273d368ba4127af729cc95ea8`을 대상으로 4건을 confirmed, 22건을 needs_validation으로 기록했다.
2. 11월 9일 04시대에 #278의 본문 제한과 #279의 전사 기한 보완이 병합됐다.
3. 11월 9일 13시대에 #281~#290의 입력 상한, 고아 파일 삭제 예약, 가입 토큰, 계정별 한도, 큐 상태, 백업 정리, 동의 철회, 토큰/JWKS 보완이 병합됐다.
4. 11월 9일 14:23에 #291의 원문 로그 제거와 근거 삭제 반영이 병합됐다.
5. 11월 9일 20:55~20:56에 Caddy 제한과 백업 정리 timer의 실제 적용 기록이 남았다. PR 병합 시각과 운영 적용 시각을 구분해야 한다.
6. 11월 10일에 처리방침, 긴 녹음 분할, 이야기/사진 품질 보완이 추가됐다.
7. #316은 11월 11일 02:08 KST, #317은 02:15 KST에 병합됐다. 각각 @decmoon05의 합성 입력 시험 보고와 @Sogeum100g의 짧은 STT 대기/상한 보완이다.
8. #324는 02:16 KST, #327은 02:18 KST 병합됐다. 게시 전 변경 이력에 추가했으며 기존 보안 검토 전체를 다시 수행한 것으로 계산하지 않는다.

## 시험 기록을 읽을 때

#278~#291 관련 PR의 테스트 본문과 check 기록을 확인했다. 작성자 로컬 시험 수와 GitHub CI 성공은 출처가 다르다. PR별 전체 시험 수는 대부분 동일 시험을 다시 돌린 수이므로 합산하지 않는다.

- #278: 요청 본문 상한과 chunked/Content-Length 예외 시험.
- #284: 동의 bool 값과 가입 토큰 재사용/동시성 시험.
- #285: 계정 슬롯, 푸시 수, 면회별 재요청 시험.
- #287: 최신 정상 백업 보존, dry-run과 apply, 읽기 실패 처리.
- #288: 사진 동의 철회와 처리 중 경합 시험.
- #290: 인증 전에 DB를 열지 않는 경로별 시험, 공개키 조회 공유.
- #291: 원문 로그 축소와 과거 행 변환 시험.

현재 보고서 작성 중 제품 시험을 다시 실행하지 않았다. GitHub 제품 검사 성공은 별도 보안 스캐너 통과, 운영 설정의 적합성, 모든 외부 서비스 연동의 성공을 의미하지 않는다.
