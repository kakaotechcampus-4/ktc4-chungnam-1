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
import 'report_text.dart';

/// G-1 리포트.
///
/// 일기 형식의 본문과 카드별 반응을 보여준다. 계약대로 의료적 해석과 대화 품질
/// 점수를 만들지 않는다.
class ReportScreen extends ConsumerWidget {
  const ReportScreen({
    required this.reportId,
    this.fromHistory = false,
    super.key,
  });

  final String reportId;

  /// 리포트 기록에서 들어왔는지. 이미 반영을 마친 회차라 변경 사항을 다시
  /// 묻지 않는다.
  final bool fromHistory;

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
        data: (data) => _Body(report: data, fromHistory: fromHistory),
      ),
    );
  }
}

/// 리포트에서 쓰는 글자 묶음이다.
///
/// 쉬운 모드는 **크기와 대비만** 다르고 위계는 같다. 글의 내용은 건드리지
/// 않는다. AI 가 쓴 요약을 FE 가 줄이거나 고쳐 쓰지 않는다(`CLAUDE.md`).
class _TypeSet {
  const _TypeSet({
    required this.title,
    required this.section,
    required this.cardTitle,
    required this.body,
    required this.sub,
    required this.chip,
    required this.cardPadding,
    required this.paragraphGap,
  });

  final TextStyle title;
  final TextStyle section;
  final TextStyle cardTitle;
  final TextStyle body;
  final TextStyle sub;
  final TextStyle chip;

  /// 글자가 커진 만큼 상자 안쪽도 넓힌다.
  final double cardPadding;

  /// 본문 문장 사이를 벌리는 높이.
  final double paragraphGap;

  /// 핫 리로드가 이미 초기화한 `static final` 을 다시 실행하지 않아, 값을 고쳐도
  /// 폰에 반영되지 않고 새 필드를 읽는 자리에서 터진다. 읽을 때마다 만든다.
  static _TypeSet get normal => _TypeSet(
    title: AppTypography.screenTitle,
    section: AppTypography.sectionTitle,
    cardTitle: AppTypography.bodyStrong,
    body: AppTypography.body.copyWith(height: 1.7),
    sub: AppTypography.sub,
    chip: AppTypography.caption,
    cardPadding: AppSpacing.xl,
    paragraphGap: AppSpacing.md,
  );

  /// 보호자가 눈으로 읽기 힘들 때 쓴다.
  ///
  /// 보조 글자의 흐린 회색(`#5C5C5C`, 6.7:1)을 본문 검정(18.9:1)으로 올린다.
  /// 노안에는 크기보다 대비가 더 잘 듣는다.
  static _TypeSet get easy => _TypeSet(
    title: AppTypography.screenTitle.copyWith(fontSize: 32),
    section: AppTypography.sectionTitle.copyWith(fontSize: 26),
    cardTitle: AppTypography.bodyStrong.copyWith(fontSize: 22),
    body: AppTypography.body.copyWith(fontSize: 22, height: 1.9),
    sub: AppTypography.sub.copyWith(fontSize: 20, color: AppColors.ink),
    chip: AppTypography.caption.copyWith(fontSize: 18),
    cardPadding: AppSpacing.xxl,
    paragraphGap: AppSpacing.lg,
  );
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.report, required this.fromHistory});

  final VisitReport report;
  final bool fromHistory;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

/// 카드 한 장을 리포트에서 어떻게 보여줄지.
enum _CardOutcome {
  /// 보호자가 쓰고 평가했다. AI 가 쓴 요약을 보여준다.
  summarized(''),

  /// 쓰지 않았다고 답했다.
  notUsed('이번 면회에서 다루지 않았어요'),

  /// 답하지 않고 넘어갔다.
  unanswered('확인하지 못했어요');

  const _CardOutcome(this.text);

  /// 요약 자리에 대신 적을 말.
  final String text;
}

class _BodyState extends ConsumerState<_Body> {
  /// 이 화면에 머무는 동안만 기억한다. 앱 전체로 넓히거나 저장하는 것은
  /// 저장 구조가 걸린 결정이라 따로 정한다(`app/CLAUDE.md`).
  bool _easy = false;

