# FE 영역

담당 리더: 이서형

상태: 목 데이터로 도는 화면 골격 완성. 구글 로그인만 서버에 붙었고, 녹음과 카메라, 나머지 서버 연동은 아직 붙이지 않음

개발 환경 세팅은 [`SETUP.md`](SETUP.md), 화면 디자인 기준은 [`DESIGN.md`](DESIGN.md)를 따른다.

## 담당 범위

- Flutter 앱 구조와 Android 실행 환경
- 초기 설정, 카드, 녹음 상태 및 제어, 리포트, 보호자 평가와 스토리북 화면
- BE가 정의한 단말 데이터 저장 인터페이스의 앱 연동
- 마이크 권한과 녹음 상태의 화면 및 앱 생명주기 처리
- 오류 상태와 접근성
- 로컬 AI와 BE 결과의 화면 반영

단말 데이터 저장 구조와 암호화는 BE 영역이 소유하고, 녹음 라이브러리, 음성 파일 형식과 STT 연결은 AI 영역이 소유한다. FE는 합의된 인터페이스를 화면, 사용자 권한과 앱 생명주기에 연결한다.

## 확정된 기준

- Android 우선 Flutter 앱
- Flutter 프로젝트명 `saerok`
- Application ID `com.saelog.app`
- 기준 화면 412 x 917 dp, 세로
- 고정 좌표에 의존하지 않고 더 작은 화면과 글자 확대를 고려
- 프로필, 전사문과 회차 기록은 사용자 단말 저장을 기본으로 함
- 녹음과 이미지 원본은 동의한 기능에 필요한 경우 서버에서 최대 24시간 임시 처리 가능
- 녹음 시작과 프로필 및 스토리북 반영은 앱 사용자 확인 필요
- 필수 동의는 서비스 제공을 위한 개인정보 처리, 건강 관련 민감정보 처리, 피보호자 동의 확인의 세 항목
- 이미지 분석은 기능 이용 시 별도 확인, 서비스 품질 개선과 푸시 알림은 선택 동의

## 확정된 기술

| 항목 | 값 |
| --- | --- |
| Flutter | 3.44.8 (stable) |
| Dart | 3.12.2 |
| `compileSdk` | 36 |
| `targetSdk` | 36 |
| `minSdk` | 26 |
| JDK | 21 (Android Studio 번들) |
| Gradle | 9.1.0 |
| Android Gradle Plugin | 9.0.1 |
| Kotlin | 2.3.20 |
| 상태 관리 | `flutter_riverpod` 3.4.3 |
| 화면 이동 | `go_router` 18.0.1 |
| 구글 로그인 | `google_sign_in` 7.2.0 |
| HTTP | `http` 1.6.0 |

**선택 이유**

- Flutter 3.44.8은 세팅 시점의 설치본이다. 12주 안에 버전을 올리며 생기는 위험을 만들지 않기 위해 고정했다.
- `minSdk` 26은 백그라운드 녹음에 쓰는 포그라운드 서비스의 분기를 줄이기 위해 골랐다. Flutter 기본값은 24다.
- SDK 세 값은 상수로 적었다. `flutter.*` 변수를 그대로 두면 Flutter를 올릴 때 값이 함께 바뀐다.
- JDK, Gradle, AGP, Kotlin은 Flutter 템플릿이 생성한 조합을 그대로 쓴다. 임의로 맞춘 조합보다 충돌이 적다.
- 상태 관리와 화면 이동의 선택 이유와 검토한 대안은 [ADR-005](../docs/architecture/decisions/ADR-005-flutter-state-management-and-routing.md)에 있다.

**검증 환경** — Windows 11, Galaxy S23+ (SM S916N), Android 15 (API 35), arm64 실기기. 2026-09-06에 `flutter build apk --debug`와 실기기 실행을 확인했다.

**재검토 조건**

- Flutter 또는 의존성의 보안 수정이 필요하면 버전 고정을 다시 판단한다.
- `minSdk` 26으로 배제되는 기기가 문제가 되면 24로 낮추고 분기 비용을 감수한다.
- 배포 정책이 상위 `targetSdk`를 요구하면 함께 올린다.

## FE 리더가 정할 사항

- 권한 거부, 중단과 복구 흐름. 마이크와 사진 권한을 실제로 요청하는 시점에 정한다.

선택 결과에는 버전, 선택 이유, 검토한 대안, 검증 환경과 재검토 조건을 기록한다. 구조를 바꾸는 선택은 ADR도 작성한다.

## 화면과 경로

경로는 `lib/app/routes.dart` 에 모아 두고 `lib/app/router.dart` 에서 화면과 잇는다.
화면 이동은 문자열을 직접 적지 않고 `AppRoutes` 를 쓴다.

