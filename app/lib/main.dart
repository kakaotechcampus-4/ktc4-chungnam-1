import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/routes.dart';
import 'design/theme.dart';
import 'features/auth/session_refresher.dart';
import 'features/profile_setup/setup_controller.dart';

void main() {
  runApp(const ProviderScope(child: SaerokApp()));
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
