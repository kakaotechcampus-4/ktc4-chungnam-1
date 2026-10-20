# ADR-009: Android Application ID를 `com.saerok.app`으로 변경

상태: accepted

담당: 없음 (팀 내부 논의)

결정일: 2026-10-20

관련 Issue: 없음

대체 대상: [ADR-002](ADR-002-android-application-id.md)

## 배경

ADR-002는 Android Application ID를 `com.saelog.app`으로 정했다. 이후 팀 내부 논의에서 프로젝트 영문명을 `saelog`가 아닌 `saerok`으로 쓰기로 합의했다. Flutter 프로젝트명과 환경 변수 접두사(`SAEROK_`)는 이미 `saerok`을 사용하고 있어 앱 식별자만 다른 이름을 쓰고 있었다.

## 결정

새록 Android 앱의 Application ID와 Kotlin 패키지는 `com.saerok.app`을 사용한다. 사용자에게 표시되는 앱 이름 `새록`은 그대로 유지한다.

Android 빌드 설정, 매니페스트, 테스트 패키지와 외부 서비스 설정도 이 식별자를 사용한다.

## 검토한 대안

- ADR-002의 `com.saelog.app` 유지
- 영문명에 맞춰 `com.saerok.app`으로 변경

스토어 배포와 외부 서비스 등록이 늘기 전에 이름을 맞추는 편이 비용이 적어 변경을 채택한다. `com.saelog.app`은 더 이상 사용하지 않는다.

## 영향

- Android 빌드 설정(`namespace`, `applicationId`)과 Kotlin 패키지 경로
- Google Cloud Console의 Android OAuth 클라이언트. `com.saerok.app`과 기존 디버그·릴리스 SHA-1로 다시 등록해야 구글 로그인이 동작한다. SHA-1은 서명 키에서 나오므로 값은 바뀌지 않는다
- 웹 클라이언트 ID(`serverClientId`, 서버의 `SAEROK_GOOGLE_CLIENT_IDS`)는 Application ID와 관계없어 바뀌지 않는다
- 기존 `com.saelog.app` 빌드가 설치된 기기에서는 다른 앱으로 설치된다. 옛 앱의 앱 내부 저장소(`/data/user/0/com.saelog.app/...`)에 있던 파일은 옮겨지지 않는다
- 앱 식별자를 안내하는 프로젝트 문서

## 검증

- 저장소에서 `com.saelog.app`이 ADR-002의 과거 기록 외에 남아 있지 않은지 검색
- Android 빌드 후 설치된 패키지명이 `com.saerok.app`인지 확인
- Google Cloud Console에 등록한 Android OAuth 클라이언트로 구글 로그인과 서버 ID 토큰 검증이 통과하는지 확인

## 재검토 조건

앱 배포 계정이나 도메인 정책 때문에 현재 식별자를 사용할 수 없거나, 외부 서비스 등록 전에 식별자 변경이 필요한 경우 재검토한다.
