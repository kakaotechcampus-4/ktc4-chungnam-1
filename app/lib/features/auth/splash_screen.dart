import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../design/tokens.dart';
import '../../widgets/app_scaffold.dart';
import 'auth_messages.dart';
import 'google_sign_in_panel.dart';
import 'session_restore.dart';

/// A-1 스플래시. 따로 있던 A-2 로그인을 여기에 합쳤다.
///
/// 보관해 둔 세션이 있으면 되살려 홈으로 간다. 없으면 같은 화면의 로고 아래에
/// 구글 로그인 버튼을 띄운다. 앱을 켤 때마다 로그인 버튼을 누르지 않도록
/// 여기서 확인한다(PR #50 리뷰).
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({
    this.signedOut = false,
    this.sessionLost = false,
    super.key,
  });

  /// 로그아웃이나 탈퇴처럼 로그인이 풀린 것을 이미 알고 온 경우다. 복원을
  /// 확인하지 않고 로고를 기다리게 하지도 않고 곧바로 로그인 버튼을 띄운다.
  final bool signedOut;

  /// 쓰는 도중 세션을 다시 받지 못해 온 경우다. 보호자가 스스로 로그아웃한
  /// 것이 아니라서, 로그인 버튼 위에 왜 다시 로그인해야 하는지 알린다
  /// (UX 점검 8번). [signedOut] 과 함께 온다.
  final bool sessionLost;

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  /// 로고가 스치듯 지나가지 않게 두는 최소 시간이다. 복원이 이보다 빨리
  /// 끝나도 이만큼은 보여준다. 느리면 복원을 기다린다.
  static const _minimumShow = Duration(seconds: 2);

  /// 로그인 버튼을 띄울 차례다.
  late bool _signingIn = widget.signedOut;

  @override
  void initState() {
    super.initState();
    if (widget.signedOut) return;
    // 첫 프레임 뒤에 시작한다. build 중에 provider 를 건드리지 않는다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final shown = Future<void>.delayed(_minimumShow);
    final outcome = await ref.read(sessionRestorerProvider).restore();
    await shown;

    if (!mounted) return;
    if (outcome == SessionRestoreOutcome.restored) {
      context.go(AppRoutes.home);
      return;
    }
    setState(() => _signingIn = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeColors.background,
      body: ScreenBody(
        scrollable: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(flex: 3),
            Center(
              child: Image.asset(
                'assets/images/logo.webp',
                width: 160,
                height: 160,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              '새록',
              style: AppTypography.screenTitle.copyWith(fontSize: 36),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              '오늘의 만남을 준비해요',
              style: AppTypography.sub,
              textAlign: TextAlign.center,
            ),
            const Spacer(flex: 2),
            if (widget.sessionLost) ...[
              const _SessionLostNotice(),
              const SizedBox(height: AppSpacing.xl),
            ],
            // 로고 자리가 흔들리지 않도록 버튼이 나오기 전에도 공간을 남긴다.
            AnimatedOpacity(
              opacity: _signingIn ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: _signingIn
                  ? const GoogleSignInPanel()
                  : const SizedBox(height: _panelReserve),
            ),
            const SizedBox(height: AppSpacing.section),
          ],
        ),
      ),
    );
  }

  /// 로그인 버튼이 들어설 높이다. 버튼 높이와 같게 두어 버튼이 나타날 때 로고가
  /// 움직이지 않는다(글자 1배 기준. 글자를 키워 버튼이 늘면 그만큼 움직인다).
  static const _panelReserve = AppSizes.control;
}

/// 로그인이 풀려 다시 로그인해야 한다는 안내.
///
/// 보호자가 잘못한 것이 아니라서 경고 빨강(로그인 실패의 `AuthNotice`)이 아니라
/// 홈 알약과 같은 연초록 면에 둔다. 화면이 열리면 화면 낭독기가 바로 읽는다.
class _SessionLostNotice extends StatelessWidget {
  const _SessionLostNotice();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: HomeColors.bubble,
          border: Border.all(color: HomeColors.bubbleLine),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 22, color: HomeColors.accent),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                sessionLostSignInNotice,
                style: AppTypography.sub.copyWith(color: AppColors.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
