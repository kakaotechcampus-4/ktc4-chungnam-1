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
/// 리포트 도착 알림은 별도 화면이 아니라 이 화면의 상태다(피그마 `HOME`,
/// `HOME-1`). 알림을 눌러야 리포트로 들어갈 수 있고, 확인하면 사라진다.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasNotice = ref.watch(reportNoticeProvider);
    final report = ref.watch(visitReportProvider);

    return Scaffold(
      body: Column(
        children: [
          _TopBar(hasNotice: hasNotice),
          Expanded(
            child: ScreenBody(
              bottom: Column(
                children: [
                  PrimaryButton(
                    label: '오늘의 대화카드 받기',
                    onPressed: () => context.push(AppRoutes.cards),
                  ),
                  if (hasNotice) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _ReportNotice(
                      // 리포트를 아직 읽는 중이면 날짜 없이 보여준다.
                      date: report.value?.visitDate,
                      onTap: () {
                        final id = report.value?.reportId;
                        if (id == null) return;
                        ref.read(reportNoticeProvider.notifier).dismiss();
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
                onPressed: () {},
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
              IconButton(
                onPressed: () => showMyPageMenu(context),
                tooltip: '메뉴',
                icon: const Icon(Icons.menu, size: 26),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
            const Icon(Icons.mail_outline, size: 24, color: AppColors.ink),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    date == null
                        ? '리포트가 도착했어요'
                        : '${_friendlyDate(date!)} 리포트가 도착했어요',
                    style: AppTypography.bodyStrong,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const Text('눌러서 확인하기', style: AppTypography.sub),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSub),
          ],
        ),
      ),
    );
  }

  /// `2026-08-21` 을 `8월 21일` 로 바꾼다.
  static String _friendlyDate(String isoDate) {
    final parts = isoDate.split('-');
    if (parts.length != 3) return isoDate;
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (month == null || day == null) return isoDate;
    return '$month월 $day일';
  }
}
