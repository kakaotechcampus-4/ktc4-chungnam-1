/// 릴리스 빌드의 빌드 설정 검사.
///
/// `SAEROK_API_BASE_URL` 기본값은 에뮬레이터용 `http://10.0.2.2:8000` 이고
/// 릴리스 빌드는 평문 통신을 막는다(`android/app/src/debug/AndroidManifest.xml`
/// 에만 열어 두었다). 값을 넘기지 않고 릴리스를 만들면 모든 요청이 실패하는데,
/// 화면에는 일반 연결 오류로만 보여 원인을 찾기 어렵다. 그래서 릴리스 빌드는
/// 앱을 켤 때 설정을 먼저 보고, 잘못됐으면 다른 화면 대신 설정 오류 화면을 띄운다.
///
/// 디버그와 프로필 빌드는 검사하지 않는다. 개발 서버가 http 이기 때문이다.
library;

import 'package:flutter/material.dart';

import '../data/auth_api.dart' show apiBaseUrl;
import '../design/theme.dart';
import '../features/auth/google_authenticator.dart' show googleServerClientId;
import '../widgets/app_states.dart';

/// 릴리스 빌드에서 고쳐야 할 설정 하나.
///
/// 값 자체는 담지 않는다. 화면과 로그에 서버 주소나 클라이언트 ID 를 남기지
/// 않고 어떤 값을 고쳐야 하는지만 알린다.
enum ReleaseConfigProblem {
  /// `SAEROK_API_BASE_URL` 이 비어 있다.
  apiBaseUrlMissing('SAEROK_API_BASE_URL 이 비어 있어요.'),

  /// `SAEROK_API_BASE_URL` 이 https 주소가 아니다. scheme 이 없거나 다르다.
  apiBaseUrlNotHttps('SAEROK_API_BASE_URL 이 https 주소가 아니에요.'),

  /// `SAEROK_API_BASE_URL` 이 https 이지만 서버 주소로 쓸 수 없는 형식이다.
  /// 앞뒤 공백, 해석할 수 없는 문자열, host 없음, 사용자 정보(`user@`),
  /// query(`?`)와 fragment(`#`)가 여기에 든다. 요청 주소는 이 값 뒤에 경로를
  /// 이어 붙여 만드므로 query 나 fragment 가 있으면 경로가 엉뚱한 곳에 붙는다.
  apiBaseUrlMalformed(
    'SAEROK_API_BASE_URL 형식이 올바르지 않아요. '
    'https://host[:port][/path] 형태로만 적어 주세요.',
  ),

  /// `SAEROK_GOOGLE_SERVER_CLIENT_ID` 가 비어 있다.
  googleServerClientIdMissing('SAEROK_GOOGLE_SERVER_CLIENT_ID 가 비어 있어요.');

  const ReleaseConfigProblem(this.message);

  /// 설정 오류 화면에 한 줄로 보여 줄 문구다.
  final String message;
}

/// 빌드 설정에서 고쳐야 할 항목을 돌려준다. 문제가 없으면 빈 목록이다.
///
/// [isRelease] 가 `false` 면 늘 빈 목록이다. 디버그 동작을 바꾸지 않는다.
/// 서버 주소 문제는 많아야 하나만 알린다([apiBaseUrlProblem]).
List<ReleaseConfigProblem> releaseConfigProblems({
  required bool isRelease,
  required String apiBaseUrl,
  required String googleServerClientId,
}) {
  if (!isRelease) return const [];

  return [
    ?apiBaseUrlProblem(apiBaseUrl),
    if (googleServerClientId.trim().isEmpty)
      ReleaseConfigProblem.googleServerClientIdMissing,
  ];
}

/// 서버 주소에서 고칠 점 하나를 돌려준다. 쓸 수 있는 주소면 `null` 이다.
///
/// 비어 있음, https 아님, 형식 오류 순서로 본다. scheme 대소문자는 구분하지
/// 않는다(`Uri` 가 소문자로 바꾼다).
ReleaseConfigProblem? apiBaseUrlProblem(String apiBaseUrl) {
  final url = apiBaseUrl.trim();
  if (url.isEmpty) return ReleaseConfigProblem.apiBaseUrlMissing;

  final uri = Uri.tryParse(url);
  if (uri != null && uri.scheme != 'https') {
    return ReleaseConfigProblem.apiBaseUrlNotHttps;
  }
  final usable =
      uri != null &&
      url == apiBaseUrl &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment;
  return usable ? null : ReleaseConfigProblem.apiBaseUrlMalformed;
}

/// 이 빌드에 넘어온 값으로 검사한다.
List<ReleaseConfigProblem> currentReleaseConfigProblems({
  required bool isRelease,
}) => releaseConfigProblems(
  isRelease: isRelease,
  apiBaseUrl: apiBaseUrl,
  googleServerClientId: googleServerClientId,
);

/// 릴리스 설정이 잘못됐을 때 `SaerokApp` 대신 띄우는 앱이다.
///
/// 라우터, 세션 복원과 서버 요청을 시작하지 않는다. 고칠 방법은 다시 빌드하는
/// 것뿐이라 다시 시도 버튼을 두지 않는다.
class ReleaseConfigErrorApp extends StatelessWidget {
  const ReleaseConfigErrorApp({required this.problems, super.key});

  final List<ReleaseConfigProblem> problems;

  @override
  Widget build(BuildContext context) {
    final lines = [
      '앱 설정이 올바르지 않아 시작할 수 없어요. 앱 담당자에게 알려 주세요.',
      for (final problem in problems) problem.message,
    ];
    return MaterialApp(
      title: '새록',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Scaffold(
        body: SafeArea(child: ErrorStateView(message: lines.join('\n'))),
      ),
    );
  }
}
