import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/profile_avatar.dart';
import 'my_page_menu.dart';

/// 시작 화면.
///
/// 리포트 도착 알림은 별도 데이터가 아니라 이 화면의 상태다(피그마 `HOME`,
/// `HOME-1`). 알림을 눌러야 리포트로 들어갈 수 있고, 확인하면 사라진다.
///
/// 왼쪽 상단 알림 아이콘을 누르면 같은 상태를 다시 보여주는 `notice_screen.dart`
/// 가 뜬다. 상태를 새로 만들지 않고 `reportNoticeProvider` 를 그대로 본다.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(reportNoticeProvider);
    final report = ref.watch(visitReportProvider);
    final name = ref.watch(profileProvider).value?.profile.name;

    return Scaffold(
      body: Column(
        children: [
          // 만드는 중에는 아직 볼 것이 없으므로 점을 찍지 않는다.
          _TopBar(hasNotice: notice == ReportNotice.ready),
          Expanded(
            child: ScreenBody(
              bottom: Column(
                children: [
                  PrimaryButton(
                    label: '오늘의 대화카드 받기',
                    onPressed: () => context.push(AppRoutes.cards),
                  ),
                  // 같은 자리에서 만드는 중이 도착으로 바뀐다. 로딩 화면을
                  // 없앤 뒤로 만드는 중을 알리는 자리가 여기뿐이다.
                  if (notice != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    if (notice == ReportNotice.generating)
                      // 리포트를 아직 읽는 중이면 날짜 없이 보여준다.
                      _GeneratingNotice(date: report.value?.visitDate)
                    else
                      _ReportNotice(
                        date: report.value?.visitDate,
                        // 여기서는 지우지 않는다. 변경 사항을 반영해야 사라진다.
                        onTap: () {
                          final id = report.value?.reportId;
                          if (id == null) return;
                          context.push(AppRoutes.reportOf(id));
                        },
                      ),
                  ],
                ],
              ),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  Text(
                    '새록',
                    style: AppTypography.screenTitle.copyWith(
                      fontSize: 44,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  // 어느 어르신의 대화 카드를 받는지 가장 큰 안내에서 알린다.
                  // 이름을 읽는 동안에는 이름 없이 묻는다.
                  Text(
                    name == null
                        ? '오늘은 무슨 주제로\n대화를 나눠볼까요?'
                        : '오늘은 $name 어르신과\n무슨 주제로 대화를 나눠볼까요?',
                    style: AppTypography.body,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xxxl),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.image),
                    child: Image.asset('assets/images/main.webp'),
                  ),
                  const Spacer(flex: 3),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        current: AppTab.home,
        onSelected: (tab) {
          switch (tab) {
            case AppTab.album:
              context.push(AppRoutes.album);
            case AppTab.home:
              break;
            case AppTab.myPage:
              showMyPageMenu(context);
          }
        },
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.hasNotice});

  final bool hasNotice;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      // 오른쪽 알약이 벽과 상태바에 붙어 보이지 않게 위와 오른쪽을 띄운다.
      // 알림 아이콘은 버튼 안쪽 여백이 있어 왼쪽은 덜 띄운다.
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.screen,
          0,
        ),
        child: ConstrainedBox(
          // 글자를 키워 알약이 높아지면 함께 늘어나도록 높이를 못 박지 않는다.
          constraints: const BoxConstraints(minHeight: AppSizes.topBar),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () => context.push(AppRoutes.notifications),
                tooltip: '알림',
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.notifications_none, size: 32),
                    if (hasNotice)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: AppColors.danger,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.background,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const _ProfileSwitcher(),
            ],
          ),
        ),
      ),
    );
  }
}

/// 지금 보고 있는 어르신과 어르신을 바꾸는 버튼이다.
///
/// 사진만으로는 같은 성별의 어르신을 구분할 수 없어 이름을 함께 둔다. 다른
/// 어르신의 대화 카드를 받는 실수를 막으려는 자리다.
///
/// 원형 화살표는 목록 순서대로 다음 어르신으로 바로 바꾼다. 어르신이 한
/// 분이면 바꿀 대상이 없어 두지 않는다.
class _ProfileSwitcher extends ConsumerWidget {
  const _ProfileSwitcher();

