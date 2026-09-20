# FE 영역

담당 리더: 이서형. 합성 목 데이터로 화면을 연결한 단계이며 실제 녹음, 카메라와 서버 연동은 아직 없다. BE 인증 API는 develop에 반영됐지만 앱의 구글 로그인 연결은 [PR #50](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/50)에서 검토 중이다.

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
| `/profile/create` | 환자 정보 입력 (7단계) | B-2 ~ B-8 |
| `/home` | 홈 | HOME, HOME-1 |
| `/cards` | 오늘의 대화 카드 | C-1 ~ C-3 |
| `/visit/photo` | 면회 전 사진 | D-1 |
| `/visit/record` | 녹음 안내와 녹음 중 | E-1, E-2 |
| `/visit/cards/add` | 면회 중 대화 카드 추가 | E-5 |
| `/visit/review` | 보호자 소감 | F-1 |
| `/report/:reportId` | 리포트 | G-1 |
| `/report/:reportId/changes` | 변경 사항 확인 | G-2 |
| `/profile` | 프로필 설정 | MYPAGE |
| `/reports` | 리포트 기록 | 설계 없음 |
| `/album` | 일대기 | H, 기획 보류 안내만 표시 |

면회 중 카드 E-3, E-4는 녹음 화면의 팝업이다. HOME과 HOME-1은 리포트 알림 유무, B-3의 녹음 완료와 B-4의 인식 실패는 음성 입력 상태, C-1 ~ C-3은 카드 펼침과 추가 상태를 나타낸다.

## 현재 사용자 흐름

동의와 프로필 입력 → 대화 카드 선택 → 면회 사진과 녹음 화면 → 보호자 소감 및 평가 → 홈에서 리포트 준비 상태 확인 → 리포트 → 변경 제안 확인. PR #42에서 별도 처리 중 화면을 제거했고, 현재 리포트 생성은 목 타이머로 표시한다. 평가 제출과 변경 제안의 실제 저장은 아직 연결되지 않았다. 화면별 상세 경로는 위 표를 따른다.

알림 수신은 선택이며 거부해도 가입과 기본 기능을 차단하지 않는다. PR #49에서 BE도 같은 선택 동의 기준으로 맞췄다. PR #50에 요청한 약관의 서버 관리와 앱 재실행 시 로그인 복원은 후속 구현이며 현재 완료된 기능으로 보지 않는다.

## 구글 로그인

서버 계약은 [`backend/README.md`](../backend/README.md)의 "로그인 API"를, 근거는 ADR-007을 따른다.
동의 문구는 `docs/legal/consent-draft.md`에서 옮긴 `consent_terms.dart`를 쓰고 화면에서 새로 쓰지 않는다.

### 흐름

    A-2 로그인의 구글 버튼
    → google_sign_in 으로 ID 토큰을 받는다 (사용자가 취소하면 아무것도 하지 않는다)
    → POST /auth/google
        → status=authenticated   → 세션을 받고 /home
        → status=consentRequired → /login/consent → POST /auth/consent → /onboarding

구글 인증만으로는 계정이 만들어지지 않는다. `/login/consent`에서 필수 동의를 제출해야
계정과 동의 이력이 함께 만들어지고, 중간에 나가면 계정이 남지 않는다.

어떤 항목이 필수인지는 서버가 준 `requiredConsents`로 판단한다. 앱 상수로 따로 판단하면
서버의 거절 기준과 어긋날 수 있어 한곳을 본다. 문구는 아직 `consent_terms.dart`에 있다.

앱이 보여주는 약관 버전(`consentVersion`)이 서버가 제시한 것과 다르거나, 서버가 앱에 문구가
없는 항목을 필수로 요구하면 동의를 받지 않는다. 보여주지 않은 문구에 동의를 받는 셈이기 때문이다.

### 코드 구성

| 파일 | 역할 |
| --- | --- |
| `lib/data/auth_api.dart` | 서버 호출과 응답·실패 타입 |
| `lib/features/auth/google_authenticator.dart` | `google_sign_in`을 감싼 인터페이스 |
| `lib/features/auth/auth_providers.dart` | provider와 세션 상태 |
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
  `AuthAccount`를 따로 두었고, 계약이 합쳐지면 하나로 줄인다.

## 담당과 남은 연동

| 영역 | FE 작업 | 함께 정할 경계 |
| --- | --- | --- |
| 화면 | 초기 설정, 카드, 면회, 리포트, 평가와 스토리북 | 카드 수와 제공 방식 등 제품 범위는 PM 결정 |
| 녹음 | 권한 안내, 녹음 상태, 제어와 앱 생명주기 | AI가 정의할 음성 형식과 `SpeechInput` 연결. 현재는 목 구현 |
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
