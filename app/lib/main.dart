import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/release_config.dart';
import 'app/router.dart';
import 'app/routes.dart';
import 'design/theme.dart';
import 'features/auth/session_refresher.dart';
import 'features/profile_setup/setup_controller.dart';

void main() {
  runApp(rootApp(isRelease: kReleaseMode));
}

/// 처음 띄울 앱을 고른다.
///
/// 릴리스 빌드에 서버 주소나 구글 클라이언트 ID 를 잘못 넘겼으면 로그인과 요청을
/// 시작하지 않고 설정 오류를 알린다. 디버그 빌드는 검사하지 않는다. 테스트가
/// [isRelease] 를 넘겨 이 연결을 확인한다.
Widget rootApp({required bool isRelease}) {
  final problems = currentReleaseConfigProblems(isRelease: isRelease);
  if (problems.isNotEmpty) return ReleaseConfigErrorApp(problems: problems);
  return const ProviderScope(child: SaerokApp());
}

class SaerokApp extends ConsumerStatefulWidget {
  const SaerokApp({super.key});

  @override
  ConsumerState<SaerokApp> createState() => _SaerokAppState();
}

class _SaerokAppState extends ConsumerState<SaerokApp> {
  late final _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    // 쓰는 도중 세션을 다시 받지 못하면 로그인부터 다시 한다. 로그아웃과 같이
    // 단말의 어르신을 비운다. 요청 코드는 화면을 옮기지 않으므로 여기서 옮긴다.
    ref.listen(sessionLossProvider, (_, loss) {
      if (loss == null) return;
      ref.read(sessionLossProvider.notifier).clear();
      forgetCareProfiles(ref);
      switch (loss) {
        case SessionSignedOut():
          _router.go(AppRoutes.signIn);
        case SessionConsentRequired(:final pending):
          _router.go(AppRoutes.googleConsent, extra: pending);
      }
    });

    return MaterialApp.router(
      title: '새록',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: _router,
    );
  }
}
