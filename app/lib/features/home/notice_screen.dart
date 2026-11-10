import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_states.dart';
import 'failed_report_sheet.dart';

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
    final info = ref.watch(reportNoticeInfoProvider);
    // 목 데이터의 알림은 목 리포트를 가리킨다. 알림이 뜨기 전부터 읽어 둔다.
    final mockReport = info?.fromServer ?? false
        ? null
        : ref.watch(visitReportProvider);

    return Scaffold(
      backgroundColor: HomeColors.background,
      appBar: const AppTopBar(
        backgroundColor: HomeColors.background,
        title: '알림',
      ),
      body: ScreenBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.lg),
            Expanded(
              child: notice == null
                  ? const EmptyStateView(
                      message: '아직 새 알림이 없어요.',
                      icon: Icons.notifications_none,
                    )
                  // 서버의 알림은 리포트와 날짜를 함께 안다.
                  : mockReport == null
                  ? _NoticeRow(
                      date: info!.visitDate,
                      notice: notice,
                      onOpen: () {
                        final id = info.reportId;
                        // 회차 상태를 묻지 못했으면 다시 묻는다.
                        if (notice == ReportNotice.checkFailed) {
                          ref.read(reportNoticeProvider.notifier).retry();
                          return;
                        }
                        if (id == null) return;
                        // 홈 배너와 같이 녹음이 남았으면 공유도 고르게 한다.
                        if (notice == ReportNotice.failed &&
                            info.analysisId != null) {
                          openFailedReport(
                            context,
                            ref,
                            sessionId: id,
                            analysisId: info.analysisId!,
                          );
                          return;
                        }
                        context.push(switch (notice) {
                          // 앱을 떠난 사이 멈춘 면회 흐름은 그 회차로 이어간다.
                          ReportNotice.evaluationPending =>
                            AppRoutes.visitReviewOf(id),
                          ReportNotice.audioPending => AppRoutes.visitUploadOf(
                            id,
                          ),
                          // 작업 ID 를 모르면 다시 요청할 수 없다.
                          ReportNotice.failed => AppRoutes.home,
                          _ => AppRoutes.reportOf(id),
                        });
                      },
                    )
                  : mockReport.when(
                      loading: () => const LoadingView(),
                      error: (error, _) => ErrorStateView(
                        message: '알림을 불러오지 못했어요.',
                        onRetry: () => ref.invalidate(visitReportProvider),
                      ),
                      data: (data) => _NoticeRow(
                        date: data.visitDate,
                        notice: notice,
                        onOpen: () =>
                            context.push(AppRoutes.reportOf(data.reportId)),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 알림 한 건이다. 테두리 상자 안에 날짜(작은 회색), 제목(크고 굵게),
/// 안내(오른쪽 끝, 누를 수 있으면 화살표)를 둔다. 이력이 여러 건이 되면 목록의
/// 항목 하나가 되는 자리다.
class _NoticeRow extends StatelessWidget {
  const _NoticeRow({
    required this.date,
    required this.notice,
    required this.onOpen,
  });

  final String? date;
  final ReportNotice notice;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    // 문구는 홈 배너(home_screen.dart)와 같은 것을 그대로 쓴다. 새로 짓지 않는다.
    final (title, hint) = switch (notice) {
      ReportNotice.generating => ('리포트를 만들고 있어요', '조금만 기다려 주세요'),
      ReportNotice.ready => ('리포트가 도착했어요', '눌러서 확인하기'),
      ReportNotice.failed => ('리포트를 만들지 못했어요', '눌러서 분석 다시 요청하기'),
      ReportNotice.evaluationPending => ('평가 이어서 하기', '평가를 마치면 리포트를 만들어요'),
      ReportNotice.audioPending => ('음성 다시 보내기', '녹음을 보내면 리포트를 만들어요'),
      ReportNotice.checkFailed => ('리포트 상태를 확인하지 못했어요', '눌러서 다시 확인하기'),
    };
    // 만드는 중에는 결과 화면을 열지 않는다.
    final onTap = switch (notice) {
      ReportNotice.generating => null,
      _ => onOpen,
    };

    // 남는 높이를 채우지 않고 위에 붙는다.
    return Align(
      alignment: Alignment.topCenter,
      child: Material(
        color: AppColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: HomeColors.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 알림임을 알리는 편지 아이콘. 장식이라 화면 읽기에서 뺀다.
                const ExcludeSemantics(child: _NoticeIcon()),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  // 내용 높이만큼만 차지한다. 기본값(max)이면 화면을 채운다.
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (date != null) ...[
                        Text(_friendlyDate(date!), style: AppTypography.sub),
                        const SizedBox(height: AppSpacing.xs),
                      ],
                      Text(title, style: AppTypography.sectionTitle),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Flexible(
                            child: Text(
                              hint,
                              style: AppTypography.sub,
                              textAlign: TextAlign.right,
                            ),
                          ),
                          if (onTap != null) ...[
                            const SizedBox(width: AppSpacing.xs),
                            const Icon(
                              Icons.chevron_right,
                              size: 22,
                              color: AppColors.textSub,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 연회색 원 안의 편지 아이콘.
class _NoticeIcon extends StatelessWidget {
  const _NoticeIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(
        color: HomeColors.bubble,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.mail_outline_rounded,
        size: 24,
        color: HomeColors.accent,
      ),
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
