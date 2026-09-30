/// 로그인 실패를 사용자에게 보여줄 한 줄로 옮긴다.
///
/// 서버가 준 `errorCode` 는 `backend/README.md` 의 오류 표를 따른다. 모르는
/// 코드를 그럴듯한 문구로 바꾸지 않고, 무엇이 되지 않았는지만 알린다.
library;

import 'package:flutter/foundation.dart';

import '../../data/auth_api.dart';

/// 실패의 원인을 개발 중에만 콘솔에 남긴다.
///
/// 화면 문구 하나가 여러 원인을 덮는다. 설정이 비었을 때와 Google Cloud Console
/// 등록이 빠졌을 때가 사용자에게는 같은 문구인데, 고칠 자리는 서로 다르다.
///
/// ID 토큰, 등록 토큰, 세션과 계정 정보는 담지 않는다(`CLAUDE.md`). 실패 타입이
/// 들고 있는 것은 오류 코드와 설정 힌트뿐이다. 릴리스 빌드에서는 아무것도
/// 남기지 않는다.
void logAuthFailure(AuthFailure failure) {
  if (kDebugMode) debugPrint('[auth] $failure');
}

String authFailureMessage(AuthFailure failure) {
  return switch (failure) {
    AuthNetworkFailure() => '서버에 연결하지 못했어요. 인터넷 연결을 확인하고 다시 시도해주세요.',
    AuthGoogleFailure(misconfigured: true) =>
      '구글 로그인 설정이 아직 준비되지 않았어요. 담당자에게 알려주세요.',
    AuthGoogleFailure() => '구글 로그인을 마치지 못했어요. 다시 시도해주세요.',
    AuthUnexpectedResponseFailure() => '서버 응답을 확인하지 못했어요. 잠시 후 다시 시도해주세요.',
    AuthServerFailure(:final errorCode) => _serverMessage(errorCode),
  };
}

/// 다시 로그인부터 시작해야 하는 실패인지.
///
/// 동의 화면에서 등록 토큰이 만료되면 그 화면에 남아 있어도 제출할 수 없다.
bool needsRestart(AuthFailure failure) {
  return failure is AuthServerFailure &&
      const {
        'INVALID_REGISTRATION_TOKEN',
        'REGISTRATION_TOKEN_EXPIRED',
        'UNAUTHENTICATED',
        'SESSION_EXPIRED',
      }.contains(failure.errorCode);
}

String _serverMessage(String? errorCode) {
  return switch (errorCode) {
    'AUTH_NOT_CONFIGURED' => '서버의 로그인 설정이 아직 준비되지 않았어요. 담당자에게 알려주세요.',
    'INVALID_ID_TOKEN' ||
    'ID_TOKEN_EXPIRED' ||
    'ID_TOKEN_AUDIENCE_MISMATCH' ||
    'ID_TOKEN_ISSUER_MISMATCH' => '구글 인증을 확인하지 못했어요. 다시 시도해주세요.',
    'IDENTITY_PROVIDER_UNAVAILABLE' => '구글 인증 서버에 연결하지 못했어요. 잠시 후 다시 시도해주세요.',
    'INVALID_REGISTRATION_TOKEN' ||
    'REGISTRATION_TOKEN_EXPIRED' => '동의를 마칠 수 있는 시간이 지났어요. 로그인부터 다시 해주세요.',
    // 화면이 필수 동의를 받고 보냈는데도 서버가 거절한 경우다. 앱과 서버가 보는
    // 필수 항목이 어긋났다는 뜻이라 사용자가 체크를 더 해서 풀 수 있는 일이
    // 아니다. 화면이 스스로 막을 때와 같은 문구를 쓰면 구분이 되지 않는다.
    'REQUIRED_CONSENT_MISSING' => '서버가 동의 항목을 받아들이지 않았어요. 담당자에게 알려주세요.',
    'CONSENT_VERSION_MISMATCH' => '약관이 새로 바뀌었어요. 앱을 업데이트한 뒤 다시 시도해주세요.',
    'UNAUTHENTICATED' || 'SESSION_EXPIRED' => '로그인이 풀렸어요. 다시 로그인해주세요.',
    'ACCOUNT_NOT_FOUND' => '계정을 찾지 못했어요. 다시 로그인해주세요.',
    // `INVALID_REQUEST` 를 포함해 앱이 고칠 수 없는 경우다. 원인을 지어내지 않는다.
    _ => '로그인하지 못했어요. 잠시 후 다시 시도해주세요.',
  };
}
