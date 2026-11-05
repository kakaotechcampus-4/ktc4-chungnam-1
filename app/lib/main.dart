import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/release_config.dart';
import 'app/router.dart';
import 'app/routes.dart';
import 'data/app_version.dart';
import 'design/theme.dart';
import 'features/app_update/app_update_watcher.dart';
import 'features/auth/session_refresher.dart';
import 'features/profile_setup/setup_controller.dart';
import 'features/push/push_messaging.dart';
import 'features/push/push_registration.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 요청마다 서버에 알릴 앱 버전. 읽지 못하면 헤더 없이 보낸다.
  final versionCode = await readAppVersionCode();
  runApp(rootApp(isRelease: kReleaseMode, versionCode: versionCode));
}

/// 처음 띄울 앱을 고른다.
///
/// 릴리스 빌드에 서버 주소나 구글 클라이언트 ID 를 잘못 넘겼으면 로그인과 요청을
/// 시작하지 않고 설정 오류를 알린다. 디버그 빌드는 검사하지 않는다. 테스트가
/// [isRelease] 를 넘겨 이 연결을 확인한다.
Widget rootApp({required bool isRelease, String? versionCode}) {
  final problems = currentReleaseConfigProblems(isRelease: isRelease);
  if (problems.isNotEmpty) return ReleaseConfigErrorApp(problems: problems);
  return ProviderScope(
    overrides: [
      appVersionCodeProvider.overrideWithValue(versionCode),
      // 실제 앱만 FCM 을 쓴다. 테스트는 기본값(아무것도 하지 않음)을 쓴다.
      pushMessagingProvider.overrideWithValue(FirebasePushMessaging()),
    ],
    child: const SaerokApp(),
  );
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
    // 앱이 켜져 있는 동안 로그인과 알림 수신 동의를 보고 이 기기를 푸시에
    // 등록하거나 등록을 푼다.
    ref.listen(pushRegistrationProvider, (_, _) {});

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
      builder: (context, child) => AppUpdateWatcher(
        router: _router,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
