/// 앱을 켤 때와 다시 돌아올 때 새 버전을 확인하고, 다 받으면 다시 시작을 권한다.
/// 앱이 구버전이라 생겼을 수 있는 문제가 있으면 업데이트가 필요하다고 알린다.
///
/// `MaterialApp.router` 의 `builder` 에 둔다. 어느 화면에 있든 같은 알림 줄로
/// 알린다. 단, 면회 흐름(사진, 녹음, 소감, 위로, 음성 다시 보내기) 동안에는
/// 플레이의 안내 창도 다시 시작이나 업데이트를 누르는 알림 줄도 띄우지 않고, 한
/// 사이클을 마치고 홈에 돌아왔을 때 알린다. 면회 중에 앱이 다시 시작되면 닫히지
/// 않은 녹음 파일과 보내지 않은 소감이 남기 때문이다. 면회 중에 업데이트가 필요해
/// 보이면 누를 것 없는 알림 줄로 홈에서 업데이트할 수 있다고만 알린다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import 'app_update.dart';

/// 알림 줄 문구다. FE 초안이며 제품 문구로 확정하려면 PM 확인이 필요하다.
abstract final class AppUpdateMessages {
  /// 새 버전을 받아 두었다.
  static const ready = '새 버전을 받았어요. 다시 시작하면 바로 쓸 수 있어요.';

  /// 구버전이라 생겼을 수 있는 문제가 있었고, 새 버전을 아직 받지 않았다.
  static const needed = '새 버전이 나와서 지금 앱으로는 안 되는 기능이 있을 수 있어요. 업데이트해 주세요.';

  /// 구버전이라 생겼을 수 있는 문제가 있었고, 새 버전을 받아 두었다.
  static const neededReady =
      '새 버전이 나와서 지금 앱으로는 안 되는 기능이 있을 수 있어요. 다시 시작하면 새 버전으로 바뀌어요.';

  /// 면회 중이라 지금은 업데이트하지 않는다.
  static const neededInVisit =
      '새 버전이 나와서 지금 앱으로는 안 되는 기능이 있을 수 있어요. 홈 화면으로 돌아가면 업데이트할 수 있어요.';

  /// 서버가 업데이트를 요구했지만 앱 안에서 받을 새 버전을 찾지 못했다.
  static const neededFromStore = '새 버전으로 업데이트해야 쓸 수 있어요. Play 스토어에서 업데이트해 주세요.';

  static const restart = '다시 시작';
  static const update = '업데이트';
}

/// 업데이트 안내를 미루는 면회 흐름의 화면이다. 세션을 잃었을 때 먼저 알리는
/// 화면과 같은 목록을 쓴다.
const _visitFlowPaths = AppRoutes.visitFlow;

class AppUpdateWatcher extends ConsumerStatefulWidget {
  const AppUpdateWatcher({
    super.key,
    required this.router,
    required this.child,
  });

  /// 지금 어느 화면인지 본다. `builder` 는 라우터 위에 있어
  /// `GoRouter.of(context)` 로 찾을 수 없으므로 직접 받는다.
  final GoRouter router;

  final Widget child;

  @override
  ConsumerState<AppUpdateWatcher> createState() => _AppUpdateWatcherState();
}

