import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_surfaces.dart';

/// G-1 리포트.
///
/// 일기 형식의 본문과 카드별 반응을 보여준다. 계약대로 의료적 해석과 대화 품질
/// 점수를 만들지 않는다.
class ReportScreen extends ConsumerWidget {
  const ReportScreen({required this.reportId, super.key});

  final String reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(visitReportProvider);

    return Scaffold(
      appBar: const AppTopBar(),
      body: report.when(
        loading: () => const LoadingView(message: '리포트를 여는 중이에요'),
        error: (error, _) => ErrorStateView(
          message: '리포트를 불러오지 못했어요.',
          onRetry: () => ref.invalidate(visitReportProvider),
        ),
        data: (data) => _Body(report: data),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.report});

  final VisitReport report;

  @override
  Widget build(BuildContext context) {
    return ScreenBody(
      scrollable: true,
      bottom: PrimaryButton(
        label: '변경 사항 확인하기',
        onPressed: () =>
            context.push(AppRoutes.reportChangesOf(report.reportId)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.sm),
          Text(report.title, style: AppTypography.screenTitle),
          const SizedBox(height: AppSpacing.lg),

          Row(
            children: [
              Text(_friendlyDate(report.visitDate), style: AppTypography.sub),
              const SizedBox(width: AppSpacing.md),
              AppChip(report.mood.label),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),

          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.image),
            child: Image.asset(
              'assets/images/visitation.webp',
              height: 240,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: AppSpacing.section),

          const Text('오늘의 만남', style: AppTypography.sectionTitle),
          const SizedBox(height: AppSpacing.lg),
          AppSurfaceBox(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text(
              report.summaryText,
              style: AppTypography.body.copyWith(height: 1.7),
            ),
          ),
          const SizedBox(height: AppSpacing.section),

          const Text('대화 카드별 반응', style: AppTypography.sectionTitle),
          const SizedBox(height: AppSpacing.lg),

          if (report.cardSummaries.isEmpty)
            const EmptyStateView(
              message: '이번 만남에서 다룬 카드가 없어요.',
              icon: Icons.style_outlined,
            )
          else
            for (final summary in report.cardSummaries) ...[
              _CardSummaryTile(summary: summary),
              const SizedBox(height: AppSpacing.lg),
            ],

          const SizedBox(height: AppSpacing.lg),
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

/// 카드 하나의 반응. 글이 짧아도 상자 높이가 들쭉날쭉하지 않게 두 줄 자리를
/// 확보한다. 글이 길면 그만큼 늘어난다.
class _CardSummaryTile extends StatelessWidget {
  const _CardSummaryTile({required this.summary});

  final CardSummary summary;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.sub;
    final lineHeight = style.fontSize! * style.height!;
    // 글자 크기를 키운 기기에서도 두 줄을 유지한다.
    final twoLines = MediaQuery.textScalerOf(context).scale(lineHeight) * 2;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(summary.topicTitle, style: AppTypography.bodyStrong),
          const SizedBox(height: AppSpacing.md),
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: twoLines),
            child: SizedBox(
              width: double.infinity,
              child: Text(summary.summary, style: style),
            ),
          ),
        ],
      ),
    );
  }
}
