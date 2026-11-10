/// 앱을 켤 때와 다시 돌아올 때 새 버전을 확인하고, 다 받으면 다시 시작을 권한다.
/// 앱이 구버전이라 생겼을 수 있는 문제가 있으면 업데이트가 필요하다고 알린다.
///
/// `MaterialApp.router` 의 `builder` 에 둔다. 어느 화면에 있든 화면 맨 위의 같은
/// 알림 띠([AppUpdateBanner])로 알린다. 알림 띠는 화면을 그 높이만큼 아래로 밀어
/// 상단바와 화면 아래의 주 버튼(카드 고르기의 `대화 시작하기` 등)을 가리지 않는다.
/// 예전에는 아래 알림 줄(SnackBar)로 띄웠는데, 저절로 닫히지 않아 아래 버튼을
/// 덮었다(UX 점검 2026-11-10, 10번).
///
/// 면회 흐름(사진, 녹음, 소감, 위로, 음성 다시 보내기) 동안에는 플레이의 안내 창도
/// 알림 띠도 띄우지 않고, 한 사이클을 마치고 홈에 돌아왔을 때 알린다. 면회 중에
/// 앱이 다시 시작되면 닫히지 않은 녹음 파일과 보내지 않은 소감이 남기 때문이다.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import 'app_update.dart';

/// 알림 띠 문구다. FE 초안이며 제품 문구로 확정하려면 PM 확인이 필요하다.
abstract final class AppUpdateMessages {
  /// 새 버전을 받아 두었다.
  static const ready = '새 버전을 받았어요. 다시 시작하면 바로 쓸 수 있어요.';

  /// 구버전이라 생겼을 수 있는 문제가 있었고, 새 버전을 아직 받지 않았다.
  static const needed = '새 버전이 나와서 지금 앱으로는 안 되는 기능이 있을 수 있어요. 업데이트해 주세요.';

  /// 구버전이라 생겼을 수 있는 문제가 있었고, 새 버전을 받아 두었다.
  static const neededReady =
      '새 버전이 나와서 지금 앱으로는 안 되는 기능이 있을 수 있어요. 다시 시작하면 새 버전으로 바뀌어요.';

  /// 서버가 업데이트를 요구했지만 앱 안에서 받을 새 버전을 찾지 못했다.
  static const neededFromStore = '새 버전으로 업데이트해야 쓸 수 있어요. Play 스토어에서 업데이트해 주세요.';

  static const restart = '다시 시작';
  static const update = '업데이트';
}

