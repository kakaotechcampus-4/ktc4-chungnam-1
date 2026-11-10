import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/api_client.dart';
import '../../data/card_api.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_surfaces.dart';
import '../review/review_controller.dart';
import '../visit/visit_camera.dart';
import '../visit/visit_controller.dart';
import '../visit/visit_photos.dart';
import 'card_expand_cue.dart';
import 'card_generation_controller.dart';
import 'card_source_photo.dart';
import 'cards_controller.dart';
import 'photo_preparation_view.dart';
import 'sensitive_card_badge.dart';

/// C 오늘의 대화 카드.
///
/// 피그마 C-1 ~ C-3 은 별도 화면이 아니라 이 화면의 상태다. 카드를 누르면
/// 꼬리 질문이 펼쳐지고(C-2), 끝의 `카드 3장 더 보기` 를 누르거나 고리가 다 찰
/// 때까지 당기면 카드가 늘어난다(C-3).
class CardsScreen extends ConsumerWidget {
  const CardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileId = ref.watch(serverProfileIdProvider);

    // 홈과 같은 색감을 쓴다. 바탕은 오프화이트, 카드는 흰색이고 고르면 초록
    // 테두리다. 언덕 그림은 홈에만 둔다.
    return Scaffold(
      backgroundColor: HomeColors.background,
      appBar: const AppTopBar(backgroundColor: HomeColors.background),
      body: profileId.when(
        loading: () => const LoadingView(message: '오늘의 대화 카드를 만들고 있어요'),
        error: (error, _) => ErrorStateView(
          message: _failureMessage(error),
          onRetry: () => ref.invalidate(serverProfileIdProvider),
        ),
        data: (id) => id == null
            ? ErrorStateView(
                message: _failureMessage(StateError('고른 어르신이 없다')),
                onRetry: () => ref.invalidate(serverProfileIdProvider),
              )
            : _Generation(profileId: id),
      ),
    );
  }
}

/// 한 어르신의 카드 생성 상태. 들어올 때 묻는 중이 아니면 처음부터 확인한다.
class _Generation extends ConsumerStatefulWidget {
  const _Generation({required this.profileId});

  final String profileId;

  @override
  ConsumerState<_Generation> createState() => _GenerationState();
}

class _GenerationState extends ConsumerState<_Generation> {
  @override
  void initState() {
    super.initState();
    // 그리는 도중에는 provider 를 바꿀 수 없다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(cardGenerationProvider(widget.profileId).notifier).start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final generation = ref.watch(cardGenerationProvider(widget.profileId));
    final photos = ref.watch(cardPhotoPreparationProvider(widget.profileId));
    final controller = ref.read(
      cardGenerationProvider(widget.profileId).notifier,
    );

    if (photos != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: PhotoPreparationView(profileId: widget.profileId),
      );
    }
    return generation.when(
      loading: () => const LoadingView(message: '오늘의 대화 카드를 만들고 있어요'),
      error: (error, _) => ErrorStateView(
        message: _failureMessage(error),
        onRetry: controller.start,
      ),
      data: (status) => switch (status) {
        CardGenerationStatus.ready => const _Cards(),
        CardGenerationStatus.needsRefresh => const _Outdated(),
        // 4-2 는 실패 이유를 주지 않는다. 정보 부족과 그 밖의 실패를 가르지
        // 못하므로 공통 문구만 보여준다.
        CardGenerationStatus.failed => ErrorStateView(
          message: '대화 카드를 만들지 못했어요.\n다시 시도하면 새로 만들어요.',
          onRetry: controller.start,
        ),
        CardGenerationStatus.inVisit => _InVisit(profileId: widget.profileId),
        // 생성 흐름은 none 과 running 을 남기지 않는다. 아직 시작하지 않은
        // null 은 들어온 직후 한 프레임뿐이라 기다리는 화면을 그대로 둔다.
        null || CardGenerationStatus.none || CardGenerationStatus.running =>
          const LoadingView(message: '오늘의 대화 카드를 만들고 있어요'),
      },
    );
  }
}