class _AppUpdateWatcherState extends ConsumerState<AppUpdateWatcher>
    with WidgetsBindingObserver {
  /// 지금 떠 있는 알림 줄과 그 문구. 같은 알림을 겹쳐 띄우지 않는다.
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _offer;
  String? _offerText;

  /// 떠 있는 알림 줄에 다시 시작이나 업데이트 버튼이 있는지.
  bool _offerActs = false;

  /// 면회 흐름이라 안내를 미뤘는지. 홈에 돌아오면 다시 확인한다.
  bool _waitingForHome = false;

  /// 면회 중에 업데이트가 필요하다고 이미 알렸는지. 이번 실행에서 한 번만 알린다.
  bool _toldInVisit = false;

  AppUpdateController get _controller =>
      ref.read(appUpdateControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.router.routerDelegate.addListener(_onRouteChanged);
    // 플레이의 확인은 화면에 떠 있는 액티비티가 있어야 한다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void didUpdateWidget(AppUpdateWatcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.router != widget.router) {
      oldWidget.router.routerDelegate.removeListener(_onRouteChanged);
      widget.router.routerDelegate.addListener(_onRouteChanged);
    }
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_onRouteChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 오래 켜 둔 앱도 돌아올 때 확인한다. 알림 줄을 닫아 넘겼다면 이때 다시
    // 알린다.
    if (state == AppLifecycleState.resumed) _check();
  }

  /// 지금 화면의 경로. 쌓아 올린(`push`) 화면까지 본다.
  String? get _path {
    final delegate = widget.router.routerDelegate;
    if (delegate.currentConfiguration.isEmpty) return null;
    return delegate.state.uri.path;
  }

  bool get _inVisitFlow => _visitFlowPaths.contains(_path);

  void _onRouteChanged() {
    // 화면이 바뀌는 도중일 수 있어 새 화면이 그려진 뒤에 본다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_inVisitFlow) {
        // 버튼이 있는 알림 줄을 띄운 채 면회를 시작했다. 닫고 홈에서 다시 알린다.
        if (_offer != null && _offerActs) {
          _offer!.close();
          _waitingForHome = true;
        }
        return;
      }
      if (_waitingForHome && _path == AppRoutes.home) {
        _waitingForHome = false;
        _check();
      }
    });
  }

  Future<void> _check() async {
    final mayAsk = !_inVisitFlow;
    if (!mayAsk) _waitingForHome = true;
    await _controller.check(mayAsk: mayAsk);
    if (mounted) _present();
  }

  /// 지금 상태와 화면에 맞는 알림 줄을 띄운다. 알릴 것이 없으면 그대로 둔다.
  void _present() {
    final update = ref.read(appUpdateControllerProvider);
    if (!update.needed && !update.downloaded) return;

    if (_inVisitFlow) {
      _waitingForHome = true;
      if (!update.needed || _toldInVisit) return;
      _toldInVisit = true;
      _show(
        update.newerVersion
            ? AppUpdateMessages.neededInVisit
            : AppUpdateMessages.neededFromStore,
      );
      return;
    }

    if (update.downloaded) {
      _show(
        update.needed ? AppUpdateMessages.neededReady : AppUpdateMessages.ready,
        actionLabel: AppUpdateMessages.restart,
        onAction: _controller.install,
      );
    } else if (update.newerVersion) {
      _show(
        AppUpdateMessages.needed,
        actionLabel: AppUpdateMessages.update,
        onAction: _controller.requestUpdate,
      );
    } else {
      _show(AppUpdateMessages.neededFromStore);
    }
  }

  void _show(String text, {String? actionLabel, VoidCallback? onAction}) {
    if (_offer != null && _offerText == text) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    _offer?.close();

    // 저절로 사라지지 않게 두고, 지금 넘기려면 닫기를 누른다.
    final offer = messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        persist: true,
        showCloseIcon: true,
        action: actionLabel == null || onAction == null
            ? null
            : SnackBarAction(label: actionLabel, onPressed: onAction),
      ),
    );
    _offer = offer;
    _offerText = text;
    _offerActs = onAction != null;
    offer.closed.then((_) {
      if (!identical(_offer, offer)) return;
      _offer = null;
      _offerText = null;
      _offerActs = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 뒤에서 받던 새 버전을 다 받았거나, 업데이트가 필요해 보이는 때다.
    ref.listen(appUpdateControllerProvider, (previous, next) {
      if (previous?.downloaded != next.downloaded ||
          previous?.needed != next.needed) {
        _present();
      }
    });
    return widget.child;
  }
}
