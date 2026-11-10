import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show OrdinalSortKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/models.dart';
import '../../design/tokens.dart';
import '../../widgets/app_states.dart';
import '../../widgets/recording_pulse.dart';
import '../cards/card_source_photo.dart';
import 'visit_controller.dart';

/// E-3, E-4 면회 중 대화 카드.
///
/// 화면이 아니라 녹음 화면 위로 올라오는 팝업이다. 보호자가 휴대전화를 들었다
/// 놨다 하지 않고 바닥에 둔 채 곁눈질로 볼 수 있게 만들었다. 그래서 질문 글자가
/// 다른 화면보다 크고, 화면을 크게 둘로 나눠 위는 메인 질문, 아래는 꼬리 질문을
/// 둔다.
///
/// 내려서 닫으면 녹음 화면으로 돌아가고, 거기서 정지를 눌러 대화를 마친다.
///
/// [controller] 를 주면 시트가 그 움직임을 따른다. 녹음 화면에서 손가락으로
/// 끌어올리는 동안 시트가 손가락을 따라오게 하는 데 쓴다.
Future<void> showVisitCardsSheet(
  BuildContext context, {
  AnimationController? controller,
}) {
  return showModalBottomSheet<void>(
    context: context,
    transitionAnimationController: controller,
    isScrollControlled: true,
    backgroundColor: HomeColors.background,
    // 위쪽 빈 곳을 누르면 닫힌다.
    barrierColor: Colors.black54,
    // 지정하지 않으면 앱 언어(영어)의 `Scrim` 이 읽힌다. 보고서 8쪽은 마이페이지
    // 메뉴를 짚었고, 같은 문제라 이 시트에도 붙인다.
    barrierLabel: '대화 카드 닫기',
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
    ),
    builder: (context) => FractionallySizedBox(
      // 화면의 5분의 4까지 올라온다.
      heightFactor: visitCardsSheetHeightFactor,
      child: const _SheetBody(),
    ),
  );
}

/// 녹음 화면에서 손가락으로 끄는 동안 그리는 시트 모양이다.
///
/// 끄는 도중에 [showVisitCardsSheet] 로 시트를 띄우면 Flutter 가 진행 중인
/// 손가락 입력을 끊는다. 그래서 끄는 동안에는 녹음 화면 위에 같은 모양을 직접
/// 그려 손가락을 따라오게 하고, 손을 떼면 그 높이에서 진짜 시트로 이어 받는다.
class VisitCardsSheetPreview extends StatelessWidget {
  const VisitCardsSheetPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const Material(
      color: HomeColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.card),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: _SheetBody(),
    );
  }
}

/// 시트가 화면 높이에서 차지하는 비율.
const visitCardsSheetHeightFactor = 0.8;

class _SheetBody extends ConsumerWidget {
  const _SheetBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visit = ref.watch(visitControllerProvider);

    return visit.when(
      loading: () => const LoadingView(),
      error: (error, _) => const ErrorStateView(message: '대화 카드를 불러오지 못했어요.'),
      data: (state) {
        if (state.cards.isEmpty) {
          return EmptyStateView(
            message: '고른 대화 카드가 없어요.\n카드를 추가해 보세요.',
            icon: Icons.style_outlined,
            actionLabel: '대화 카드 추가',
            onAction: () => context.push(AppRoutes.visitAddCards),
          );
        }
        return _Cards(state: state);
      },
    );
  }
}

class _Cards extends ConsumerStatefulWidget {
  const _Cards({required this.state});

  final VisitState state;

  @override
  ConsumerState<_Cards> createState() => _CardsState();
}

class _CardsState extends ConsumerState<_Cards> {
  /// 카드 추가 화면에 가 있는 동안 보여줄 막대 칸 수. 그동안 늘어난 카드의
  /// 칸은 돌아온 뒤에 하나씩 자라 들어오게 하려고 잠시 숨긴다.
  int? _hiddenFrom;

