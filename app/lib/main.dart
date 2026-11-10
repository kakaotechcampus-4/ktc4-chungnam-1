import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app_locale.dart';
import 'app/release_config.dart';
import 'app/report_open_policy.dart';
import 'app/router.dart';
import 'app/routes.dart';
import 'data/app_version.dart';
import 'design/theme.dart';
import 'features/app_update/app_update_watcher.dart';
import 'features/auth/session_refresher.dart';
import 'features/profile_setup/setup_controller.dart';
import 'features/push/push_messaging.dart';
import 'features/push/push_registration.dart';
import 'features/visit/visit_signed_out_dialog.dart';

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

  late final SessionRefresher _refresher;

  @override
  void initState() {
    super.initState();
    _router.routerDelegate.addListener(_openPendingReport);
    // 면회 흐름에서 세션을 잃으면 화면을 옮기기 전에 먼저 알린다.
    _refresher = ref.read(sessionRefresherProvider)
      ..needsConfirmation = _inVisitFlow;
  }

  @override
  void dispose() {
    _router.routerDelegate.removeListener(_openPendingReport);
    if (_refresher.needsConfirmation == _inVisitFlow) {
      _refresher.needsConfirmation = () => false;
    }
    super.dispose();
  }

  /// 지금 화면이 면회 흐름인지. 쌓아 올린(`push`) 화면까지 본다.
  /// `currentConfiguration.uri` 는 쌓아 올린 화면 아래의 주소라 쓰지 않는다.
  bool _inVisitFlow() {
    final delegate = _router.routerDelegate;
    if (delegate.currentConfiguration.isEmpty) return false;
    return AppRoutes.visitFlow.contains(delegate.state.uri.path);
  }

  /// 면회 흐름에서 세션을 잃었다. 녹음 중이었으면 파일은 이미 닫았다
  /// ([sessionHoldProvider]). 세션을 지우기 전이라 뒤 화면은 그대로다. 이유를
  /// 알리고, 보호자가 확인하면 세션을 지워 로그인 화면으로 가게 한다.
  ///
  /// 계정이 사라졌으면(동의 화면으로 가는 경우) 새로 가입한 계정은 남긴 녹음을
  /// 찾지 못하므로 이어서 보낼 수 있다고 말하지 않는다. 이미 보낸 녹음도
  /// 이어서 보낼 것이 없어 말하지 않는다([visitRecordingKept]).
  Future<void> _confirmSessionLoss(SessionLoss loss) async {
    final recordingKept =
        loss is SessionSignedOut && await visitRecordingKept(ref);
    if (!mounted) return;
    // 만남을 끝내면 파일을 닫은 직후 소감 화면을 쌓는다. 창을 먼저 띄우면 새
    // 화면이 창을 덮으므로, 그 이동이 그려진 다음 프레임 뒤에 띄운다.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final navigator = _router.routerDelegate.navigatorKey.currentContext;
    if (navigator != null && navigator.mounted) {
      await showVisitSignedOutDialog(navigator, recordingKept: recordingKept);
    }
    if (!mounted) return;
    await _refresher.confirmLoss();
  }

  /// 리포트 완료 알림을 눌렀으면 보기만 하는 화면에서 그 리포트를 연다.
  ///
  /// 스플래시, 로그인, 녹음과 평가처럼 하던 일이 있는 화면에서는 기다린다
  /// ([canOpenReportOver]). 지금 화면 위에 리포트를 올려 뒤로 가면 돌아온다.
  void _openPendingReport() {
    if (ref.read(pendingReportOpenProvider) == null) return;
    final location = _router.routerDelegate.currentConfiguration.uri.path;
    if (!canOpenReportOver(location)) return;
    final sessionId = ref.read(pendingReportOpenProvider.notifier).take();
    if (sessionId == null) return;
    // 이미 그 리포트를 보고 있으면 한 번 더 올리지 않는다.
    if (location == AppRoutes.reportOf(sessionId)) return;
    // 라우터가 이동을 알리는 중에 다시 이동하지 않도록 다음 차례로 미룬다.
    Future.microtask(() => _router.push(AppRoutes.reportOf(sessionId)));
  }

  @override
  Widget build(BuildContext context) {
    // 앱이 켜져 있는 동안 로그인과 알림 수신 동의를 보고 이 기기를 푸시에
    // 등록하거나 등록을 푼다.
    ref.listen(pushRegistrationProvider, (_, _) {});
    ref.listen(pendingReportOpenProvider, (_, _) => _openPendingReport());

    // 쓰는 도중 세션을 다시 받지 못하면 로그인부터 다시 한다. 로그아웃과 같이
    // 단말의 어르신을 비운다. 요청 코드는 화면을 옮기지 않으므로 여기서 옮긴다.
    // 로그인 화면은 왜 다시 로그인해야 하는지 알린다.
    ref.listen(sessionLossProvider, (_, loss) {
      if (loss == null) return;
      ref.read(sessionLossProvider.notifier).clear();
      forgetCareProfiles(ref);
      switch (loss) {
        case SessionSignedOut():
          _router.go(AppRoutes.signInAfterSessionLoss);
        case SessionConsentRequired(:final pending):
          _router.go(AppRoutes.googleConsent, extra: pending);
      }
    });
    // 면회 흐름에서 잃었으면 옮기기 전에 확인 창부터 띄운다.
    ref.listen(unconfirmedSessionLossProvider, (_, loss) {
      if (loss != null) _confirmSessionLoss(loss);
    });

    return MaterialApp.router(
      title: '새록',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: appLocale,
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      routerConfig: _router,
      builder: (context, child) => AppUpdateWatcher(
        router: _router,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