String _failureMessage(Object error) => switch (error) {
  ApiNetworkFailure() => '서버에 연결하지 못했어요.\n인터넷 연결을 확인한 뒤 다시 시도해주세요.',
  _ => '대화 카드를 불러오지 못했어요.\n잠시 후 다시 시도해주세요.',
};

/// 평가 전 회차가 이 묶음을 쓰는 중이다(`inVisit`). 녹음을 시작한 뒤 녹음
/// 화면을 떠났거나, 그 뒤 앱을 다시 켠 경우다.
///
/// 그 회차의 평가를 이어서 한다(#234). 홈 배너의 `평가 이어서 하기` 와 같은
/// 화면이다. 녹음 화면으로는 돌려보내지 않는다. 녹음 화면을 떠날 때 파일을
/// 닫아 같은 파일에 이어 녹음할 수 없고, 새로 녹음하면 회차마다 파일 하나를
/// 받는 6-2 에 앞 녹음이 빠진다. 같은 묶음으로 면회를 다시 시작하면 5-1 이
/// `CARD_SET_ALREADY_USED` 로 거절하므로 카드 고르기도 두지 않는다.
class _InVisit extends ConsumerStatefulWidget {
  const _InVisit({required this.profileId});

  final String profileId;

  @override
  ConsumerState<_InVisit> createState() => _InVisitState();
}

class _InVisitState extends ConsumerState<_InVisit> {
  bool _finding = false;
  Object? _failure;

  Future<void> _continue() async {
    if (_finding) return;
    setState(() {
      _finding = true;
      _failure = null;
    });
    try {
      final sessionId = await _sessionInVisit();
      if (!mounted) return;
      if (sessionId == null) {
        // 그 사이 평가를 마쳤거나 묶음이 바뀌었다. 상태부터 다시 묻는다.
        unawaited(
          ref.read(cardGenerationProvider(widget.profileId).notifier).start(),
        );
        return;
      }
      unawaited(context.push(AppRoutes.visitReviewOf(sessionId)));
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _finding = false);
    }
  }

  /// 이 묶음을 쓰는 회차. 이번 실행에서 시작한 면회면 면회 상태가 안다. 앱을
  /// 다시 켰으면 4-3 의 `usedBySessionId` 다. 받아 둔 묶음은 회차를 만들기 전에
  /// 받은 것일 수 있어 새로 받는다.
  Future<String?> _sessionInVisit() async {
    final visit = startedVisitOf(
      ref.exists(visitControllerProvider)
          ? ref.read(visitControllerProvider)
          : null,
    );
    if (visit != null) return visit.sessionId;
    try {
      final set = await ref.refresh(currentCardSetProvider.future);
      return set.usedBySessionId;
    } on ApiServerFailure catch (failure) {
      // 쓸 묶음이 없다(`CARD_GENERATION_NOT_FOUND`). 평가를 마친 경우다.
      if (failure.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_finding) {
      return const LoadingView(message: '이어서 할 면회를 찾고 있어요');
    }
    final failure = _failure;
    if (failure != null) {
      return ErrorStateView(
        message: _failureMessage(failure),
        onRetry: _continue,
      );
    }
    return EmptyStateView(
      message: '아직 마치지 않은 면회가 있어요.\n평가를 마치면 새 대화 카드를 받을 수 있어요.',
      icon: Icons.style_outlined,
      actionLabel: '평가 이어서 하기',
      onAction: _continue,
    );
  }
}

/// 쓸 묶음이 준비된 뒤의 카드 고르기.
///
/// 받은 묶음(4-3)이 `needsRefresh` 면 카드를 보여주지 않고 [_Outdated] 로
/// 홈에 돌려보낸다. 4-2 는 `ready` 였지만 그 사이에 정보를 고친 경우다.
class _Cards extends ConsumerWidget {
  const _Cards();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(cardsControllerProvider);
    final setOutdated =
        ref.watch(currentCardSetProvider).value?.needsRefresh ?? false;
    if (setOutdated) return const _Outdated();

