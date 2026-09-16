import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../design/tokens.dart';

/// A-1 스플래시.
///
/// 잠깐 보여준 뒤 로그인으로 넘어간다. 로그인 상태를 확인하는 자리이기도 하지만
/// 인증은 아직 없으므로 지금은 시간만 두고 넘어간다.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const _delay = Duration(seconds: 2);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_delay, () {
      if (mounted) context.go(AppRoutes.login);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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
