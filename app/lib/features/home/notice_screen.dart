import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_states.dart';
import 'my_page_menu.dart';

/// 알림. 홈의 왼쪽 상단 알림 아이콘을 누르면 뜬다(피그마 설계 없음).
///
/// `ReportNotice` 는 상태 하나(만드는 중 / 도착)뿐이라 지금은 그 상태 한 건만
/// 보여준다. 날짜별로 여러 건이 쌓인 이력 화면을 만들려면 `app/lib/data/` 에
/// 데이터 모델을 새로 넓혀야 한다. 그전까지는 홈 배너와 같은 문구를 그대로
/// 다시 보여주는 자리다.
class NoticeScreen extends ConsumerWidget {
  const NoticeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(reportNoticeProvider);
    final report = ref.watch(visitReportProvider);

    return Scaffold(
      appBar: AppTopBar(
        actions: [
          // 홈의 메뉴 아이콘과 같다. 쓰임새가 정해지기 전까지 아무것도 열지 않는다.
          IconButton(
            onPressed: null,
            tooltip: '메뉴',
            icon: Icon(Icons.menu, size: 26, color: AppColors.textDisabled),
          ),
        ],
      ),
      body: ScreenBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.lg),
            Text('알림', style: AppTypography.screenTitle),
            const SizedBox(height: AppSpacing.xxl),
            Expanded(
              child: notice == null
                  ? const EmptyStateView(
                      message: '아직 새 알림이 없어요.',
                      icon: Icons.notifications_none,
                    )
                  : report.when(
                      loading: () => const LoadingView(),
                      error: (error, _) => ErrorStateView(
                        message: '알림을 불러오지 못했어요.',
                        onRetry: () => ref.invalidate(visitReportProvider),
                      ),
                      data: (data) => _NoticeRow(
                        date: data.visitDate,
                        generating: notice == ReportNotice.generating,
                        onTap: notice == ReportNotice.ready
                            ? () =>
                                  context.push(AppRoutes.reportOf(data.reportId))
                            : null,
                      ),
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        current: AppTab.home,
        onSelected: (tab) {
          switch (tab) {
            case AppTab.album:
              context.push(AppRoutes.album);
            case AppTab.home:
              context.go(AppRoutes.home);
            case AppTab.myPage:
              showMyPageMenu(context);
          }
        },
      ),
    );
  }
}

/// 알림 한 건이다. 지금은 이 한 건뿐이지만, 이력이 여러 건이 되면 목록의
/// 항목 하나가 되는 자리다.
class _NoticeRow extends StatelessWidget {
  const _NoticeRow({
    required this.date,
    required this.generating,
    required this.onTap,
  });

  final String? date;
  final bool generating;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // 문구는 홈 배너(home_screen.dart)와 같은 것을 그대로 쓴다. 새로 짓지 않는다.
    final title = generating ? '리포트를 만들고 있어요' : '리포트가 도착했어요';
    final hint = generating ? '조금만 기다려 주세요' : '눌러서 확인하기';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (date != null) ...[
                  Text(_friendlyDate(date!), style: AppTypography.bodyStrong),
                  const SizedBox(height: AppSpacing.xs),
                ],
                Text(title, style: AppTypography.body),
                const SizedBox(height: AppSpacing.xs),
                Text(hint, style: AppTypography.sub),
              ],
            ),
          ),
        ),
        const Divider(color: AppColors.line, height: 1),
      ],
    );
  }
}

/// `2026-08-21` 을 `8월 21일 만남` 으로 바꾼다. `home_screen.dart` 와 같은 규칙이다.
String _friendlyDate(String isoDate) {
  final parts = isoDate.split('-');
  if (parts.length != 3) return isoDate;
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (month == null || day == null) return isoDate;
  return '$month월 $day일 만남';
}