    return cards.when(
      loading: () => const LoadingView(message: '오늘의 대화 카드를 불러오고 있어요'),
      error: (error, _) => ErrorStateView(
        message: _failureMessage(error),
        // 실패한 묶음 조회를 버려야 다시 받는다.
        onRetry: () => ref.invalidate(currentCardSetProvider),
      ),
      data: (state) => _Body(state: state),
    );
  }
}

/// 받은 뒤 프로필이나 일대기를 고친 묶음이다.
///
/// 옛 카드는 보여주지 않고 고르거나 면회를 시작하지 못하게 한다. 새 카드는
/// 홈의 `오늘의 대화카드 받기` 에서 12장을 모두 다시 만든다(2026-11-01 #171
/// 에서 PM 확인). 만드는 동안 다른 화면을 볼 수 있게 하려는 것이다.
class _Outdated extends StatelessWidget {
  const _Outdated();

  @override
  Widget build(BuildContext context) {
    return EmptyStateView(
      message:
          '카드를 받은 뒤 어르신 정보가 바뀌었어요.\n'
          '홈에서 오늘의 대화카드 받기를 누르면\n새로 만들어요.',
      icon: Icons.style_outlined,
      actionLabel: '홈으로 가기',
      onAction: () => context.go(AppRoutes.home),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.state});

  final CardsState state;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

/// 카드를 고르는 본문.
///
/// 처음 3장을 보여주고, 목록 끝의 `카드 3장 더 보기` 버튼을 누르면 고리가 잠깐
/// 돌며 불러온 뒤 3장씩 더 보여준다. 당기기만으로는 찾지 못해 나머지 6장을 보지
/// 못할 수 있어 버튼으로 두었다(2026-11-10 UX 점검 5).
///
/// 당기기는 지름길로 남긴다. 끝을 넘겨 당기면 고무줄처럼 버티며
/// 늘어나고(BouncingScrollPhysics), 버튼 안의 고리가 당긴 만큼 채워진다. 손을 뗀
/// 채가 아니라 당기는 채로 고리가 한 바퀴 다 차야 버튼을 누른 것처럼 불러온다.
/// 살짝 밀었을 때 카드가 나오지 않게 하려는 것이다. 화면 낭독기는 버튼을
/// `대화 카드 n장 더 보기` 로 읽는다.
class _BodyState extends ConsumerState<_Body> {
  /// 이만큼 끝을 넘겨 당겨야 고리가 한 바퀴 찬다.
  static const _pullToLoad = 96.0;

  /// 고리가 다 찬 뒤 돌며 불러오는 시간.
  static const _loadingTime = Duration(milliseconds: 600);

  /// 끝을 넘겨 당긴 정도(0~1).
  double _pull = 0;

  /// 고리가 다 차 불러오는 중이다.
  bool _loading = false;

  Timer? _loadTimer;

  @override
  void dispose() {
    _loadTimer?.cancel();
    super.dispose();
  }

  bool _onScroll(ScrollNotification notification) {
    if (!widget.state.hasMore || _loading) return false;
    final metrics = notification.metrics;
    final over = metrics.pixels - metrics.maxScrollExtent;
    final pull = (over / _pullToLoad).clamp(0.0, 1.0);
    if (pull != _pull) setState(() => _pull = pull);

    // 손으로 당기는 중에 다 찼을 때만 불러온다. 놓은 뒤 튕겨 오르는 힘으로
    // 차는 것은 세지 않는다.
    final dragging =
        notification is ScrollUpdateNotification &&
        notification.dragDetails != null;
    if (pull >= 1 && dragging) _load();
    return false;
  }

