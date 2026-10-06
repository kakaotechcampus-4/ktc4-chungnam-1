# FE 영역

담당 리더: 이서형. 합성 목 데이터로 화면을 연결한 단계이며 카메라와 서버 연동은 아직 없다. 면회 녹음은 기기에 파일을 남기는 데까지 동작하고 업로드는 없다([면회 녹음](#면회-녹음)). BE 인증 API는 develop에 반영됐지만 앱의 구글 로그인 연결은 [PR #50](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/50)에서 검토 중이다.

- 처음 실행: [환경 세팅](SETUP.md)
- 화면과 접근성: [디자인 기준](DESIGN.md)
- 연동: [공통 데이터 계약](../docs/architecture/data-contracts.md), [목 데이터 원본](../docs/architecture/mock/README.md)
- 제품 결정: [PM 문서](../docs/pm/README.md), [동의 문구](../docs/legal/consent-draft.md), [기능별 동의](../docs/legal/consent-mapping.md)

## 실행과 테스트

`app/`에서 실행한다. 푸시 전에는 정적 검사와 테스트를 모두 실행한다.

| 명령 | 용도 |
| --- | --- |
| `flutter pub get` | 의존성 설치 |
| `flutter run` | 연결된 기기에서 실행. 테스트는 별도 실행 |
| `flutter analyze` | 정적 검사 |
| `flutter test` | 테스트와 목 데이터 원본 비교 |
| `flutter build apk --debug` | 디버그 APK 빌드 |

구글 로그인을 실제로 눌러 보려면 `flutter run` 에 [구글 로그인](#구글-로그인)의 `--dart-define` 둘을 함께 넘긴다. 넘기지 않으면 버튼이 설정 오류만 알린다. 나머지 화면은 값 없이도 그대로 돌아간다.

기존 검증 기록: 2026-09-06, Windows 11과 Galaxy S23+ (SM S916N), Android 15 (API 35), arm64 실기기에서 위 명령과 앱 실행을 확인했다.

## 기술과 화면 기준

| 항목 | 값 |
| --- | --- |
| 대상 / 프로젝트명 | Android 우선 / `saerok` |
| Application ID | `com.saelog.app` |
| Flutter / Dart | 3.44.8 stable / 3.12.2 |
| compileSdk / targetSdk / minSdk | 36 / 36 / 26 |
| JDK / Gradle | 21 (Android Studio 번들) / 9.1.0 |
| Android Gradle Plugin / Kotlin | 9.0.1 / 2.3.20 |
| 상태 관리 / 화면 이동 | `flutter_riverpod` 3.4.3 / `go_router` 18.0.1 |
| 구글 로그인 / HTTP | `google_sign_in` 7.2.0 / `http` 1.6.0 |
| 세션 보관 | `flutter_secure_storage` 11.2.0 |
| 녹음 / 저장 경로 | `record` 7.1.1 / `path_provider` 2.1.6 |
| 기준 화면 | 412 x 917 dp, 세로. 작은 화면과 글자 확대에서도 확인 |

<details>
<summary>버전 선택 이유와 재검토 조건</summary>

- 설치본 Flutter 3.44.8을 개발 기간에 고정하고 SDK 값도 상수로 선언한다.
- `minSdk` 26은 백그라운드 녹음용 포그라운드 서비스 분기를 줄이기 위한 선택이다. Flutter 기본값은 24다.
- JDK, Gradle, AGP와 Kotlin은 Flutter 템플릿의 조합을 유지한다.
- 보안 수정, 배포 정책의 상위 `targetSdk` 요구 또는 `minSdk` 26으로 제외되는 기기 문제가 생기면 재검토한다.
- 상태 관리와 라우팅의 대안 및 선택 이유는 [ADR-005](../docs/architecture/decisions/ADR-005-flutter-state-management-and-routing.md)에 있다.

</details>

## 화면과 경로

[routes.dart](lib/app/routes.dart)에 경로를 선언하고 [router.dart](lib/app/router.dart)에서 화면과 연결한다. 화면 이동은 문자열 대신 `AppRoutes`를 사용한다.

| 경로 | 화면 | 피그마 |
| --- | --- | --- |
| `/splash` | 스플래시 | A-1 |
| `/login` | 로그인 | A-2 |
| `/signup` | 회원가입과 동의 | A-3 |
| `/onboarding` | 처음 오셨네요 | B-1 |
| `/profile/create` | 환자 정보 입력 (7단계). `?adding=<id>`이면 어르신 추가 | B-2 ~ B-8 |
| `/home` | 홈 | HOME, HOME-1 |
| `/cards` | 오늘의 대화 카드 | C-1 ~ C-3 |
| `/visit/photo` | 면회 전 사진 | D-1 |
| `/visit/record` | 녹음 안내와 녹음 중 | E-1, E-2 |
| `/visit/cards/add` | 면회 중 대화 카드 추가 | E-5 |
| `/visit/review` | 보호자 소감 | F-1 |
| `/visit/review/done` | 보호자 위로 | 설계 없음, PM 초안 |
| `/report/:reportId` | 리포트 | G-1 |
| `/report/:reportId/changes` | 변경 사항 확인 | G-2 |
| `/profiles` | 함께하는 소중한 분 (어르신 전환, 추가, 순서, 지우기) | 설계 없음 |
| `/profile` | 프로필 설정 | MYPAGE |
| `/profile/delete` | 회원 탈퇴 확인 | 설계 없음 |
| `/reports` | 리포트 기록 | 설계 없음 |
| `/notifications` | 알림 | 설계 없음 |
| `/album` | 일대기 | H, 기획 보류 안내만 표시 |

면회 중 카드 E-3, E-4는 녹음 화면의 팝업이다. HOME과 HOME-1은 리포트 알림 유무, B-3의 녹음 완료와 B-4의 인식 실패는 음성 입력 상태, C-1 ~ C-3은 카드 펼침과 추가 상태를 나타낸다.

`/notifications`는 홈의 리포트 알림 상태(`ReportNotice`)를 그대로 다시 보여주는 화면이라 지금은 한 번에 한 건만 뜬다. 날짜별로 여러 건이 쌓인 이력을 보여주려면 데이터 모델을 넓혀야 한다.

`/profile`의 로그아웃과 `/profile/delete`의 탈퇴하기는 서버에 연결했다([로그아웃과 탈퇴](#로그아웃과-탈퇴)). `/profile/delete`의 탈퇴 이유 설문은 계약이나 법률 문서에 속한 값이 아니라 화면 문구다. 탈퇴 후 재가입 가능 여부는 `docs/legal/` 어디에도 정해진 내용이 없어 화면에 적지 않았다.

## 현재 사용자 흐름

동의와 프로필 입력 → 대화 카드 선택 → 면회 사진과 녹음 화면 → 보호자 소감 및 평가 → 보호자 위로 → 홈에서 리포트 준비 상태 확인 → 리포트 → 변경 제안 확인. PR #42에서 별도 처리 중 화면을 제거했고, 현재 리포트 생성은 목 타이머로 표시한다. 평가 제출과 변경 제안의 실제 저장은 아직 연결되지 않았다. 보호자 위로 화면은 Q1 대화 만족도(1~5)에 맞춘 고정 문구 5개 중 하나를 보여주고, 서버와 AI를 부르지 않는다. 문구는 [comfort_messages.dart](lib/features/review/comfort_messages.dart)에 있다. 화면별 상세 경로는 위 표를 따른다.

알림 수신은 선택이며 거부해도 가입과 기본 기능을 차단하지 않는다. PR #49에서 BE도 같은 선택 동의 기준으로 맞췄다. 앱 재실행 시 로그인 복원과 만료 후 자동 재인증은 아래 "세션 보관"에 구현했으나 실기기 확인 전이다. PR #50에 함께 요청한 약관의 서버 관리는 서버가 약관 본문을 내려주어야 해서 아직 하지 않았다.

## 함께하는 소중한 분

한 보호자가 어르신을 최대 3분까지 등록해 바꿔 가며 쓰는 부가기능이다. 첫 가입은 기존 온보딩 그대로이고, 추가는 그 뒤에 한다. 다른 어르신의 대화 카드로 면회하는 실수를 막으려고 지금 어르신의 이름을 여러 곳에 보여준다.

| 자리 | 동작 |
| --- | --- |
| 홈 상단 | 알약(성별 기본 사진과 `○○ 어르신`). 누르면 `/profiles`. 두 분 이상이면 오른쪽 원형 화살표로 다음 분에게 바로 넘어가고 `지금부터 ○○ 어르신과 함께해요`를 띄운다 |
| 홈 안내 | `오늘은 ○○ 어르신과 무슨 주제로 대화를 나눠볼까요?` |
| `/profiles` | 슬롯 3개. 누르면 전환, 빈 슬롯은 추가, 등록하다 나간 분은 `입력 중`으로 남아 이어서 입력. 꾹 눌러 끌면 순서를 바꾸고 이 순서가 화살표 순서다. 맨 아래 버튼으로 지울 분을 골라 확인 후 지운다. 마지막 한 분도 같은 확인창으로 지우며 계정은 남는다 |
| 어르신 추가 | 처음 오셨네요를 건너뛰고 기본 정보부터 입력한다. 마치면 새 분으로 바뀐다 |
| 프로필 설정 | 지금 어르신의 기본 정보를 보여준다. 약관 동의는 계정 공통이라 `계정 약관 동의`로 표시한다 |
| 회원 탈퇴 | 계정 전체를 지우므로 특정 어르신 이름을 부르지 않는다 |

어르신마다 나뉘는 것은 기본 정보, 홈 리포트 알림, 대화 카드 선택이다. 세부 정보, 사진, 대화 카드와 리포트는 아직 목 데이터 한 벌을 함께 쓴다. 어르신별 데이터는 서버를 붙이면 `profileId` 기준 API(`api-spec.md` 2절, 4-2, 5-4, 7-1)가 내려준다.

입력한 기본 정보와 어르신 목록은 프로필 저장 API(`api-spec.md` 2-2)가 없어 **앱이 켜져 있는 동안만 기억한다.** 단말 보관 범위가 정해지지 않아(이슈 18) 단말 저장소에 쓰지 않는다. 앱을 다시 켜거나 로그아웃 또는 탈퇴하면 빈 목록으로 돌아간다(`forgetCareProfiles`). 등록을 마친 분의 세부 정보와 사진은 목 데이터를 쓰고, 입력 화면의 사진 소재 후보와 음성 예시는 `profileSampleProvider`로 목 데이터를 읽는다. 코드는 [providers.dart](lib/data/providers.dart)의 `careProfilesProvider`와 [setup_controller.dart](lib/features/profile_setup/setup_controller.dart)의 `pendingSetupsProvider`다.

홈 리포트 알림은 계정과 어르신마다 따로 둔다. 로그아웃해도 지우지 않으며, 다른 계정으로 들어오면 보이지 않고 원래 계정으로 다시 들어오면 다시 보인다. 로그아웃한 사이 도착한 리포트도 기다리던 계정에 남는다. 탈퇴하면 그 계정의 알림만 지운다. 이 알림도 앱이 켜져 있는 동안만 기억한다. 다만 지금은 로그아웃하면 어르신 목록이 비므로, 같은 계정으로 다시 들어와도 알림을 띄울 어르신이 없다. 서버의 프로필 목록을 받으면 같은 어르신이 돌아와 알림도 다시 보인다.

### 등록한 어르신이 없을 때

서버를 쓰면 회원가입에서 첫 분을 반드시 등록하므로, 어르신이 없는 경우는 보호자가 마지막 분을 지운 때다. 프로필 삭제는 계정 탈퇴가 아니므로 계정 설정과 로그아웃은 그대로 쓴다. 지금은 어르신 목록을 서버에서 받지 않아 로그인만 하고 들어와도 이 상태다. 입력하다 멈춘 분(`입력 중`)은 등록한 분으로 치지 않는다.

| 자리 | 동작 |
| --- | --- |
| 홈 상단 | 알약 자리에 `＋ 어르신 등록`. 누르면 `/profiles` |
| 홈 안내 | `오늘은 무슨 주제로 대화를 나눠볼까요?` |
| 알림, 일대기, 오늘의 대화카드 받기, 마이페이지의 리포트 기록 | `어르신을 먼저 등록해주세요` 창. `등록하러 가기`는 `/profiles`, `닫기`는 그 자리에 남는다 |
| 프로필 설정 | 어르신 사진, 기본 정보, 세부 정보, 갤러리를 감추고 계정 약관 동의, 저장하기, 로그아웃, 회원탈퇴만 보인다 |
| `/profiles` | 빈 슬롯 3개. 지우기 버튼은 감춘다 |
| 대화 카드, 면회, 리포트, 알림, 일대기 경로 | 주소로 바로 들어오면 화면 대신 등록 안내를 보여준다(`router.dart`의 `_NeedsProfile`) |

### 확인이 필요한 것

- BE: 명세 2-2는 계정당 프로필 1개다. 최대 3분 허용, 프로필 삭제 API, 푸시 알림의 `profileId`, 2-1 목록 응답의 이름과 성별은 합의 전이다.
- BE: 로그인 후 마지막에 본 어르신을 여는 기능은 단말 보관 범위와 함께 정한 뒤 붙인다. 지금은 첫 분으로 연다.
- PM: 화면 문구는 FE 초안이다. 다른 어르신의 리포트가 도착했을 때 알리는 방식도 정하지 않았다.

## 구글 로그인

서버 계약은 [`backend/README.md`](../backend/README.md)의 "로그인 API"를, 근거는 ADR-007을 따른다.
동의 문구는 `docs/legal/consent-draft.md`에서 옮긴 `consent_terms.dart`를 쓰고 화면에서 새로 쓰지 않는다.

### 흐름

    A-2 로그인의 구글 버튼
    → google_sign_in 으로 ID 토큰을 받는다 (사용자가 취소하면 아무것도 하지 않는다)
    → POST /auth/google
        → status=authenticated   → 세션을 받고 /home
        → status=consentRequired → /login/consent → POST /auth/consent → /onboarding

    앱을 다시 켤 때 (A-1 스플래시)
    → 보관한 세션 읽기 (없으면 /login)
    → 만료 전이면 GET /auth/me 로 확인
        → 200                → /home
        → 401, 403           → 아래 무음 로그인
        → 그 밖의 오류, 연결 실패 → 확인만 못 한 것이므로 세션을 두고 /home
    → 만료됐거나 서버가 거절하면 google_sign_in 무음 로그인으로 새 ID 토큰
    → POST /auth/google
        → status=authenticated   → 새 세션을 보관하고 /home
        → status=consentRequired → 계정이 사라진 경우다. 세션을 버리고 /login

구글 인증만으로는 계정이 만들어지지 않는다. `/login/consent`에서 필수 동의를 제출해야
계정과 동의 이력이 함께 만들어지고, 중간에 나가면 계정이 남지 않는다.

어떤 항목이 필수인지는 서버가 준 `requiredConsents`로 판단한다. 앱 상수로 따로 판단하면
서버의 거절 기준과 어긋날 수 있어 한곳을 본다. 문구는 아직 `consent_terms.dart`에 있다.

앱이 보여주는 약관 버전(`consentVersion`)이 서버가 제시한 것과 다르거나, 서버가 앱에 문구가
없는 항목을 필수로 요구하면 동의를 받지 않는다. 보여주지 않은 문구에 동의를 받는 셈이기 때문이다.

### 세션 보관

세션은 `flutter_secure_storage`에 둔다(안드로이드는 키스토어로 감싼 AES-GCM, iOS는 키체인).
평문 `SharedPreferences`에 두지 않는다. 보관하는 값은 접근 토큰, 만료 시각과 계정이며
구글 ID 토큰과 등록 토큰은 그때만 쓰고 보관하지 않는다.

서버는 리프레시 토큰을 두지 않으므로, 갱신은 앱이 구글 무음 로그인으로 새 ID 토큰을 받아
`POST /auth/google`을 다시 부르는 방식이다(`backend/README.md`의 "세션").

서버에 닿지 못했을 때는 만료 전 세션을 버리지 않는다. 확인하지 못했을 뿐 만료된 것은
아니어서, 여기서 로그인 화면으로 보내면 오프라인에서 앱을 열 수 없다.

### 로그아웃과 탈퇴

    MYPAGE 프로필 설정의 로그아웃
    → 단말 세션 삭제 → POST /auth/logout → 구글 쪽 로그아웃 → /login

    MYPAGE 프로필 설정의 회원탈퇴 → /profile/delete 의 탈퇴하기
    → DELETE /auth/me
        → 204                         → 단말 세션 삭제 → 구글 쪽 로그아웃 → /login, "탈퇴가 완료됐어요."
        → 401, 404 (세션 풀림, 계정 없음) → 이유를 알리고 "로그인으로 돌아가기"
        → 그 밖의 오류, 연결 실패        → 이 화면에 남아 이유를 알린다. 세션을 지우지 않는다

로그아웃은 `SessionNotifier.signOut()`이다. 단말 세션을 먼저 지우고 서버에 폐기를 알린다.
서버에 닿지 못해도 로그아웃은 된다. 오프라인에서도 로그아웃은 되어야 하고, 단말에서 지운
세션은 다시 쓰일 일이 없다. 서버가 받지 못한 세션은 만료(기본 1시간)까지 서버에서만 유효하다.

탈퇴는 `SessionNotifier.deleteAccount()`다. 로그아웃과 순서가 반대로, 서버가 `204`로 답한
뒤에만 단말 세션을 지운다. 실패했는데 로그아웃된 것처럼 보이면 사용자는 탈퇴됐다고 믿게
된다. 서버 계정 없이 들어온 경우(아이디와 비밀번호 목 로그인)는 지울 계정을 가리킬 세션이
없으므로 서버를 부르지 않고 로그인 정보가 없다고 알린다.

탈퇴 이유 설문은 화면에서만 쓰고 서버로 보내지 않는다. 기기에 남은 녹음 파일 등 단말 자료는
지우지 않는다. 탈퇴 시 단말 자료의 삭제 범위는 정해지지 않았다(`docs/legal/README.md`의
"열린 쟁점"). `/profile/delete`의 "활동 정보와 개인 정보가 삭제돼요" 문구는 아직 서버의
실제 삭제 범위(계정과 동의 이력)보다 넓다. 범위가 정해지면 문구나 삭제 범위를 맞춘다.

### 코드 구성

| 파일 | 역할 |
| --- | --- |
| `lib/data/auth_api.dart` | 서버 호출과 응답·실패 타입 |
| `lib/features/auth/google_authenticator.dart` | `google_sign_in`을 감싼 인터페이스 |
| `lib/features/auth/auth_providers.dart` | provider와 세션 상태 |
| `lib/features/auth/auth_session.dart` | 세션 값과 보관 형태 |
| `lib/features/auth/session_store.dart` | 단말 보안 저장소 |
| `lib/features/auth/session_restore.dart` | 앱 재실행 시 복원과 자동 재인증 |
| `lib/features/auth/auth_messages.dart` | `errorCode`를 사용자 문구로 옮김 |
| `lib/features/auth/consent_form.dart` | A-3과 함께 쓰는 동의 항목 UI |
| `lib/features/auth/google_consent_screen.dart` | `/login/consent` 화면 |
| `lib/features/auth/google_sign_in_button.dart` | 구글이 배포한 버튼 이미지 |
| `assets/signin-assets/` | 버튼 이미지와 출처 기록([README](assets/signin-assets/README.md)) |

화면은 provider만 보고 SDK나 서버를 직접 부르지 않는다. 테스트는 `authApiProvider`와
`googleAuthenticatorProvider`를 override한다(ADR-005). 확인 내용은 `test/google_login_test.dart`에 있다.

### 설정

클라이언트 ID와 서버 주소는 저장소에 적지 않고 빌드할 때 넘긴다.

    flutter run --dart-define=SAEROK_GOOGLE_SERVER_CLIENT_ID=<웹 클라이언트 ID> --dart-define=SAEROK_API_BASE_URL=http://10.0.2.2:8000

| `--dart-define` | 기본값 | 설명 |
| --- | --- | --- |
| `SAEROK_GOOGLE_SERVER_CLIENT_ID` | 없음 | `google_sign_in`의 `serverClientId`. 비면 구글 창을 띄우기 전에 설정 오류로 막는다 |
| `SAEROK_API_BASE_URL` | `http://10.0.2.2:8000` | 에뮬레이터에서 호스트를 가리키는 주소. 실기기는 PC의 LAN 주소를 넘긴다 |

`serverClientId`가 ID 토큰의 `aud`가 되므로 서버의 `SAEROK_GOOGLE_CLIENT_IDS`와 같아야 한다.
Google Cloud Console에 Application ID `com.saelog.app`과 디버그·릴리스 SHA-1 등록이 선행되어야 한다.

개발 서버가 http라서 평문 통신을 디버그 빌드에서만 열어 두었다
(`android/app/src/debug/AndroidManifest.xml`). 릴리스 빌드에는 들어가지 않는다.

### 확인이 필요한 것

- **Application ID** — `backend/README.md`는 패키지명을 `com.saerok.app`으로 적었으나
  ADR-002가 확정한 값은 `com.saelog.app`이다. Google Cloud Console에 등록하기 전에 맞춰야 한다.
- **`Account` 계약** — 서버 응답에는 `loginId`가 없고 `email`이 `null`일 수 있어
  `lib/data/models.dart`의 `Account`와 형태가 다르다. 없는 값을 지어내지 않으려고
  `AuthAccount`를 따로 두었고, 계약이 합쳐지면 하나로 줄인다. PR #50 리뷰는 분리를
  유지해도 된다고 보았으며, 계정 식별 방식과 이메일이 없을 때의 기준을 BE와 맞추는 일이 남았다.
- **약관의 서버 관리** — 필수 여부는 서버 목록을 따르도록 고쳤으나 문구는 아직
  `consent_terms.dart`에 있다. 문구만 바뀌어도 앱 업데이트가 필요하고, 약관 버전이 다르면
  가입을 막는다. 서버가 약관 본문을 내려주는 방법이 정해져야 고칠 수 있다(PR #50 리뷰).
- **사용 중 세션 만료** — 앱을 켤 때만 자동 재인증을 한다. 쓰는 도중 세션이 만료된 뒤
  탈퇴하기를 누르면 "로그인이 풀렸어요"를 띄우고 로그인부터 다시 하게 한다. 서버 호출마다
  무음 재인증을 붙일지는 녹음 업로드 연결과 함께 정한다.

## 면회 녹음

E-2 녹음 화면에서 실제로 마이크를 열고 기기에 파일을 남긴다. 이 파일은 이후 서버로
보내 STT를 거치지만, 업로드는 아직 붙이지 않았다([아직 없는 것](#아직-없는-것)). 코드는 [`visit_recorder.dart`](lib/features/visit/visit_recorder.dart)에
모여 있고, 화면과 [`VisitController`](lib/features/visit/visit_controller.dart)는
`VisitRecorder` 인터페이스만 본다. 테스트는 `visitRecorderProvider`를 override 한다.

### 저장 위치

`path_provider`의 `getApplicationDocumentsDirectory()` 아래 `visit_recordings/`다.
Android에서 이 값은 `context.getDir("flutter", MODE_PRIVATE)`이므로 실제 경로는
다음과 같다.

```
/data/user/0/com.saelog.app/app_flutter/visit_recordings/visit-2026-09-23T14-05-33-120.wav
```

- 앱 전용 내부 저장소다. 다른 앱과 갤러리, 파일 관리자에 보이지 않고 USB로도
  바로 꺼낼 수 없다. 앱을 지우면 함께 지워진다.
- 외부 저장소를 쓰지 않으므로 `READ/WRITE_EXTERNAL_STORAGE` 권한이 필요 없다.
- 파일 이름에는 시각만 넣는다. 어르신 이름이나 회차 정보처럼 사람을 알아볼 수
  있는 값은 파일 이름에 남기지 않는다.
- 확인은 `adb exec-out run-as com.saelog.app ls app_flutter/visit_recordings`로 한다.
  `run-as`는 디버그 빌드에서만 된다.

### 음성 형식

WAV / PCM 16비트 / 16kHz / 모노다. BE [PR #71](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/71)과
AI [PR #66](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/66)이 검사하는 형식과 같다.
두 PR 모두 머지 전이고 PR #71의 ADR-008도 `proposed`라 확정값은 아니다. `app/CLAUDE.md`대로 형식은 AI 영역이 확정한다. 바뀌면
`visitRecordConfig`와 `VisitRecording.fileExtension`, 그리고
`test/visit_recording_test.dart`의 `음성 형식` 테스트를 함께 고친다.

1시간 녹음은 약 115MB다. PR #71의 서버 업로드 상한 기본값은 512MB다.

### 권한과 실패

`AndroidManifest.xml`에 `RECORD_AUDIO`를 넣었고, 사용자가 녹음을 시작할 때
`record`가 권한을 묻는다. 거부, 장치 열기 실패와 저장 실패는
`VisitState.problem`으로 구분해 화면에서 안내한다.

### 파일을 반드시 닫아야 하는 이유

WAV 헤더 44바이트는 녹음을 **끝낼 때** 파일 앞에 덮어 쓰인다
(`record_android`의 `WaveContainer.stop()`). 끝내지 않고 화면을 떠나거나 앱이
죽으면 그 자리가 0으로 남아, 소리는 들어 있는데 열 수 없는 파일이 된다.

- `만남 끝내기`뿐 아니라 **녹음 화면을 떠날 때도** 파일을 닫는다
  (`_RecordScreenState.dispose`).
- 닫은 뒤 파일이 정말 `RIFF`로 시작하는지 확인하고, 아니면 저장 실패로 알린다.
  경로가 있다고 성공이라 말하지 않는다.
- **개발 중 hot restart(`flutter run`의 `R`)는 이 과정을 건너뛴다.** 그때 남은
  파일은 재생되지 않으니 지우고 다시 녹음한다. 확인은 다음과 같이 한다.

  ```
  adb exec-out run-as com.saelog.app cat app_flutter/visit_recordings/<파일> | head -c 4
  ```

  `RIFF`가 나오면 정상이다.

### 만남 끝내기 확인 창

`만남 끝내기`를 누르면 바로 끝내지 않고
[`stop_recording_dialog.dart`](lib/features/visit/stop_recording_dialog.dart)의
확인 창을 띄운다.

- 창이 떠 있는 동안 **녹음과 시간을 잠시 멈춘다.** 창을 보는 사이의 침묵을
  대화로 남기지 않으려는 것이다. `이어서 녹음`을 고르면 같은 파일에 이어 쓴다.
  잠시 멈춤 상태에서 눌렀다면 멈춘 채로 돌아간다.
- 같은 자리에서 **참여자 수**를 받는다. 기본 2명이고 1~8명까지 고른다.
  계약의 `VisitSession.participantCount`이며 STT 화자 분리 요청의
  `speakerCount`로 그대로 넘어간다.
- **앱이 목소리를 세어 짐작하지 않는다.** 보호자가 확인해 준 수만 쓴다. 창을
  거치지 않고 화면을 떠나면 값을 비워 둔다.

### 아직 없는 것

PR #71이 머지되면 별도 PR로 붙인다. 흐름은 ADR-008을 따른다.

- 서버 업로드. WAV와 `participantCount`를 multipart로
  `POST /api/v1/visit-sessions/{sessionId}/speech-analyses`에 보낸다.
- 상태 조회. `202`로 받은 `analysisId`로 `GET /api/v1/speech-analyses/{analysisId}`를
  조회해 홈 타일에 반영한다.
- 기기 파일 삭제. 서버가 `202`로 받은 뒤 지운다. 지금은 파일이 쌓인다.
- 보내지 못한 파일을 기기에 얼마나 둘지. ADR-008은 FE 문서에서 정하게 했으나 **미정**이며
  PM 확인이 필요하다.
- 앱이 백그라운드로 내려갔을 때의 처리와 포그라운드 서비스.

## 담당과 남은 연동

| 영역 | FE 작업 | 함께 정할 경계 |
| --- | --- | --- |
| 화면 | 초기 설정, 카드, 면회, 리포트, 평가와 스토리북 | 카드 수와 제공 방식 등 제품 범위는 PM 결정 |
| 녹음 | 권한 안내, 녹음 상태, 제어와 앱 생명주기, 기기 저장 | 음성 형식은 AI가 확정한다. 업로드와 상태 조회는 BE 계약(PR #71)을 따르며 남았다 |
| 사진 | 카메라와 갤러리 연동 | 현재는 목 이미지. 권한 거부, 중단과 복구 흐름은 FE가 정함 |
| 데이터 | 합의된 저장 및 서버 인터페이스를 앱에 연결 | BE가 저장 구조, 암호화와 API 담당. 현재는 `MockRepository` |
| 품질 | 오류 상태, 수동 전환과 접근성 | 실제 모델 결과와 실패 상태는 AI, BE 계약 확인 |

MVP의 STT와 VLM 실행 위치는 [ADR-006](../docs/architecture/decisions/ADR-006-server-side-ai-processing.md)의 온프레미스 GPU 1대다. 앱의 실제 서버 연동은 후속 작업이다.

동의와 개인정보 조건은 위 법률 문서를 따르며, 녹음 시작과 AI 제안의 프로필 및 스토리 반영에는 사용자 확인이 필요하다. 목 화면에 표시된 카드 수, 태그와 동의 항목은 제품의 최종 결정이나 실제 연동 완료를 뜻하지 않는다. 계약과 PM 문서가 다른 부분은 관련 담당자가 확인한다.

## 목 데이터 관리

| 위치 | 역할 |
| --- | --- |
| `docs/architecture/mock/` | FE, BE와 AI가 계약과 함께 관리하는 원본 |
| `app/assets/mock/` | Flutter 패키지 밖 파일을 asset으로 읽을 수 없어 둔 사본 |

계약 변경 시 두 곳을 같은 PR에서 갱신한다. [동기화 테스트](test/mock_data_sync_test.dart)는 원본 폴더가 없으면 비교를 skip한다. 현재 브랜치에 원본이 있는데도 skip되면 실행 위치와 체크아웃을 확인하고, 비교를 실행한 결과와 skip 여부를 PR에 남긴다.

### 계정 응답 읽기

`Account`는 공통 계약의 `authProvider`를 읽고 `loginId`를 요구하지 않는다. `email`은 `String?`이며 서버가 제공하지 않는 경우 `null`을 그대로 유지한다. 이메일을 임의로 채우지 않는다. 계정 목 데이터 두 벌은 이메일을 보관하지 않는 응답을 예시로 사용한다.

`test/account_model_test.dart`는 실제 `Account.fromJson`으로 이메일의 `null`, 문자열, 누락과 잘못된 타입을 검사한다. 이 변경은 계정 응답을 읽는 범위이며 이메일 미저장 정책을 확정하거나 화면의 실제 로그인 연동을 완료한 것은 아니다.

구글 로그인 연결과 별도 `AuthAccount`는 [PR #50](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/50)에서 다룬다. 약관의 서버 관리, 앱 재실행 시 로그인 유지와 만료 후 자동 재인증은 해당 PR의 후속 요청이며 여기서 구현하지 않았다.