| 경로 | 화면 | 피그마 |
| --- | --- | --- |
| `/splash` | 스플래시 | A-1 |
| `/login` | 로그인 | A-2 |
| `/signup` | 회원가입과 동의 | A-3 |
| `/login/consent` | 구글 로그인 뒤 필수 동의 | 설계 없음 |
| `/onboarding` | 처음 오셨네요 | B-1 |
| `/profile/create` | 환자 정보 입력 (7단계) | B-2 ~ B-8 |
| `/home` | 홈 | HOME, HOME-1 |
| `/cards` | 오늘의 대화 카드 | C-1 ~ C-3 |
| `/visit/photo` | 면회 전 사진 | D-1 |
| `/visit/record` | 녹음 안내와 녹음 중 | E-1, E-2 |
| `/visit/cards/add` | 면회 중 대화 카드 추가 | E-5 |
| `/visit/review` | 보호자 소감 | F-1 |
| `/visit/processing` | 리포트 만드는 중 | 설계 없음 |
| `/report/:reportId` | 리포트 | G-1 |
| `/report/:reportId/changes` | 변경 사항 확인 | G-2 |
| `/profile` | 프로필 설정 | MYPAGE |
| `/reports` | 리포트 기록 | 설계 없음 |
| `/album` | 일대기 | H, 기획 보류 |

면회 중 대화 카드(E-3, E-4)는 화면이 아니라 녹음 화면 위로 올라오는 팝업이라 경로가 없다.

`HOME`과 `HOME-1`은 리포트 알림 유무, `B-3(녹음 완료 시)`와 `B-4(음성 인식 실패 시)`는
음성 입력의 단계, `C-1 ~ C-3`은 카드가 펼쳐지고 늘어나는 상태다.

<br>

## 아직 붙이지 않은 것

화면과 상태는 만들었으나 실제 기능이 없는 부분이다.

| 항목 | 소유 | 지금 상태 |
| --- | --- | --- |
| 녹음과 음성 인식 | AI | `SpeechInput` 인터페이스만 두고 목 데이터로 대신한다 |
| 카메라와 갤러리 | FE | 목 이미지로 자리를 채운다 |
| 아이디·비밀번호 로그인 | BE | 화면만 있고 서버에 보내지 않는다. 채우면 홈으로 넘어간다 |
| 세션 저장과 자동 로그인 | FE | 세션을 메모리에만 둔다. 앱을 다시 켜면 로그인부터 시작한다 |
| 로그인 뒤 서버 통신 | BE | 세션을 받아 두기만 하고, 다른 화면은 `MockRepository` 를 쓴다 |

녹음 라이브러리와 음성 형식, STT 연결은 AI 영역이 정한다. FE 가 임의로 확정하지 않는다.

<br>

## 현재 사용자 흐름

    프로필 설정
    → 필수 동의와 피보호자 동의 확인
    → 대화 카드 후보 확인
    → 녹음 면회
    → 분석 결과와 보호자 평가
    → 확인된 이야기 반영
    → 다음 회차

카드 수, 자동 선택, 추가 대화 방식과 스토리북 직접 제공 및 판매 여부는 PM 문서의 검토 중 항목이다. 화면 구현으로 먼저 확정하지 않는다.

동의 화면의 실제 문구와 기능별 노출 시점은 `docs/legal/consent-draft.md`와 `docs/legal/consent-mapping.md`를 따른다.

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

앱이 보여주는 약관 버전(`consentVersion`)이 서버가 제시한 것과 다르면 제출하지 않는다.
보여주지 않은 문구에 동의를 받는 셈이기 때문이다.

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

<br>

## 실행과 테스트

`app/`에서 실행한다. 아래는 2026-09-06 검증 환경에서 실제로 확인한 명령이다.

| 명령 | 용도 |
| --- | --- |
| `flutter pub get` | 의존성 설치 |
| `flutter run` | 연결된 기기에서 실행 |
| `flutter test` | 테스트 실행 |
| `flutter analyze` | 정적 검사 |
| `flutter build apk --debug` | 디버그 APK 빌드 |

구글 로그인을 실제로 눌러 보려면 `flutter run`에 "구글 로그인"의 `--dart-define` 두 개를 함께 넘긴다.
넘기지 않으면 버튼이 설정 오류만 알린다. 나머지 화면은 값 없이도 그대로 돈다.

푸시 전에 `flutter analyze`와 `flutter test`를 실행한다. `flutter run`은 테스트를 함께 실행하지 않는다.

세팅 절차와 자주 막히는 지점은 [`SETUP.md`](SETUP.md)에 있다.

## 목 데이터

    docs/architecture/mock/   원본. 공통 데이터 계약과 함께 관리한다
    app/assets/mock/          사본. Flutter 가 패키지 루트 밖을 asset 으로 읽지 못해 복사한다

계약이 바뀌면 두 곳을 같은 PR에서 함께 갱신한다. `test/mock_data_sync_test.dart`가 두 벌이 같은지 확인하며, 원본이 브랜치에 없으면 건너뛰고 들어오면 코드 수정 없이 비교를 시작한다.