  Future<void> _openAddCards() async {
    setState(() => _hiddenFrom = widget.state.cards.length);
    await context.push(AppRoutes.visitAddCards);
    if (!mounted) return;
    setState(() => _hiddenFrom = null);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final controller = ref.read(visitControllerProvider.notifier);
    final card = state.currentCard!;

    return Column(
      children: [
        _SheetTop(state: state),
        _CardBar(
          state: state,
          shownCount: _hiddenFrom ?? state.cards.length,
          onSelect: controller.goToCard,
        ),

        // 남은 자리를 크게 둘로 나눈다.
        Expanded(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Column(
                children: [
                  // 화면 낭독기는 메인 질문, 꼬리 질문, 이전, 다음 순서로
                  // 읽는다. 버튼이 두 영역 경계에 걸쳐 있어 위치만으로 두면
                  // 꼬리 질문보다 먼저 읽힐 수 있다.
                  Expanded(
                    child: Semantics(
                      sortKey: const OrdinalSortKey(0),
                      child: _MainQuestion(card: card),
                    ),
                  ),
                  Expanded(
                    child: Semantics(
                      sortKey: const OrdinalSortKey(1),
                      // 카드를 바꾸면 꼬리 질문 넘김 효과 없이 바로 바꾼다.
                      // 밀려 나가는 효과는 같은 카드 안에서 넘길 때만 보인다.
                      child: _FollowUpQuestion(
                        key: ValueKey(card.cardId),
                        question: state.currentFollowUp ?? '',
                        index: state.followUpCount == 0
                            ? 0
                            : state.followUpIndex % state.followUpCount,
                        turn: state.followUpIndex,
                        count: state.followUpCount,
                        onTap: controller.nextFollowUp,
                      ),
                    ),
                  ),
                ],
              ),

              // 두 영역의 경계 한가운데에 이전, 다음 버튼을 나란히 놓는다.
              Positioned.fill(
                child: Align(
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        sortKey: const OrdinalSortKey(2),
                        child: _CardStepButton(
                          forward: false,
                          // 끝에서 처음으로 돌아가므로 카드가 두 장 이상이면
                          // 늘 누를 수 있다.
                          enabled: state.cards.length > 1,
                          onTap: controller.previousCard,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Semantics(
                        sortKey: const OrdinalSortKey(3),
                        child: _CardStepButton(
                          forward: true,
                          enabled: state.cards.length > 1,
                          onTap: controller.nextCard,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        _AddCardsBar(onTap: _openAddCards),
      ],
    );
  }
}

/// 시트 맨 위. 손잡이 바로 아래에 녹음 상태와 시간을 둔다.
///
/// 시트가 화면의 5분의 4를 덮어 녹음 화면의 `녹음 중이에요` 와 시간이 가려졌다
/// (2026-11-10 UX 점검 7번). 녹음이 이어지는지 보려고 시트를 내리지 않아도 되게
/// 여기 작게 다시 보인다. 원래 손잡이 아래 여백과 카드 막대 위 여백을 이 줄에
/// 내주어 글자 1배에서는 시트 안 높이가 그대로이고, 메인 질문의 자리도 줄지
/// 않는다. 그래서 시트 높이([visitCardsSheetHeightFactor])는 바꾸지 않았다.
class _SheetTop extends StatelessWidget {
  const _SheetTop({required this.state});

  final VisitState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _DragHandle(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
          child: _RecordingStatus(
            key: const Key('visitSheetRecordingStatus'),
            recording: state.recording,
            elapsed: state.elapsedLabel,
          ),
        ),
      ],
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    // 아래 녹음 표시 줄과 붙어 한 묶음으로 보이게 위아래 여백을 8로 둔다.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Container(
        width: 44,
        height: 4,
        decoration: BoxDecoration(
          color: HomeColors.bubbleLine,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
    );
  }
}

/// 녹음 화면의 상태와 시간을 한 줄로 줄인 것이다.
///
/// 녹음 화면의 마이크 원을 작게 줄여 같은 모양으로 둔다. 녹음 중이면 초록 면에
/// 흰 마이크와 둘레의 물결([RecordingPulse]), 멈추면 연초록 면에 진한 테두리와
/// 멈춤 표시다. 색만으로 가르지 않도록 아이콘과 글자도 바뀐다. 누르는 자리가
/// 아니라 면이나 테두리로 감싸지 않는다.
///
/// 화면 낭독기는 녹음 화면처럼 상태가 바뀔 때 바로 읽고(`녹음 중이에요`,
/// `잠시 멈췄어요`), 1초마다 바뀌는 시간은 바뀔 때 읽지 않는다. 시간은 글자가
/// 커져 한 줄에 들어가지 않으면 다음 줄로 내려간다.
class _RecordingStatus extends StatelessWidget {
  const _RecordingStatus({
    required this.recording,
    required this.elapsed,
    super.key,
  });

  final bool recording;
  final String elapsed;

  /// 작은 녹음 원의 지름. 보조 글자 한 줄 높이에 들어간다.
  static const _dot = 20.0;

  /// 작은 원 둘레로 물결이 퍼지는 거리. 옆 글자와의 간격(8)에 닿지 않는다.
  static const _spread = 6.0;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.md,
      children: [
        Semantics(
          liveRegion: true,
          label: recording ? '녹음 중이에요' : '잠시 멈췄어요',
          excludeSemantics: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RecordingPulse(
                active: recording,
                spread: _spread,
                child: Container(
                  width: _dot,
                  height: _dot,
                  decoration: BoxDecoration(
                    color: recording ? HomeColors.accent : HomeColors.bubble,
                    shape: BoxShape.circle,
                    border: recording
                        ? null
                        : Border.all(color: HomeColors.outline, width: 1.5),
                  ),
                  child: Icon(
                    recording ? Icons.mic : Icons.pause,
                    size: 14,
                    color: recording ? AppColors.background : AppColors.textSub,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                recording ? '녹음 중' : '잠시 멈춤',
                style: AppTypography.sub.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Text(
          elapsed,
          style: AppTypography.sub.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// 위쪽의 카드 막대. 길이가 정해진 막대를 카드 수만큼 나눠 지금 어디쯤인지
/// 보여준다. 칸을 누르면 그 카드로 바로 간다.
///
/// 번호 칩을 늘어놓으니 화면이 요란해서 막대로 바꿨다. 지금 카드 칸만 검정이고
/// 살짝 튀어 오르듯 위로 올라간다. 면회 중에 더한 카드의 칸은 처음 고른 카드의
/// 칸(연한 회색)보다 진한 회색이다. 카드를 더하고 돌아오면 새 칸이 하나씩
/// 차례로 자라 들어오고, 그만큼 앞 칸들이 좁아진다.
class _CardBar extends StatefulWidget {
  const _CardBar({
    required this.state,
    required this.shownCount,
    required this.onSelect,
  });

  final VisitState state;

  /// 그릴 칸 수. 카드 추가 화면에 가 있는 동안은 카드 수보다 작다.
  final int shownCount;

  final ValueChanged<int> onSelect;

  @override
  State<_CardBar> createState() => _CardBarState();
}

class _CardBarState extends State<_CardBar>
    with SingleTickerProviderStateMixin {
  /// 새 칸이 자라기 시작하기 전 기다림. 카드 추가 화면이 닫히는 동안이다.
  static const _wait = 250;

  /// 다음 칸이 따라 들어오는 간격.
  static const _step = 110;

  /// 한 칸이 다 자라는 데 걸리는 시간.
  static const _grow = 420;

  /// 칸 사이 간격.
  static const _gap = 6.0;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: 1,
  );

  /// 이 번호부터의 칸이 이번에 새로 자란다.
  late int _growFrom = widget.shownCount;

  @override
  void didUpdateWidget(_CardBar old) {
    super.didUpdateWidget(old);
    if (widget.shownCount <= old.shownCount) return;
    _growFrom = old.shownCount;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
      return;
    }
    final added = widget.shownCount - old.shownCount;
    _controller.duration = Duration(
      milliseconds: _wait + (added - 1) * _step + _grow,
    );
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// [index] 칸이 얼마나 자랐는지(0~1). 앞에 있던 칸은 늘 1이다.
  double _share(int index) {
    if (index < _growFrom) return 1;
    final total = _controller.duration?.inMilliseconds ?? 1;
    final start = (_wait + (index - _growFrom) * _step) / total;
    final end = (start + _grow / total).clamp(0.0, 1.0);
    if (start >= 1) return 1;
    return Interval(
      start,
      end,
      curve: Curves.easeOutCubic,
    ).transform(_controller.value);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final count = widget.shownCount.clamp(0, state.cards.length);

    // 시트 손잡이와 헷갈리지 않게 손잡이에서 떨어뜨린다. 그 사이에 녹음 표시
    // 줄([_SheetTop])이 있고 막대 위 누르는 자리의 남는 높이(20)가 간격이
    // 되므로 위 여백은 두지 않는다. 아래 여백도 같은 이유로 두지 않는다.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
      child: LayoutBuilder(
        builder: (context, constraints) => AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final shares = [for (var i = 0; i < count; i++) _share(i)];
            final sum = shares.fold(0.0, (a, b) => a + b);
            final visible = shares.where((s) => s > 0).length;
            final room =
                constraints.maxWidth - 0.5 - _gap * (visible - 1).clamp(0, 99);
            return Row(
              children: [
                for (var i = 0; i < count; i++)
                  if (shares[i] > 0) ...[
                    if (i > 0) const SizedBox(width: _gap),
                    SizedBox(
                      width: sum == 0 ? 0 : room * shares[i] / sum,
                      child: _CardBarSegment(
                        number: i + 1,
                        current: i == state.currentIndex,
                        added: state.addedCardIds.contains(
                          state.cards[i].cardId,
                        ),
                        onTap: () => widget.onSelect(i),
                      ),
                    ),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 막대의 한 칸. 보이는 막대는 얇지만 누르는 자리는 높이 48이다.
class _CardBarSegment extends StatelessWidget {
  const _CardBarSegment({
    required this.number,
    required this.current,
    required this.added,
    required this.onTap,
  });

  final int number;
  final bool current;
  final bool added;
  final VoidCallback onTap;

  /// 지금 카드 칸이 위로 올라가는 거리.
  static const _lift = 6.0;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    // 더한 카드도 처음 고른 카드와 같은 연한 색이다. 색을 나누니 막대가
    // 요란해 보였다. 더한 카드는 화면 낭독기 이름으로만 알린다.
    final color = current ? HomeColors.accent : HomeColors.bubbleLine;

    return Semantics(
      container: true,
      button: true,
      selected: current,
      label: '$number번 카드${added ? ', 추가한 카드' : ''}',
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: AppSizes.minTouch,
          child: Center(
            // 올라갈 때는 살짝 지나쳤다 돌아와 탄력 있게, 내려갈 때는 조용히.
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: current ? 1 : 0),
              duration: still
                  ? Duration.zero
                  : Duration(milliseconds: current ? 650 : 250),
              curve: current
                  ? const ElasticOutCurve(0.55)
                  : Curves.easeOutCubic,
              builder: (context, lift, child) => Transform.translate(
                offset: Offset(0, -_lift * lift),
                child: child,
              ),
              child: AnimatedContainer(
                duration: still
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 위쪽 절반. 흰 바탕에 어르신께 여쭙는 문장을 크게 둔다.
///
/// 사진에서 나온 카드는 소제목 위에 그 사진을 작게 둔다([CardSourcePhoto]).
/// 사진은 소제목과 메인 질문을 제 크기로 놓고 남는 높이만 쓰며 120 을 넘지
/// 않는다. 남는 높이가 48 보다 작으면(작은 화면, 큰 글자) 질문을 줄이지 않도록
/// 사진을 두지 않는다. 곁눈질로 읽는 질문이 먼저다.
class _MainQuestion extends StatelessWidget {
  const _MainQuestion({required this.card});

  final ConversationCard card;

  static const _photoMax = CardSourcePhoto.largestHeight;
  static const _photoMin = 48.0;
  static const _questionWidth = 340.0;

  /// 바닥에 둔 채 곁눈질로 읽으므로 다른 화면보다 크게 둔다.
  static final _questionStyle = AppTypography.screenTitle.copyWith(
    fontSize: 32,
    height: 1.4,
  );

  /// 사진에 줄 수 있는 높이. 소제목과 메인 질문을 제 크기로 놓고 남는 높이에서
  /// 사진 아래 여백을 뺀다.
  double _photoRoom(BuildContext context, BoxConstraints box) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    double heightOf(String text, TextStyle style, double width) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textAlign: TextAlign.center,
        textDirection: direction,
        textScaler: scaler,
      )..layout(maxWidth: width);
      final height = painter.height;
      painter.dispose();
      return height;
    }

    final title = heightOf(
      '[ ${card.cardTitle} ]',
      AppTypography.sub,
      box.maxWidth,
    );
    final question = heightOf(
      card.primaryQuestion,
      _questionStyle,
      _questionWidth,
    );
    return box.maxHeight - title - AppSpacing.lg - question - AppSpacing.md;
  }

  @override
  Widget build(BuildContext context) {
    final cardTitle = card.cardTitle;
    final question = card.primaryQuestion;
    return Container(
      width: double.infinity,
      color: HomeColors.background,
      // 소제목과 메인 질문 묶음이 위 막대와 아래 이전·다음 버튼 사이의
      // 가운데에 오게 한다. 막대는 이 칸 위쪽 20 지점에서 끝나고(누르는
      // 자리 48 중 아래 20), 버튼은 이 칸 아래쪽 32 지점에서 시작한다(높이
      // 64의 절반). 그래서 아래 여백을 위보다 52 더 두어 둘 사이의 가운데에
      // 맞춘다.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        0,
        AppSpacing.screen,
        52,
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final photo = card.evidenceSource == 'photo'
              ? math.min(_photoMax, _photoRoom(context, box))
              : 0.0;
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (photo >= _photoMin)
                CardSourcePhoto(
                  card: card,
                  maxHeight: photo,
                  alignment: Alignment.center,
                ),
              Text(
                '[ $cardTitle ]',
                style: AppTypography.sub,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _questionWidth),
                    child: Text(
                      question,
                      style: _questionStyle,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 아래쪽 절반. 회색 바탕으로 위와 구분하고, 누르면 다음 꼬리 질문으로 넘어간다.
///
/// 넘길 때 앞 질문이 왼쪽으로 밀려 사라진 뒤 다음 질문이 오른쪽에서 들어온다.
/// 글자만 바뀌면 넘어갔는지 알아채기 어려웠다.
class _FollowUpQuestion extends StatelessWidget {
  const _FollowUpQuestion({
    required this.question,
    required this.index,
    required this.turn,
    required this.count,
    required this.onTap,
    super.key,
  });

  final String question;
  final int index;

  /// 넘긴 횟수. 한 바퀴 돌아 같은 질문이 와도 넘김 효과가 보이게 이 값으로
  /// 질문을 가른다.
  final int turn;

  final int count;
  final VoidCallback onTap;

  Widget _slide(Widget child, Animation<double> animation) {
    // 앞 질문이 조금 왼쪽으로 밀리며 사라진 뒤에 다음 질문이 오른쪽에서
    // 들어온다. 둘이 함께 움직이면 글자가 겹쳐 어지러웠다.
    //
    // 나가는 쪽은 애니메이션이 1에서 0으로 거꾸로 돈다. 두 쪽 모두 뒤 절반
    // 구간만 쓰므로, 나가는 질문은 앞 절반에 사라지고 들어오는 질문은 뒤
    // 절반에 나타나 한 번에 하나만 보인다.
    final incoming = child.key == ValueKey(turn);
    final half = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.5, 1, curve: Curves.easeOutCubic),
    );
    final offset = Tween<Offset>(
      begin: Offset(incoming ? 0.25 : -0.25, 0),
      end: Offset.zero,
    ).animate(half);
    return SlideTransition(
      position: offset,
      child: FadeTransition(opacity: half, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 400);

    return Material(
      color: HomeColors.bubble,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: HomeColors.bubbleLine, width: 2),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(
            0,
            AppSpacing.xxxl,
            0,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                // 화면 양 끝까지 밀려 나가도록 좌우 여백은 질문 안쪽에 둔다.
                child: ClipRect(
                  child: SizedBox(
                    width: double.infinity,
                    child: AnimatedSwitcher(
                      duration: duration,
                      transitionBuilder: _slide,
                      child: Padding(
                        key: ValueKey(turn),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.screen,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 340),
                            child: Text(
                              question,
                              style: AppTypography.screenTitle.copyWith(
                                fontSize: 26,
                                height: 1.4,
                                color: AppColors.textSub,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < count; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: AnimatedContainer(
                        duration: duration,
                        curve: Curves.easeOutCubic,
                        // 지금 질문의 점은 길게 늘여 자리가 옮겨 가는 것이
                        // 보이게 한다.
                        width: i == index ? 18 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: i == index
                              ? HomeColors.accent
                              : HomeColors.bubbleLine,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                '눌러서 다음 꼬리 질문 보기',
                // 연초록 면 위라 비활성 회색(3.9:1) 대신 보조 글자색을 쓴다.
                style: AppTypography.caption.copyWith(color: AppColors.textSub),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 두 영역 경계에 걸쳐 나란히 놓는 이전, 다음 카드 버튼이다.
///
/// 메인 질문을 옆으로 미는 동작은 50~60대에게 낯설어 버튼으로 둔다. 다음은
/// 검정 면, 이전은 검정 테두리로 나눠 어느 쪽이 앞으로 가는지 바로 보이게 한다.
class _CardStepButton extends StatelessWidget {
  const _CardStepButton({
    required this.forward,
    required this.enabled,
    required this.onTap,
  });

  final bool forward;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 마지막 다음은 첫 카드, 첫 카드 이전은 마지막 카드로 돌아 끝이 없다.
    final label = forward ? '다음' : '이전';
    // 보이는 글자만으로는 무엇의 다음인지 알 수 없어 화면 낭독기에는 카드라는
    // 것을 붙여 읽는다.
    final semanticLabel = forward ? '다음 카드' : '이전 카드';

    final Color background;
    final Color foreground;
    final Color border;
    if (!enabled) {
      (background, foreground, border) = (
        AppColors.surface,
        AppColors.textDisabled,
        AppColors.line,
      );
    } else if (forward) {
      (background, foreground, border) = (
        HomeColors.accent,
        AppColors.background,
        HomeColors.accent,
      );
    } else {
      (background, foreground, border) = (
        AppColors.background,
        HomeColors.accent,
        HomeColors.accent,
      );
    }

    final icon = Icon(
      forward ? Icons.chevron_right : Icons.chevron_left,
      size: 28,
      color: foreground,
    );
    final text = Text(
      label,
      style: AppTypography.sectionTitle.copyWith(color: foreground),
    );

    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: semanticLabel,
      onTap: enabled ? onTap : null,
      excludeSemantics: true,
      child: Material(
        color: background,
        shape: StadiumBorder(side: BorderSide(color: border, width: 2)),
        elevation: enabled ? 3 : 0,
        shadowColor: Colors.black26,
        child: InkWell(
          onTap: enabled ? onTap : null,
          customBorder: const StadiumBorder(),
          // Container 의 alignment 는 받은 자리를 다 채워, 경계 위에 띄운 이
          // 버튼이 시트 높이만큼 늘어났다. 최소 크기만 주고 가운데 정렬은
          // Row 가 맡는다.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 132, minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                // 화살표는 가는 쪽 바깥에 둔다. ‹ 이전 | 다음 ›
                children: forward
                    ? [text, const SizedBox(width: AppSpacing.xs), icon]
                    : [icon, const SizedBox(width: AppSpacing.xs), text],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddCardsBar extends StatelessWidget {
  const _AddCardsBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HomeColors.background,
      child: InkWell(
        onTap: onTap,
        child: SafeArea(
          top: false,
          child: Container(
            width: double.infinity,
            height: 64,
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: HomeColors.bubbleLine)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, size: 22, color: HomeColors.accent),
                SizedBox(width: AppSpacing.sm),
                Text('대화 카드 추가', style: AppTypography.bodyStrong),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
