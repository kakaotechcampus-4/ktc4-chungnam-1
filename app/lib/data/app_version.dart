/// 앱 버전을 서버에 알리고, 앱이 서버와 맞지 않아 보이는 실패를 가린다.
///
/// 모든 요청(`ApiClient`, `AuthApi`)에 설치된 앱의 versionCode 를
/// [appVersionCodeHeader] 로 실어 보낸다. 서버가 최소 지원 버전보다 낮다고 보면
/// `426` 으로 거절하고, 앱은 업데이트가 필요하다고 알린다.
///
/// 서버는 `426 APP_UPDATE_REQUIRED` 로 거절한다. 앱은 `errorCode` 를 보지 않고
/// `426` 만 본다.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 요청에 앱의 versionCode 를 싣는 헤더.
const appVersionCodeHeader = 'X-App-Version-Code';

/// 설치된 앱의 versionCode. 앱을 켤 때 [readAppVersionCode] 로 읽어
/// `main.dart` 가 넣는다. 읽지 못했거나 테스트면 `null` 이고 헤더를 싣지 않는다.
final appVersionCodeProvider = Provider<String?>((ref) => null);

/// 설치된 앱의 versionCode 를 읽는다. 안드로이드는 `pubspec.yaml` 의
/// `version` 에서 `+` 뒤 숫자다. 읽지 못하면 `null` 이다.
Future<String?> readAppVersionCode() async {
  try {
    final code = (await PackageInfo.fromPlatform()).buildNumber;
    return int.tryParse(code) == null ? null : code;
  } on Object catch (error) {
    if (kDebugMode) debugPrint('[app-version] 읽지 못함: $error');
    return null;
  }
}

/// 서버가 이 앱 버전으로는 처리하지 않는다고 분명히 알렸는지(`426 Upgrade
/// Required`). 다른 실패와 달리 앱이 구버전이라고 단정할 수 있다.
bool isUpdateRequiredStatus(int statusCode) => statusCode == 426;

/// 앱이 서버와 맞지 않을 때 서버가 돌려주는 거절인지. 명세 공통 오류와
/// 서버의 기본 처리(`backend/app/core/errors.py`)를 따른다.
///
/// 서버가 경로를 모르거나(`404 NOT_FOUND`, `405`, `410`), 요청 형식이 틀렸다고
/// 하거나(`422 INVALID_REQUEST`), 업데이트를 요구했을 때(`426`)다. 회차나
/// 프로필을 찾지 못한 것처럼 업무상 `404` 와 `422` 는 넣지 않는다.
bool suggestsContractMismatch(int statusCode, String? errorCode) =>
    switch (statusCode) {
      405 || 410 || 426 => true,
      404 => errorCode == 'NOT_FOUND',
      422 => errorCode == 'INVALID_REQUEST',
      _ => false,
    };
