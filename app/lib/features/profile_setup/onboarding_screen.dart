import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';

/// B-1 처음 오셨네요.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ScreenBody(
        bottom: PrimaryButton(
          label: '입력하러 가기',
          onPressed: () => context.go(AppRoutes.profileCreate),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/onboarding.webp',
              width: 260,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: AppSpacing.section),
            Text(
              '새록에\n처음 오셨네요!',
              style: AppTypography.screenTitle.copyWith(fontSize: 30),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              '어르신에 대해 알려주시면\n대화 카드를 만들어 드릴게요.',
              style: AppTypography.body,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
