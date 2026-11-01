# ADR-009: Android Application ID를 `app.saerok.android`로 변경

상태: accepted

담당: 없음 (팀 내부 논의)

결정일: 2026-10-20

관련 Issue: 없음

대체 대상: [ADR-002](ADR-002-android-application-id.md)

## 배경

ADR-002는 Android Application ID를 `com.saelog.app`으로 정했다. 이후 팀 내부 논의에서 프로젝트 영문명을 `saelog`가 아닌 `saerok`으로 쓰기로 합의했다. Flutter 프로젝트명과 환경 변수 접두사(`SAEROK_`)는 이미 `saerok`을 사용하고 있어 앱 식별자만 다른 이름을 쓰고 있었다.

처음에는 `com.saerok.app`으로 정해 반영했으나, Google Play Console에서 이미 사용 중인 패키지 이름으로 확인되어 배포할 수 없었다. Play의 패키지 이름은 전체에서 하나만 쓸 수 있으므로 사용 가능함을 확인한 `app.saerok.android`로 다시 정했다. `com.saerok.app`은 외부 배포 전에 바꾸어 이 ADR을 직접 고쳤다.

## 결정

새록 Android 앱의 Application ID와 Kotlin 패키지는 `app.saerok.android`를 사용한다. 사용자에게 표시되는 앱 이름 `새록`은 그대로 유지한다.

Android 빌드 설정, 매니페스트, 테스트 패키지와 외부 서비스 설정도 이 식별자를 사용한다.

## 검토한 대안

- ADR-002의 `com.saelog.app` 유지
- 영문명에 맞춘 `com.saerok.app`. Google Play Console에서 이미 사용 중이라 제외
- `app.saerok.com`. 형식은 허용되나 역순 도메인 관례에 맞지 않고 `com.saerok.app`과 혼동되어 제외
- `app.saerok.android`. Google Play Console에서 사용 가능함을 확인

스토어 배포와 외부 서비스 등록이 늘기 전에 이름을 맞추는 편이 비용이 적어 변경을 채택한다. `com.saelog.app`과 `com.saerok.app`은 사용하지 않는다.

## 영향

- Android 빌드 설정(`namespace`, `applicationId`)과 Kotlin 패키지 경로
- Google Play Console에서 `app.saerok.android`로 앱을 만들어야 패키지 이름이 확보된다. 사용 가능 표시만으로는 확보되지 않는다
- Google Cloud Console의 Android OAuth 클라이언트. `app.saerok.android`와 기존 디버그·릴리스 SHA-1로 다시 등록해야 구글 로그인이 동작한다. SHA-1은 서명 키에서 나오므로 값은 바뀌지 않는다. `com.saerok.app`으로 등록한 클라이언트가 있으면 함께 정리한다
- 웹 클라이언트 ID(`serverClientId`, 서버의 `SAEROK_GOOGLE_CLIENT_IDS`)는 Application ID와 관계없어 이 결정만으로는 바뀌지 않는다. 팀 전용 개발 계정의 Google 프로젝트로 옮기며 새로 발급되면 앱과 서버 값을 함께 바꾼다
- 기존 `com.saelog.app` 또는 `com.saerok.app` 빌드가 설치된 기기에서는 별도의 앱으로 설치되며, 기존 앱의 앱 내부 저장소에 있던 녹음은 자동으로 옮겨지지 않는다. 필요한 녹음이 없으면 기존 앱은 삭제해도 된다
- 앱 식별자를 안내하는 프로젝트 문서

## 검증

- 저장소에서 `com.saelog.app`과 `com.saerok.app`이 과거 기록 외에 남아 있지 않은지 검색
- Android 빌드 후 설치된 패키지명이 `app.saerok.android`인지 확인
- Google Cloud Console에 등록한 Android OAuth 클라이언트로 구글 로그인과 서버 ID 토큰 검증이 통과하는지 확인

## 재검토 조건

앱 배포 계정이나 도메인 정책 때문에 현재 식별자를 사용할 수 없거나, 외부 서비스 등록 전에 식별자 변경이 필요한 경우 재검토한다.
