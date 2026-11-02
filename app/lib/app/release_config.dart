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

  /// `SAEROK_API_BASE_URL` 이 https 주소가 아니다.
  apiBaseUrlNotHttps('SAEROK_API_BASE_URL 이 https 주소가 아니에요.'),

  /// `SAEROK_GOOGLE_SERVER_CLIENT_ID` 가 비어 있다.
  googleServerClientIdMissing('SAEROK_GOOGLE_SERVER_CLIENT_ID 가 비어 있어요.');

  const ReleaseConfigProblem(this.message);

  /// 설정 오류 화면에 한 줄로 보여 줄 문구다.
  final String message;
}

/// 빌드 설정에서 고쳐야 할 항목을 돌려준다. 문제가 없으면 빈 목록이다.
///
/// [isRelease] 가 `false` 면 늘 빈 목록이다. 디버그 동작을 바꾸지 않는다.
/// 서버 주소는 scheme 이 `https` 이고 host 가 있어야 통과한다.
List<ReleaseConfigProblem> releaseConfigProblems({
  required bool isRelease,
  required String apiBaseUrl,
  required String googleServerClientId,
}) {
  if (!isRelease) return const [];

  final problems = <ReleaseConfigProblem>[];

  final url = apiBaseUrl.trim();
  if (url.isEmpty) {
    problems.add(ReleaseConfigProblem.apiBaseUrlMissing);
  } else {
    final uri = Uri.tryParse(url);
    final isHttps =
        uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        url == apiBaseUrl;
    if (!isHttps) problems.add(ReleaseConfigProblem.apiBaseUrlNotHttps);
  }

  if (googleServerClientId.trim().isEmpty) {
    problems.add(ReleaseConfigProblem.googleServerClientIdMissing);
  }

  return problems;
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
