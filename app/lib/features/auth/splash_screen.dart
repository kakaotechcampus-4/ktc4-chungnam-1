import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../design/tokens.dart';
import 'session_restore.dart';

/// A-1 스플래시.
///
/// 보관해 둔 세션이 있으면 되살려 홈으로, 없으면 로그인으로 넘어간다. 앱을
/// 켤 때마다 로그인 버튼을 누르지 않도록 여기서 확인한다(PR #50 리뷰).
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  /// 로고가 스치듯 지나가지 않게 두는 최소 시간이다. 복원이 이보다 빨리
  /// 끝나도 이만큼은 보여준다. 느리면 복원을 기다린다.
  static const _minimumShow = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    // 첫 프레임 뒤에 시작한다. build 중에 provider 를 건드리지 않는다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final shown = Future<void>.delayed(_minimumShow);
    final outcome = await ref.read(sessionRestorerProvider).restore();
    await shown;

    if (!mounted) return;
    context.go(
      outcome == SessionRestoreOutcome.restored
          ? AppRoutes.home
          : AppRoutes.login,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/logo.webp',
              width: 160,
              height: 160,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('새록', style: AppTypography.screenTitle.copyWith(fontSize: 36)),
            const SizedBox(height: AppSpacing.md),
            const Text(
              '오늘의 만남을 준비해요',
              style: AppTypography.sub,
            ),
          ],
        ),
      ),
    );
  }
}
