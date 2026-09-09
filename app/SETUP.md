# 개발 환경 세팅

새록 Flutter 앱을 각자 PC에서 실행하기 위한 안내다. 버전과 선택 이유는 [`README.md`](README.md)에, 상태 관리와 화면 이동 결정은 [ADR-003](../docs/architecture/decisions/ADR-003-flutter-state-management-and-routing.md)에 있다.

## 누가 무엇을 하나

| 대상 | 필요한 것 |
| --- | --- |
| FE | 아래 전체 |
| AI, BE | **없음.** 목 데이터는 `docs/architecture/mock/`의 JSON을 각자 언어로 읽으면 되고, 화면은 FE가 공유하는 APK나 화면 캡처로 확인한다 |

<br>

## 1. Flutter 설치

버전을 **3.44.8**로 맞춘다. 팀원 사이에 버전이 다르면 빌드 결과가 달라진다.

이미 설치되어 있으면 버전만 확인한다.

```
flutter --version
```

`Flutter 3.44.8 • channel stable`과 `Dart 3.12.2`가 나와야 한다. 

### 설치되어 있지 않다면

1. <https://docs.flutter.dev/get-started/install/windows>에서 **3.44.8** 압축 파일을 받는다. 최신본이 다른 버전이면 같은 쪽의 이전 버전 목록에서 찾는다.
2. `C:\src\flutter`처럼 **공백과 한글이 없는 경로**에 푼다. `C:\Program Files`와 바탕화면 아래는 빌드가 깨진다.
3. `C:\src\flutter\bin`을 시스템 환경 변수 `Path`에 추가한다. 시작 메뉴에서 `환경 변수`를 검색해 연다.
4. **새 터미널**을 열고 `flutter --version`으로 확인한다. 이미 열려 있던 터미널에는 변경된 `Path`가 반영되지 않는다.

<br>

## 2. Android Studio와 SDK

Android Studio를 설치하면 JDK가 함께 설치된다. 따로 JDK를 받지 않아도 된다.

설치되어 있지 않다면 <https://developer.android.com/studio>에서 설치 프로그램을 받아 실행한다. 처음 실행할 때 나오는 설정 마법사가 Android SDK를 함께 내려받는다. 이 단계에서 수 GB를 받으므로 시간이 걸린다.

SDK Manager에서 다음을 확인한다. Android Studio 시작 화면의 **More Actions → SDK Manager**, 또는 프로젝트에서 **Settings → Languages & Frameworks → Android SDK**로 연다.

- **SDK Platforms** 탭: `Android API 36`
- **SDK Tools** 탭: `Android SDK Command-line Tools (latest)`

Command-line Tools는 잊기 쉬운데 없으면 Flutter가 Android SDK를 다루지 못한다. `flutter doctor`가 "Android Studio를 설치하라"고 안내한다면 대개 이것이 빠진 경우다.

<br>

## 3. 실행할 기기

**안드로이드 폰이 있으면 에뮬레이터를 만들지 않아도 된다.** 녹음과 알림을 다루는 앱이라 실기기가 더 정확하고 빠르다.

**안드로이드 폰을 쓰는 경우**

1. 설정 → 휴대전화 정보 → (갤럭시는 **소프트웨어 정보** 안에 있다) → **빌드번호를 7번 연타**
2. 설정 → 개발자 옵션 → **USB 디버깅** 켜기
3. USB로 연결하고 폰에 뜨는 허용 팝업을 승인

빌드번호가 안 보이면 설정 검색창에 `빌드`를 입력한다.

**아이폰만 쓰는 경우** — 에뮬레이터가 필요하다. Android Studio의 Device Manager에서 만든다.

- 기기: **Pixel 7 또는 8** (412 x 915 dp로 기준 화면 412 x 917 dp에 가깝다)
- 시스템 이미지: **API 36**, `Google Play` 또는 `Google APIs`가 붙은 것, `x86_64`
- 기본(AOSP) 이미지에는 Google Play 서비스가 없어 푸시 알림을 확인할 수 없다

<br>

## 4. 확인

```
flutter doctor
flutter devices
```

`flutter devices`에 기기나 에뮬레이터가 보이면 준비가 끝났다.

### 무시해도 되는 경고

| 경고 | 이유 |
| --- | --- |
| `Android license status unknown` | Command-line Tools 23.0에서 `sdkmanager`가 폐기되고 `android` CLI로 바뀌었는데 Flutter 3.44.8이 옛 방식으로 확인해 생긴다. `flutter doctor --android-licenses`는 "더 이상 필요하지 않다"는 안내만 출력한다. 빌드는 정상 동작한다 |
| `Visual Studio not installed` | Windows 데스크톱 앱을 만들 때 필요하다. 이 프로젝트는 Android 전용이라 상관없다 |

<br>

## 5. 프로젝트 실행

```
git clone https://github.com/kakaotechcampus-4/ktc4-chungnam-1.git
cd ktc4-chungnam-1/app
flutter pub get
flutter run
```

폰이나 에뮬레이터에 **새록**이 설치되고 화면이 뜨면 성공이다.

<br>

## 자주 쓰는 명령

`app/` 안에서 실행한다.

| 명령 | 용도 |
| --- | --- |
| `flutter run` | 기기에서 실행. 종료는 `q` |
| `flutter test` | 테스트 실행. **푸시 전에 실행한다** |
| `flutter analyze` | 정적 검사 |
| `flutter build apk --debug` | APK 만들기. AI, BE와 화면을 공유할 때 쓴다 |

`flutter run`은 테스트를 실행하지 않는다. 목 데이터 사본이 원본과 갈라졌는지는 `flutter test`를 돌려야 알 수 있다.

<br>

## 막힐 때

| 증상 | 확인할 것 |
| --- | --- |
| `flutter devices`에 폰이 안 보임 | USB 디버깅이 켜져 있는지, 폰의 허용 팝업을 승인했는지, 케이블이 충전 전용은 아닌지 |
| Gradle 빌드가 오래 걸림 | 첫 빌드는 배포판과 의존성을 받아 몇 분 걸린다. 두 번째부터 빨라진다 |
| `flutter.sdk not set in local.properties` | `app/`에서 `flutter pub get`을 먼저 실행한다. `local.properties`는 PC마다 달라 저장소에 올리지 않는다 |
| 목 데이터 테스트가 skip으로 나옴 | 정상이다. 아래 설명을 참고한다 |

<br>

## 목 데이터

목 데이터는 두 곳에 있고 **`docs/architecture/mock/`이 원본**이다.

    docs/architecture/mock/   원본. 공통 데이터 계약과 함께 FE, BE, AI 리더가 공동 관리
    app/assets/mock/          사본. Flutter 가 패키지 루트 밖을 asset 으로 읽지 못해 복사

**계약이 바뀌면 두 곳을 같은 PR에서 함께 갱신한다.** 원본을 고치고 사본으로 복사한다.

`app/test/mock_data_sync_test.dart`가 두 벌이 같은지 확인한다. 원본이 아직 브랜치에 없으면 건너뛰고, 원본이 들어오면 코드 수정 없이 비교를 시작한다.