/// 업데이트 안내를 미루는 면회 흐름의 화면이다.
const _visitFlowPaths = {
  AppRoutes.visitPhoto,
  AppRoutes.visitRecord,
  AppRoutes.visitAddCards,
  AppRoutes.visitReview,
  AppRoutes.visitReviewDone,
  AppRoutes.visitUpload,
};

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
  /// 지금 띄운 알림. 없으면 알림 띠를 그리지 않는다.
  _Offer? _offer;

  /// 면회 흐름이라 안내를 미뤘는지. 홈에 돌아오면 다시 확인한다.
  bool _waitingForHome = false;

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
    // 오래 켜 둔 앱도 돌아올 때 확인한다. 알림 띠를 닫아 넘겼다면 이때 다시
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
        // 알림 띠를 띄운 채 면회를 시작했다. 닫고 홈에서 다시 알린다.
        if (_offer != null) {
          _close();
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

  /// 지금 상태와 화면에 맞는 알림 띠를 띄운다. 알릴 것이 없으면 그대로 둔다.
  void _present() {
    final update = ref.read(appUpdateControllerProvider);
    if (!update.needed && !update.downloaded) return;

    // 면회 화면에는 버튼 없는 알림도 띄우지 않고 홈에 돌아오면 알린다. 면회 중
    // 6-2 제출이 실패해도 녹음은 기기에 남아 업데이트 뒤에 다시 보낼 수 있다.
    if (_inVisitFlow) {
      _waitingForHome = true;
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

  /// 저절로 사라지지 않게 두고, 지금 넘기려면 닫기를 누른다. 다른 화면이 아래
  /// 알림 줄을 띄워도 닫히지 않는다.
  void _show(String text, {String? actionLabel, VoidCallback? onAction}) {
    if (_offer?.text == text) return;
    setState(() {
      _offer = actionLabel == null || onAction == null
          ? _Offer(text)
          : _Offer(text, actionLabel: actionLabel, onAction: onAction);
    });
  }

  void _close() {
    if (_offer == null) return;
    setState(() => _offer = null);
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

    final offer = _offer;
    final act = offer?.onAction;
    // 아래부터 쌓아 화면을 먼저, 알림 띠를 나중에 그린다. 화면 전환 경로의
    // 투명한 막(ModalBarrier)은 먼저 그려진 것의 의미 정보를 지우므로, 띠를
    // 먼저 그리면 화면 낭독기가 띠를 읽지 못한다. 읽는 순서는 위치대로 띠가
    // 먼저다.
    return Column(
      verticalDirection: VerticalDirection.up,
      children: [
        Expanded(
          // 알림 띠가 상태 표시줄 자리까지 차지하므로 화면은 그 아래에서
          // 시작한다. 화면 위젯은 그대로 두어 쌓인 화면과 입력이 남는다.
          child: MediaQuery.removePadding(
            context: context,
            removeTop: offer != null,
            child: widget.child,
          ),
        ),
        if (offer != null)
          AppUpdateBanner(
            text: offer.text,
            actionLabel: offer.actionLabel,
            // 예전 알림 줄처럼 누르면 닫고 할 일을 한다. 다 받으면 다시 시작을
            // 권하는 알림을 새로 띄운다.
            onAction: act == null
                ? null
                : () {
                    _close();
                    act();
                  },
            onClose: _close,
          ),
      ],
    );
  }
}

/// 띄울 알림의 문구와 버튼.
@immutable
class _Offer {
  const _Offer(this.text, {this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
}

/// 새 버전 알림 띠. 화면 맨 위에 두고 상태 표시줄 자리까지 연초록 면을 칠한 뒤
/// 글은 그 아래에 둔다.
///
/// 라우터 바깥(`MaterialApp.builder`)에 놓여 위에 Overlay 가 없다. 그래서 길게
/// 누르면 뜨는 도움말(tooltip)은 쓰지 않고 닫기 버튼에 이름만 붙인다.
class AppUpdateBanner extends StatelessWidget {
  const AppUpdateBanner({
    required this.text,
    required this.onClose,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String text;

  /// `다시 시작`, `업데이트`. 없으면 버튼 없이 알리기만 한다.
  final String? actionLabel;
  final VoidCallback? onAction;

  final VoidCallback onClose;

  /// 상태 표시줄 글자는 상단바처럼 어둡게 둔다. 상단바가 이 띠 아래로 밀려
  /// 상태 표시줄을 정하지 못하므로 띠가 정한다.
  static const _statusBar = SystemUiOverlayStyle(
    statusBarColor: Color(0x00000000),
    statusBarBrightness: Brightness.light,
    statusBarIconBrightness: Brightness.dark,
    systemStatusBarContrastEnforced: false,
  );

  @override
  Widget build(BuildContext context) {
    final label = actionLabel;
    final onAction = this.onAction;
    final acts = label != null && onAction != null;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _statusBar,
      child: Material(
        color: HomeColors.bubble,
        shape: const Border(bottom: BorderSide(color: HomeColors.bubbleLine)),
        // 뜨면 화면 낭독기가 문구를 읽는다(예전 알림 줄과 같다).
        child: Semantics(
          container: true,
          liveRegion: true,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.only(
                left: AppSpacing.screen,
                right: AppSpacing.xs,
                bottom: acts ? AppSpacing.xs : 0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Padding(
                          // 버튼이 있으면 버튼의 누르는 자리 여백이 글과 버튼
                          // 사이를 띄운다.
                          padding: EdgeInsets.only(
                            top: AppSpacing.md,
                            bottom: acts ? 0 : AppSpacing.md,
                          ),
                          child: Text(
                            text,
                            style: AppTypography.sub.copyWith(
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: onClose,
                        color: AppColors.ink,
                        constraints: const BoxConstraints.tightFor(
                          width: AppSizes.minTouch,
                          height: AppSizes.minTouch,
                        ),
                        icon: const Icon(Icons.close, semanticLabel: '알림 닫기'),
                      ),
                    ],
                  ),
                  if (acts)
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(
                          end: AppSpacing.sm,
                        ),
                        child: AppTextButton(label: label, onPressed: onAction),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
