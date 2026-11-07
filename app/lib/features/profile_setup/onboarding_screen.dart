import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/mascot.dart';

/// B-1 처음 오셨네요.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeColors.background,
      body: ScreenBody(
        bottom: PrimaryButton(
          color: HomeColors.accent,
          loadingColor: HomeColors.accentLoading,
          label: '입력하러 가기',
          onPressed: () => context.go(AppRoutes.profileCreate),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 홈과 같은 새싹 마스코트가 `><` 얼굴로 제자리에서 천천히 콩콩
            // 뛰며 하트를 띄운다. 처음 온 보호자를 반기는 자리다.
            const Mascot(size: 220, cheerful: true, hopping: true),
            const SizedBox(height: AppSpacing.section),
            Text(
              '새록에\n처음 오셨네요!',
              style: AppTypography.screenTitle.copyWith(fontSize: 30),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              '어르신에 대해 알려주시면\n함께 나눌 이야기를 준비해 드릴게요.',
              style: AppTypography.body,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