  /// 보호자 평가를 보고 카드 한 장을 어떻게 보여줄지 정한다.
  ///
  /// 평가를 아직 읽지 못했으면 AI 요약을 그대로 둔다. 읽지 못했다는 이유로
  /// `확인하지 못했어요` 를 띄우면 보호자가 답을 했는데도 안 했다고 말하게 된다.
  _CardOutcome _outcomeOf(String cardId, CaregiverEvaluation? evaluation) {
    if (evaluation == null) return _CardOutcome.summarized;

    final review = evaluation.cardReviews
        .where((r) => r.cardId == cardId)
        .firstOrNull;

    if (review == null) return _CardOutcome.unanswered;
    return review.wasUsed ? _CardOutcome.summarized : _CardOutcome.notUsed;
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final set = _easy ? _TypeSet.easy : _TypeSet.normal;
    // 보호자가 무엇이라 답했는지에 따라 카드별 반응의 표시가 갈린다.
    final evaluation = ref.watch(caregiverEvaluationProvider).value;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    // ScreenBody 의 bottom 슬롯이 차지하는 높이다. 그 위에 버튼을 띄운다.
    final slotHeight = widget.fromHistory
        ? AppSpacing.xxl
        : AppSpacing.lg + AppSizes.control + AppSpacing.xxl;

    return Stack(
      children: [
        ScreenBody(
          scrollable: true,
          // 이미 반영을 마친 회차에는 변경 사항을 다시 묻지 않는다.
          bottom: widget.fromHistory
              ? null
              : PrimaryButton(
                  label: '변경 사항 확인하기',
                  onPressed: () =>
                      context.push(AppRoutes.reportChangesOf(report.reportId)),
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.sm),
              Text(report.title, style: set.title),
              const SizedBox(height: AppSpacing.lg),

              // 기본 모드는 한 줄에 들어간다. 쉬운 모드는 글자가 커져 한 줄로는
              // 가로가 넘치므로 칩을 아래로 내린다.
              _MetaLine(
                date: _friendlyDate(report.visitDate),
                mood: report.mood?.label ?? unsupportedValueLabel,
                set: set,
                stacked: _easy,
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

              Text('오늘의 만남', style: set.section),
              const SizedBox(height: AppSpacing.lg),
              AppSurfaceBox(
                padding: EdgeInsets.all(set.cardPadding),
                child: _Summary(text: report.summaryText, set: set),
              ),
              const SizedBox(height: AppSpacing.section),

              Text('대화 카드별 반응', style: set.section),
              const SizedBox(height: AppSpacing.lg),

              if (report.cardSummaries.isEmpty)
                const EmptyStateView(
                  message: '이번 만남에서 다룬 카드가 없어요.',
                  icon: Icons.style_outlined,
                )
              else
                for (final summary in report.cardSummaries) ...[
                  _CardSummaryTile(
                    summary: summary,
                    outcome: _outcomeOf(summary.cardId, evaluation),
                    set: set,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],

              // 떠 있는 버튼이 마지막 카드를 가리지 않게 자리를 비워 둔다.
              const SizedBox(
                height: _EasyModeButton.height + AppSpacing.lg * 2,
              ),
            ],
          ),
        ),

        Positioned(
          right: AppSpacing.screen,
          bottom: bottomInset + slotHeight + AppSpacing.lg,
          child: _EasyModeButton(
            on: _easy,
            onChanged: (value) => setState(() => _easy = value),
          ),
        ),
      ],
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

/// 오늘의 만남 본문이다.
///
/// 한 덩어리로 그리지 않고 문장마다 문단을 나눈다. 글이 길면 어디까지 읽었는지
/// 놓치기 쉬운데, 이 요약은 대화 주제를 하나씩 적은 목록이라 문장 경계가 곧
/// 주제의 경계다.
class _Summary extends StatelessWidget {
  const _Summary({required this.text, required this.set});

  final String text;
  final _TypeSet set;

  @override
  Widget build(BuildContext context) {
    final paragraphs = splitIntoParagraphs(text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < paragraphs.length; i++) ...[
          if (i > 0) SizedBox(height: set.paragraphGap),
          Text(paragraphs[i], style: set.body),
        ],
      ],
    );
  }
}

/// 날짜와 기분을 적는 줄이다.
///
/// 기본 모드는 예전처럼 한 줄에 나란히 둔다. 쉬운 모드는 글자가 커져 한 줄로는
/// 가로가 넘치므로 칩을 아래로 내린다.
class _MetaLine extends StatelessWidget {
  const _MetaLine({
    required this.date,
    required this.mood,
    required this.set,
    required this.stacked,
  });

  final String date;
  final String mood;
  final _TypeSet set;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final label = Text(date, style: set.sub);
    final chip = AppChip(mood, style: set.chip);

    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label,
          const SizedBox(height: AppSpacing.md),
          chip,
        ],
      );
    }

    return Row(
      children: [
        label,
        const SizedBox(width: AppSpacing.md),
        chip,
      ],
    );
  }
}

/// 카드 하나의 반응. 글이 짧아도 상자 높이가 들쭉날쭉하지 않게 두 줄 자리를
/// 확보한다. 글이 길면 그만큼 늘어난다.
class _CardSummaryTile extends StatelessWidget {
  const _CardSummaryTile({
    required this.summary,
    required this.outcome,
    required this.set,
  });

  final CardSummary summary;
  final _CardOutcome outcome;
  final _TypeSet set;

  @override
  Widget build(BuildContext context) {
    final style = set.sub;
    final lineHeight = style.fontSize! * style.height!;
    // 글자 크기를 키운 기기에서도 두 줄을 유지한다.
    final twoLines = MediaQuery.textScalerOf(context).scale(lineHeight) * 2;
    final summarized = outcome == _CardOutcome.summarized;

    return AppCard(
      padding: EdgeInsets.all(set.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(summary.topicTitle, style: set.cardTitle),
          const SizedBox(height: AppSpacing.md),
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: twoLines),
            child: SizedBox(
              width: double.infinity,
              // 다루지 않은 카드에는 분석 결과가 없다. 요약 자리에 그 사실을
              // 대신 적는다.
              child: Text(
                summarized ? summary.summary : outcome.text,
                style: style,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 화면을 내려도 자리를 지키는 쉬운 모드 버튼이다.
///
/// 리포트를 읽는 사람은 보호자 본인이고 주 사용자가 50~60대다. 시스템 글자 크기
/// 설정을 찾지 못해도 이 자리에서 바로 키울 수 있게 둔다.
class _EasyModeButton extends StatelessWidget {
  const _EasyModeButton({required this.on, required this.onChanged});

  final bool on;
  final ValueChanged<bool> onChanged;

  static const height = AppSizes.control;

  @override
  Widget build(BuildContext context) {
    final foreground = on ? AppColors.background : AppColors.ink;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: on ? AppColors.ink : AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: on ? AppColors.ink : AppColors.line),
        boxShadow: AppShadows.high,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onChanged(!on),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 켜졌다는 것을 색만으로 알리지 않는다(`app/DESIGN.md` 접근성).
                Icon(
                  on ? Icons.check : Icons.format_size,
                  size: 24,
                  color: foreground,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '쉬운 모드',
                  style: AppTypography.bodyStrong.copyWith(color: foreground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
