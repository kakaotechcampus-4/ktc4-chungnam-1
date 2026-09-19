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

알림 수신은 선택이며 거부해도 가입과 기본 기능을 차단하지 않는다. BE의 필수 알림 규칙을 바로잡는 PR #49는 아직 미병합이다. PR #50에 요청한 약관의 서버 관리와 앱 재실행 시 로그인 복원은 후속 구현이며 현재 완료된 기능으로 보지 않는다.

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