  static const _photo = 32.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value?.profile;
    final canSwitch = ref.watch(
      careProfilesProvider.select((p) => p.entries.length > 1),
    );
    if (profile == null) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canSwitch)
          IconButton(
            onPressed: () => _switchToNext(context, ref),
            tooltip: '다음 어르신으로 바꾸기',
            // 알림 아이콘과 같은 크기다.
            icon: const Icon(Icons.sync, size: 32),
          ),
        // 전환 화면은 다음 작업에서 연결한다.
        Container(
          constraints: const BoxConstraints(minHeight: AppSizes.minTouch),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ProfileAvatar(gender: profile.gender, size: _photo),
              const SizedBox(width: AppSpacing.sm),
              ConstrainedBox(
                // 이름이 길어도 알림 아이콘을 밀어내지 않게 폭을 묶는다.
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  '${profile.name} 어르신',
                  style: AppTypography.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 다음 어르신으로 바꾸고 누구로 바뀌었는지 알린다.
  ///
  /// 한 번 누르면 바로 바뀌므로, 잘못 눌러도 알아챌 수 있게 이름을 말해 준다.
  Future<void> _switchToNext(BuildContext context, WidgetRef ref) async {
    ref.read(careProfilesProvider.notifier).selectNext();
    final next = await ref.read(profileProvider.future);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('${next.profile.name} 어르신으로 바꿨어요')),
      );
  }
}

/// 배너 안의 글 묶음이다.
///
/// 날짜를 제목에 붙이면 어떤 문구로도 한 줄에 들어가지 않는다. 쓸 수 있는 폭이
/// 230 인데 가장 짧은 조합인 `8월 21일 리포트를 만들고 있어요` 가 323 이다.
/// 날짜를 위 줄로 빼고 제목을 짧게 둔다.
class _NoticeText extends StatelessWidget {
  const _NoticeText({
    required this.date,
    required this.title,
    required this.hint,
  });

  final String? date;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (date != null) ...[
          Text(_friendlyDate(date!), style: AppTypography.caption),
          const SizedBox(height: AppSpacing.xs),
        ],
        Text(title, style: AppTypography.bodyStrong),
        const SizedBox(height: AppSpacing.xs),
        Text(hint, style: AppTypography.sub),
      ],
    );
  }
}

/// 리포트를 만드는 중임을 알리는 배너다.
///
/// 도착 배너와 같은 자리에 서고, 다 만들어지면 그 자리에서 도착 배너로 바뀐다.
/// 아직 들어갈 곳이 없으므로 누르지 않는다.
class _GeneratingNotice extends StatelessWidget {
  const _GeneratingNotice({required this.date});

  final String? date;

  static const _character = 64.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/images/logo.webp',
            width: _character,
            // 옆 글자가 같은 것을 말한다.
            excludeFromSemantics: true,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _NoticeText(
              date: date,
              title: '리포트를 만들고 있어요',
              hint: '조금만 기다려 주세요',
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ],
      ),
    );
  }
}

/// `2026-08-21` 을 `8월 21일 만남` 으로 바꾼다.
String _friendlyDate(String isoDate) {
  final parts = isoDate.split('-');
  if (parts.length != 3) return isoDate;
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (month == null || day == null) return isoDate;
  return '$month월 $day일 만남';
}

/// 리포트가 도착했음을 알리는 배너다. 이것을 눌러야 리포트로 들어간다.
class _ReportNotice extends StatelessWidget {
  const _ReportNotice({required this.date, required this.onTap});

  final String? date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          children: [
            const Icon(Icons.mail_outline, size: 32, color: AppColors.ink),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _NoticeText(
                date: date,
                title: '리포트가 도착했어요',
                hint: '눌러서 확인하기',
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSub),
          ],
        ),
      ),
    );
  }
}
