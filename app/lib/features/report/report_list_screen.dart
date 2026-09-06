import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_surfaces.dart';

/// 리포트 기록.
///
/// 피그마에 설계가 없어 새로 만든 화면이다. 홈의 도착 알림은 리포트를 확인하면
/// 사라지므로, 지난 리포트를 다시 보려면 이곳으로 들어온다.
///
/// 목 데이터에는 회차가 하나뿐이라 목록에도 한 건만 나온다.
class ReportListScreen extends ConsumerWidget {
  const ReportListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(visitReportProvider);

    return Scaffold(
      appBar: const AppTopBar(title: '리포트 기록'),
      body: report.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorStateView(
          message: '리포트 기록을 불러오지 못했어요.',
          onRetry: () => ref.invalidate(visitReportProvider),
        ),
        data: (data) => _Body(reports: [data]),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.reports});

  final List<VisitReport> reports;

  @override
  Widget build(BuildContext context) {
    if (reports.isEmpty) {
      return const EmptyStateView(
        message: '아직 만들어진 리포트가 없어요.\n면회를 마치면 여기에 쌓여요.',
        icon: Icons.description_outlined,
      );
    }

    return ScreenBody(
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.lg),
          Text('지난 만남 ${reports.length}개', style: AppTypography.sub),
          const SizedBox(height: AppSpacing.lg),

          for (final report in reports) ...[
            _ReportRow(report: report),
            const SizedBox(height: AppSpacing.lg),
          ],

          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.report});

  final VisitReport report;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => context.push(
        AppRoutes.reportOf(report.reportId, fromHistory: true),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.image),
            child: Image.asset(
              'assets/images/visitation.webp',
              width: 72,
              height: 72,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_friendlyDate(report.visitDate), style: AppTypography.sub),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  report.title,
                  style: AppTypography.bodyStrong,
                  maxLines: 2,
                ),
                const SizedBox(height: AppSpacing.sm),
                AppChip(report.mood.label, tone: ChipTone.weak),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textSub),
        ],
      ),
    );
  }

  /// `2026-08-21` 을 `2026년 8월 21일` 로 바꾼다.
  static String _friendlyDate(String isoDate) {
    final parts = isoDate.split('-');
    if (parts.length != 3) return isoDate;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return isoDate;
    return '$year년 $month월 $day일';
  }
}
