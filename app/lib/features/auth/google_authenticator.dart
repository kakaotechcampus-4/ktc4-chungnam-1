/// 구글 로그인 SDK 를 감싼다.
///
/// 화면과 테스트는 [GoogleAuthenticator] 만 본다. SDK 를 직접 부르지 않으므로
/// 테스트에서 가짜 구현으로 바꿔 끼울 수 있다(`ADR-005` 의 주입 방식과 같다).
library;

import 'package:google_sign_in/google_sign_in.dart';

import '../../data/auth_api.dart';

/// 구글 로그인의 `serverClientId` 로 쓸 웹 클라이언트 ID.
///
/// 이 값이 ID 토큰의 `aud` 가 되므로 서버의 `SAEROK_GOOGLE_CLIENT_IDS` 와 같아야
/// 한다(`backend/README.md`). 저장소에 적지 않고 빌드할 때 넘긴다.
///
///     flutter run --dart-define=SAEROK_GOOGLE_SERVER_CLIENT_ID=<웹 클라이언트 ID>
const googleServerClientId = String.fromEnvironment(
  'SAEROK_GOOGLE_SERVER_CLIENT_ID',
);

abstract interface class GoogleAuthenticator {
  /// 구글 계정을 골라 ID 토큰을 받는다.
  ///
  /// 사용자가 창을 닫거나 취소하면 `null` 이다. 취소는 실패가 아니므로 오류를
  /// 띄우지 않는다. 그 밖의 실패는 [AuthGoogleFailure] 로 던진다.
  Future<String?> idToken();

  /// 다음 로그인에서 계정을 다시 고를 수 있게 한다.
  Future<void> signOut();
}

class GoogleSignInAuthenticator implements GoogleAuthenticator {
  GoogleSignInAuthenticator({this.serverClientId = googleServerClientId});

  final String serverClientId;

  /// `initialize` 는 한 번만 부를 수 있다. 실패하면 다시 부를 수 있도록 비운다.
  Future<void>? _initializing;

  @override
  Future<String?> idToken() async {
    if (serverClientId.isEmpty) {
      // 값이 없으면 서버가 `aud` 를 확인할 수 없어 어차피 거절당한다. 구글 창을
      // 띄우기 전에 설정 문제임을 알린다.
      throw const AuthGoogleFailure(
        misconfigured: true,
        detail: 'SAEROK_GOOGLE_SERVER_CLIENT_ID 가 비어 있다',
      );
    }

    await _initialize();

    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw const AuthGoogleFailure(
        misconfigured: true,
        detail: '이 플랫폼은 authenticate 를 지원하지 않는다',
      );
    }

    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (error) {
      // 취소와 중단은 사용자가 그만둔 것이다. 오류로 보여주지 않는다.
      if (error.code == GoogleSignInExceptionCode.canceled ||
          error.code == GoogleSignInExceptionCode.interrupted) {
        return null;
      }
      throw AuthGoogleFailure(
        misconfigured: _isConfiguration(error.code),
        detail: '${error.code}',
      );
    }

    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      // 서버에 보낼 것이 없다. 로그인한 것처럼 넘기지 않는다.
      throw const AuthGoogleFailure(
        misconfigured: true,
        detail: 'ID 토큰이 비어 있다. serverClientId 설정을 확인한다',
      );
    }
    return idToken;
  }

  @override
  Future<void> signOut() async {
    if (_initializing == null) return;
    await GoogleSignIn.instance.signOut();
  }

  Future<void> _initialize() async {
    final started =
        _initializing ??= GoogleSignIn.instance.initialize(
          serverClientId: serverClientId,
        );
    try {
      await started;
    } catch (error) {
      // 다음 시도에서 다시 부를 수 있게 비운다.
      _initializing = null;
      throw AuthGoogleFailure(misconfigured: true, detail: '$error');
    }
  }

  static bool _isConfiguration(GoogleSignInExceptionCode code) =>
      code == GoogleSignInExceptionCode.clientConfigurationError ||
      code == GoogleSignInExceptionCode.providerConfigurationError;
}
