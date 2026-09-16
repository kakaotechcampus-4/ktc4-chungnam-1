# ADR-002: Android Application ID 통일

상태: accepted

담당: PM, FE

결정일: 2026-08-22

관련 Issue: #3

## 배경

저장소 문서에는 이전 GitHub 이름을 사용한 Android Application ID가 기록되어 있었다. 팀에서 앱 식별자를 `com.saelog.app`으로 통일하기로 결정해 문서와 이후 구현의 기준을 맞춰야 한다.

## 결정

새록 Android 앱의 Application ID는 `com.saelog.app`을 사용한다. Flutter 프로젝트명 `saerok`과 사용자에게 표시되는 앱 이름 `새록`은 그대로 유지한다.

앱 소스가 저장소에 추가되면 Android 빌드 설정, 매니페스트, 테스트 패키지와 외부 서비스 설정도 이 식별자를 사용한다.

## 검토한 대안

- 기존 GitHub 이름 기반 식별자 유지
- 새 값 `com.saelog.app`으로 통일

팀 결정에 따라 새 값을 채택하며 기존 값은 더 이상 사용하지 않는다.

## 영향

- Android 빌드 설정과 패키지 경로
- OAuth, 딥링크, 푸시, Firebase 등 앱 식별자를 요구하는 외부 연동
- 테스트 패키지와 배포 설정
- 앱 식별자를 안내하는 프로젝트 문서

## 검증

- 저장소에서 이전 Application ID가 남아 있지 않은지 검색
- Flutter 앱 소스 반입 후 Android 빌드 설정의 Application ID 확인
- 외부 서비스 도입 시 등록된 패키지명이 `com.saelog.app`과 일치하는지 확인

## 재검토 조건

앱 배포 계정이나 도메인 정책 때문에 현재 식별자를 사용할 수 없거나, 외부 서비스 등록 전에 식별자 변경이 필요한 경우 재검토한다.
