import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
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
                  const Text(
                    '오늘은 무슨 주제로\n대화를 나눠볼까요?',
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
      child: SizedBox(
        height: AppSizes.topBar,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () => context.push(AppRoutes.notifications),
                tooltip: '알림',
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.notifications_none, size: 28),
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
              // 쓰임새가 정해지기 전까지 아무것도 열지 않는다.
              IconButton(
                onPressed: null,
                tooltip: '메뉴',
                icon: Icon(Icons.menu, size: 26, color: AppColors.textDisabled),
              ),
            ],
          ),
        ),
      ),
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
