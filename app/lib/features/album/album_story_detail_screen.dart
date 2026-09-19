import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_surfaces.dart';

/// 이야기 상세. 목록(`album_stories_screen.dart`)에서 화살표를 누르면 뜬다.
///
/// "만남 평가"와 "대화 시간"은 계약에 없는 값이다. `app/lib/data/`,
/// `app/lib/app/`를 건드리지 않기로 해서 `LifeFact` 에 필드로 붙이거나 새
/// 경로를 등록하지 않았다. 대신 이 화면 안에서만 쓰는 [_extras] 로 두고,
/// 화면 이동도 go_router 대신 `Navigator.push` 로 연다.
class AlbumStoryDetailScreen extends ConsumerWidget {
  const AlbumStoryDetailScreen({required this.fact, super.key});

  final LifeFact fact;

  static const _extras = <String, (VisitMood, String)>{
    'fact_demo_001': (VisitMood.good, '15분 02초'),
    'fact_demo_002': (VisitMood.normal, '9분 47초'),
    'fact_demo_003': (VisitMood.good, '18분 20초'),
    'fact_demo_004': (VisitMood.good, '7분 15초'),
    'fact_demo_005': (VisitMood.good, '12분 34초'),
    'fact_demo_006': (VisitMood.normal, '10분 08초'),
    'fact_demo_007': (VisitMood.normal, '5분 40초'),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);

    return Scaffold(
      appBar: const AppTopBar(),
      body: profile.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorStateView(
          message: '이야기를 불러오지 못했어요.',
          onRetry: () => ref.invalidate(profileProvider),
        ),
        data: (bundle) => _Body(name: bundle.profile.name, fact: fact),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.name, required this.fact});

  final String name;
  final LifeFact fact;

  @override
  Widget build(BuildContext context) {
    final extra = AlbumStoryDetailScreen._extras[fact.factId];
    final heading = [
      if (fact.lifeStage != null) fact.lifeStage!.label,
      fact.title ?? fact.text,
    ].join(' - ');

    return ScreenBody(
      scrollable: true,
      bottom: SecondaryButton(
        label: '이야기 목록으로',
        onPressed: () => Navigator.of(context).pop(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.sm),
          Text('$name님의 이야기', style: AppTypography.sectionTitle),
          const SizedBox(height: AppSpacing.lg),
          Text(heading, style: AppTypography.screenTitle),
          const SizedBox(height: AppSpacing.xs),
          const Text('의 이야기를 담았어요.', style: AppTypography.sub),
          const SizedBox(height: AppSpacing.section),

          AspectRatio(
            aspectRatio: 4 / 3,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.image),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.section),

          _InfoRow(
            label: '이야기를 나눈 시점',
            value: _formatDateTime(fact.createdAt),
          ),
          const SizedBox(height: AppSpacing.md),
          if (extra != null) ...[
            _InfoRow(label: '보호자님의 만남 평가', value: extra.$1.label),
            const SizedBox(height: AppSpacing.md),
            _InfoRow(label: '대화 시간', value: extra.$2),
            const SizedBox(height: AppSpacing.md),
          ],

          const Text('대화 내용 요약', style: AppTypography.bodyStrong),
          const SizedBox(height: AppSpacing.sm),
          Text(fact.text, style: AppTypography.body),

          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  /// `2026-08-30T12:19:30+09:00` 를 `2026년 8월 30일 (일) 오후 12시 19분` 로 바꾼다.
  static String _formatDateTime(String iso) {
    final dt = DateTime.parse(iso);
    const weekdayNames = ['월', '화', '수', '목', '금', '토', '일'];
    final weekday = weekdayNames[dt.weekday - 1];
    final isPm = dt.hour >= 12;
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    return '${dt.year}년 ${dt.month}월 ${dt.day}일 ($weekday) '
        '${isPm ? '오후' : '오전'} $hour12시 ${dt.minute}분';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.sub),
          const SizedBox(height: AppSpacing.xs),
          Text(value, style: AppTypography.bodyStrong),
        ],
      ),
    );
  }
}
