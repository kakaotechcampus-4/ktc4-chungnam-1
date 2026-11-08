import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/mascot.dart';
import 'onboarding_tutorial.dart';

/// B-1 처음 오셨네요.
///
/// 가입(약관 동의) 직후에 한 번 지난다. 정보를 묻기 전에 앱을 둘러볼 수 있게
/// 여기서는 입력으로 보내지 않고 홈으로 보낸다. 함께하는 분의 정보는 홈의
/// `오늘의 대화카드 받기` 를 누를 때 묻는다.
///
/// 화면이 뜨면 새록 소개([showOnboardingTutorial])를 바로 띄운다. 마지막 장의
/// `시작하기` 를 누르면 홈으로 가고, 건너뛰면 이 화면에 남아 다시 볼 수 있다.
/// 이 화면은 새 계정에서만 지나므로 본 적이 있는지 따로 저장하지 않는다.
/// 나중에는 설정의 도움말에서 다시 볼 수 있고, 이 화면과 소개 마지막 장에서
/// 그 자리를 알린다([tutorialHelpHint]).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showTutorial());
  }

  Future<void> _showTutorial() async {
    if (!mounted) return;
    final started = await showOnboardingTutorial(context);
    if (started && mounted) _goHome();
  }

  void _goHome() => context.go(AppRoutes.home);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeColors.background,
      body: ScreenBody(
        // 글자를 키우면 아래 버튼 두 개와 함께 화면을 넘을 수 있다.
        scrollable: true,
        bottom: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PrimaryButton(
              color: HomeColors.accent,
              loadingColor: HomeColors.accentLoading,
              label: '시작하기',
              onPressed: _goHome,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppTextButton(label: '새록 소개 다시 보기', onPressed: _showTutorial),
            const SizedBox(height: AppSpacing.xs),
            // 이 화면은 새 계정에서만 지난다. 나중에 볼 자리를 알린다.
            const Text(
              tutorialHelpHint,
              style: AppTypography.sub,
              textAlign: TextAlign.center,
            ),
          ],
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
              '면회에서 나눌 이야기를\n함께 준비해 드릴게요.',
              style: AppTypography.body,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
