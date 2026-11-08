import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';

/// 소개 한 장.
class TutorialPage {
  const TutorialPage({required this.title, required this.body, this.icon});

  /// 비우면 새록 로고를 보여준다.
  final IconData? icon;
  final String title;
  final String body;
}

/// 처음 오셨네요 위에 띄우는 새록 소개 다섯 장.
///
/// 가입 직후에는 정보를 묻지 않고 무슨 앱인지부터 알린다. 의료 효과나 기억
/// 회복처럼 들리는 말은 쓰지 않는다. 개인정보 장은 확정된 데이터 원칙 안에서만
/// 말한다(동의 범위 안에서 쓰고, 고치거나 지울 수 있다).
const tutorialPages = <TutorialPage>[
  TutorialPage(
    title: '새록을 소개할게요',
    body: '새록은 면회에서 나눌 이야기를\n미리 준비하고 기록하도록 돕는 앱이에요.',
  ),
  TutorialPage(
    icon: Icons.style_outlined,
    title: '알려주신 이야기로\n대화 카드를 만들어요',
    body: '함께하는 분의 하시던 일, 고향, 취미,\n가족 이야기를 바탕으로 면회에서\n꺼낼 대화 카드를 준비해 드려요.',
  ),
  TutorialPage(
    icon: Icons.auto_stories_outlined,
    title: '이야기가 쌓이면\n앨범을 만들 수 있어요',
    body: '알려주신 이야기와 면회 뒤 직접 확인한\n이야기를 일대기 앨범에 차곡차곡\n모아 둘 수 있어요.',
  ),
  TutorialPage(
    icon: Icons.lock_outline,
    title: '소중한 정보는\n조심스럽게 다뤄요',
    body:
        '입력하신 정보는 동의하신 범위 안에서\n대화 카드와 앨범을 만드는 데 써요.\n등록한 정보는 언제든 고치거나 지울 수 있어요.',
  ),
  TutorialPage(
    icon: Icons.touch_app_outlined,
    title: '준비가 되면\n대화카드 받기를 눌러주세요',
    body: '그때 함께하는 분의 기본 정보와\n이야기를 여쭤볼게요.\n',
  ),
];

/// 소개를 띄운다. 마지막 장의 `시작하기` 를 누르면 `true`, 건너뛰면 `false` 다.
Future<bool> showOnboardingTutorial(BuildContext context) async {
  final started = await showDialog<bool>(
    context: context,
    // 바깥을 눌러 실수로 닫지 않게 한다. 건너뛰기로 닫는다.
    barrierDismissible: false,
    builder: (context) => const OnboardingTutorial(),
  );
  return started ?? false;
}

/// 소개 창. 버튼으로 넘기고, 옆으로 밀어도 넘어간다.
///
/// 글자를 키우면 창이 길어지므로 한 장씩 그리고 창 전체를 스크롤한다. 높이를
/// 고정하는 `PageView` 는 쓰지 않는다.
class OnboardingTutorial extends StatefulWidget {
  const OnboardingTutorial({super.key});

  @override
  State<OnboardingTutorial> createState() => _OnboardingTutorialState();
}

class _OnboardingTutorialState extends State<OnboardingTutorial> {
  var _index = 0;

  bool get _last => _index == tutorialPages.length - 1;

  void _go(int index) {
    if (index < 0 || index >= tutorialPages.length) return;
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final page = tutorialPages[_index];

    return Dialog(
      backgroundColor: AppColors.background,
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.sm,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                // 마지막 장은 시작하기와 같은 일을 하므로 감춘다. 자리는 남긴다.
                child: Visibility(
                  visible: !_last,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: AppTextButton(
                    label: '건너뛰기',
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragEnd: (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  if (velocity < 0) _go(_index + 1);
                  if (velocity > 0) _go(_index - 1);
                },
                child: AnimatedSwitcher(
                  duration: still
                      ? Duration.zero
                      : const Duration(milliseconds: 250),
                  child: _PageContent(key: ValueKey(_index), page: page),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              _Dots(index: _index, total: tutorialPages.length),
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                color: HomeColors.accent,
                loadingColor: HomeColors.accentLoading,
                label: _last ? '시작하기' : '다음',
                onPressed: _last
                    ? () => Navigator.of(context).pop(true)
                    : () => _go(_index + 1),
              ),
              // 첫 장에서도 자리를 남겨 버튼이 오르내리지 않게 한다.
              Visibility(
                visible: _index > 0,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: Center(
                  child: AppTextButton(
                    label: '이전',
                    onPressed: () => _go(_index - 1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageContent extends StatelessWidget {
  const _PageContent({required this.page, super.key});

  final TutorialPage page;

  static const _art = 112.0;

  @override
  Widget build(BuildContext context) {
    final icon = page.icon;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 그림은 옆 글자가 말하는 것을 꾸밀 뿐이라 화면 읽기에서 뺀다.
        ExcludeSemantics(
          child: icon == null
              ? Image.asset(
                  'assets/images/logo.webp',
                  width: _art,
                  height: _art,
                )
              : Container(
                  width: _art,
                  height: _art,
                  decoration: const BoxDecoration(
                    color: HomeColors.bubble,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 56, color: HomeColors.accent),
                ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          page.title,
          style: AppTypography.sectionTitle,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(page.body, style: AppTypography.sub, textAlign: TextAlign.center),
      ],
    );
  }
}

/// 몇 번째 장인지. 화면 읽기에는 `5장 중 2장` 처럼 읽힌다.
class _Dots extends StatelessWidget {
  const _Dots({required this.index, required this.total});

  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$total장 중 ${index + 1}장',
      child: ExcludeSemantics(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < total; i++)
              Container(
                width: i == index ? 20 : 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: i == index ? HomeColors.accent : HomeColors.outline,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