  /// 고리를 잠깐 돌린 뒤 카드를 더 보여준다.
  void _load() {
    if (_loading || !widget.state.hasMore) return;
    setState(() => _loading = true);
    final still = MediaQuery.disableAnimationsOf(context);
    _loadTimer = Timer(still ? Duration.zero : _loadingTime, () {
      if (!mounted) return;
      ref.read(cardsControllerProvider.notifier).showMore();
      setState(() {
        _loading = false;
        _pull = 0;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final controller = ref.read(cardsControllerProvider.notifier);

    if (state.cards.isEmpty) {
      return const EmptyStateView(
        message: '오늘 준비된 대화 카드가 없어요.\n잠시 후 다시 확인해주세요.',
        icon: Icons.style_outlined,
      );
    }

    return ScreenBody(
      bottom: PrimaryButton(
        label: '대화 시작하기',
        color: HomeColors.accent,
        loadingColor: HomeColors.accentLoading,
        // 한 장도 고르지 않으면 시작하지 않는다.
        onPressed: state.canStart
            ? () {
                // 지난 회차의 녹음 시간, 소감과 사진이 남아 있지 않게 비운다.
                // 지난 사진의 사본은 갤러리에 원본이 있을 때만 지운다
                // (visit_photos.dart). 못 지워도 면회는 시작한다.
                ref.invalidate(visitControllerProvider);
                ref.invalidate(reviewControllerProvider);
                ref.invalidate(visitPhotoProvider);
                unawaited(
                  ref
                      .read(visitPhotosProvider)
                      .tidy()
                      .catchError((Object _) {}),
                );
                context.push(AppRoutes.visitPhoto);
              }
            : null,
      ),
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        // 웹과 데스크톱에서도 마우스나 트랙패드로 끌어 당겨 볼 수 있게 한다.
        // 기본값은 마우스 끌기를 받지 않아 고리를 채울 수 없다.
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(
            context,
          ).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
          child: SingleChildScrollView(
            // 카드가 적어 화면이 차지 않아도 당길 수 있고, 끝을 넘기면 버틴다.
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.sm),
                const Text('오늘의 대화 카드', style: AppTypography.screenTitle),
                const SizedBox(height: AppSpacing.md),
                const Text('오늘은 어떤 이야기를 나눠볼까요?', style: AppTypography.body),
                const SizedBox(height: AppSpacing.xl),

                _SelectionSummary(count: state.selectedIds.length),
                const SizedBox(height: AppSpacing.xl),

                for (final card in state.visibleCards) ...[
                  _CardTile(
                    card: card,
                    selected: state.selectedIds.contains(card.cardId),
                    expanded: state.expandedId == card.cardId,
                    onToggleSelected: () =>
                        controller.toggleSelected(card.cardId),
                    onToggleExpanded: () =>
                        controller.toggleExpanded(card.cardId),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],

                if (state.hasMore)
                  _MoreCardsButton(
                    pull: _pull,
                    loading: _loading,
                    count: state.remaining < CardRules.pageSize
                        ? state.remaining
                        : CardRules.pageSize,
                    onLoad: _load,
                  ),

                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 목록 끝의 `카드 n장 더 보기` 버튼. 누르면 고리가 돌며 불러온다. 끝을 넘겨
/// 당기면 안의 고리가 당긴 만큼 채워지고, 다 차면 누른 것처럼 불러온다.
class _MoreCardsButton extends StatelessWidget {
  const _MoreCardsButton({
    required this.pull,
    required this.loading,
    required this.count,
    required this.onLoad,
  });

  /// 당긴 정도(0~1).
  final double pull;
  final bool loading;

  /// 이번에 더 나올 장수.
  final int count;

  /// 버튼을 누르거나 화면 낭독기로 눌렀을 때. 당기지 않고 바로 불러온다.
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    // 불러오는 동안에는 누를 수 없는 버튼으로 읽는다(`app/DESIGN.md` 화면 낭독기).
    return Semantics(
      button: true,
      enabled: !loading,
      label: loading ? '카드를 불러오고 있어요' : '대화 카드 $count장 더 보기',
      onTap: loading ? null : onLoad,
      excludeSemantics: true,
      // 보조 버튼과 같은 흰 면, 진한 테두리다. 높이를 못 박지 않고 48 이상으로
      // 두어 글자를 키우면 함께 커진다.
      child: OutlinedButton(
        onPressed: loading ? null : onLoad,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          disabledForegroundColor: AppColors.textSub,
          backgroundColor: AppColors.background,
          // 불러오는 동안에도 흰 면을 둔다. 회색 면은 비활성처럼 보인다.
          disabledBackgroundColor: AppColors.background,
          side: const BorderSide(color: HomeColors.outline),
          minimumSize: const Size.fromHeight(AppSizes.minTouch),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.button)),
          ),
        ),
        // 고리와 문구를 한 줄에 둔다. 글자를 키워 줄이 넘치면 문구만 줄을 바꾼다.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                // 다 차기 전에는 당긴 만큼, 다 차면 돈다.
                value: loading ? null : pull,
                strokeWidth: 2.5,
                color: HomeColors.accent,
                backgroundColor: AppColors.line,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                loading ? '카드를 불러오고 있어요' : '카드 $count장 더 보기',
                style: AppTypography.bodyStrong.copyWith(
                  color: loading ? AppColors.textSub : AppColors.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionSummary extends StatelessWidget {
  const _SelectionSummary({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AppChip(
          count == 0 ? '아직 고르지 않았어요' : '$count개 선택함',
          tone: count == 0 ? ChipTone.weak : ChipTone.strong,
          accent: HomeColors.accent,
        ),
        const SizedBox(width: AppSpacing.md),
        Text('최대 ${CardRules.selectableCount}개까지', style: AppTypography.sub),
      ],
    );
  }
}

/// 카드 한 장. 접힌 상태에서는 주제와 안내 문장을, 펼치면 질문까지 보여준다.
class _CardTile extends StatelessWidget {
  const _CardTile({
    required this.card,
    required this.selected,
    required this.expanded,
    required this.onToggleSelected,
    required this.onToggleExpanded,
  });

  final ConversationCard card;
  final bool selected;
  final bool expanded;
  final VoidCallback onToggleSelected;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    // 카드 본문을 누르면 펼쳐지고, 오른쪽 원 둘레의 자리(폭 84)를 눌러야
    // 선택된다. 화면 낭독기도 두 동작을 따로 읽는다(접근성 보고서 10쪽).
    return SelectableCard(
      accent: HomeColors.accent,
      shadows: AppShadows.cardSoft,
      selected: selected,
      onTap: onToggleExpanded,
      expanded: expanded,
      tapHint: expanded ? '질문 접기' : '질문 펼치기',
      selectLabel: cardSelectLabel(card.cardTitle),
      onToggleSelected: onToggleSelected,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 사진에서 나온 카드는 그 사진을 맨 위에 둔다. 찾지 못하면 그리지 않는다.
          CardSourcePhoto(card: card),
          // 아픈 경험을 다루는 카드는 제목 위에 표시해 고르기 전에 보이게 한다.
          if (card.sensitive) ...[
            const SensitiveCardBadge(),
            const SizedBox(height: AppSpacing.sm),
          ],
          Text(card.cardTitle, style: AppTypography.bodyStrong),
          const SizedBox(height: AppSpacing.sm),
          // 이 카드로 무엇을 나누는지 알려주는 설명이다. 주제는 여러 면회에
          // 걸친 묶음이라 고르는 화면에는 두지 않는다.
          Text(card.description, style: AppTypography.sub),
          if (expanded) ...[
            const SizedBox(height: AppSpacing.lg),
            const Divider(),
            const SizedBox(height: AppSpacing.lg),
            Text(card.primaryQuestion, style: AppTypography.bodyStrong),
            const SizedBox(height: AppSpacing.md),
            for (final question in card.followUpQuestions)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('· ', style: AppTypography.sub),
                    Expanded(child: Text(question, style: AppTypography.sub)),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.xs),
          ] else
            const SizedBox(height: AppSpacing.md),
          CardExpandCue(expanded: expanded),
        ],
      ),
    );
  }
}

/// 카드 고르기 표시를 화면 낭독기가 읽는 이름이다. 카드 추가 화면도 같은 이름을 쓴다.
String cardSelectLabel(String cardTitle) => '$cardTitle 카드 고르기';
