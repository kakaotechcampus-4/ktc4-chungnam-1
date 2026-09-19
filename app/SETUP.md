# 개발 환경 세팅

Windows에서 Android 앱을 실행하는 FE용 안내다. AI와 BE는 화면 개발을 하지 않는다면 Flutter 설치 없이 공통 목 JSON이나 FE가 공유한 APK로 확인할 수 있다. 버전과 선택 이유는 [README](README.md), 상태 관리와 라우팅은 [ADR-005](../docs/architecture/decisions/ADR-005-flutter-state-management-and-routing.md)를 참고한다.

## 1. Flutter와 Android SDK

1. [Flutter 설치 안내](https://docs.flutter.dev/get-started/install/windows)에서 3.44.8을 설치한다. 최신 버전이 다르면 이전 버전 목록을 확인한다.
2. `C:\src\flutter`처럼 공백과 한글이 없는 경로에 풀고 `C:\src\flutter\bin`을 `Path`에 추가한다. 기존 팀 안내에서는 `Program Files`와 바탕화면 아래 경로를 피하도록 했다.
3. 새 터미널에서 확인한다.

```powershell
flutter --version
```

Flutter 3.44.8 stable과 Dart 3.12.2가 기준이다.

4. [Android Studio](https://developer.android.com/studio)를 설치하고 번들 JDK 21을 사용한다.
5. SDK Manager에서 `Android API 36`과 `Android SDK Command-line Tools (latest)`를 설치한다. 시작 화면의 More Actions 또는 Settings → Languages & Frameworks → Android SDK에서 연다.

## 2. 실행 기기

| 기기 | 준비 |
| --- | --- |
| Android 실기기 | 설정에서 빌드번호 7회 누르기 → 개발자 옵션의 USB 디버깅 켜기 → USB 연결 후 허용 팝업 승인 |
| Android 에뮬레이터 | Device Manager에서 Pixel 7 또는 8, API 36, Google Play 또는 Google APIs, x86_64 이미지 생성 |

기준 화면은 412 x 917 dp다. 실기기는 녹음과 알림 검증에 사용하고, Android 기기가 없으면 에뮬레이터로 시작한다. 기본 AOSP 이미지는 Google Play 서비스를 이용한 알림 검증에 적합하지 않다.

```powershell
flutter doctor
flutter devices
```

`flutter devices`에서 연결한 기기나 에뮬레이터를 확인한다.

## 3. 프로젝트 실행

```powershell
git clone https://github.com/kakaotechcampus-4/ktc4-chungnam-1.git
cd ktc4-chungnam-1/app
flutter pub get
flutter run
```

새록 앱 화면이 뜨는지 확인한다. `flutter run` 종료는 `q`이며 테스트는 별도로 실행해야 한다.

## 4. 푸시 전 확인과 APK 공유

`app/`에서 실행한다.

```powershell
flutter analyze
flutter test
flutter build apk --debug
```

APK 빌드는 화면 공유가 필요할 때 실행한다. 목 데이터 원본과 사본의 위치 및 갱신 규칙은 [목 데이터 관리](README.md#목-데이터-관리)를 따른다. 테스트 결과에는 통과 수와 skip 여부를 남긴다.

## 막힐 때

| 증상 | 확인할 것 |
| --- | --- |
| `flutter devices`에 폰이 없음 | USB 디버깅, 허용 팝업, 데이터 전송 가능한 케이블 |
| Gradle 첫 빌드가 오래 걸림 | Gradle 배포판과 의존성 다운로드 진행 여부 |
| `flutter.sdk not set in local.properties` | `app/`에서 `flutter pub get` 실행. PC별 `local.properties`는 커밋하지 않음 |
| 목 데이터 비교가 skip됨 | `app/` 실행 여부와 `docs/architecture/mock/` 존재 여부. 원본이 없을 때만 비교를 건너뛰는 테스트임 |
| Android SDK를 찾지 못함 | SDK Manager의 API 36과 Command-line Tools 설치 여부 |
| `Visual Studio not installed` | Windows 데스크톱용 경고. Android 실행과 구분 |

<details>
<summary>기존 Android 라이선스 경고 확인 기록</summary>

팀의 Flutter 3.44.8, Command-line Tools 23.0 환경에서는 `Android license status unknown`이 표시됐지만 빌드가 동작했다. 당시 `flutter doctor --android-licenses`는 더 이상 필요하지 않다는 안내를 출력했다. 이 기록만으로 다른 환경의 라이선스 오류를 무시하지 말고 설치 버전과 실제 빌드 결과를 함께 확인한다.

</details>
