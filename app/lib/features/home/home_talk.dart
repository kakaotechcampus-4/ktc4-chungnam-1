import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/card_api.dart';
import '../../data/providers.dart';
import '../../design/tokens.dart';
import '../../widgets/mascot.dart';
import '../cards/card_generation_controller.dart';
import '../life_story/life_story.dart';
import '../life_story/life_story_providers.dart';
import 'home_phrases.dart';

/// 홈의 `오늘의 대화카드 받기` 를 누를 때 올린다. [HomeTalk] 가 듣고 말풍선을
/// 바꾼다.
final homeTalkNudgeProvider = NotifierProvider<HomeTalkNudge, int>(
  HomeTalkNudge.new,
);

class HomeTalkNudge extends Notifier<int> {
  @override
  int build() => 0;

  void nudge() => state++;
}

/// 면회를 마치고 홈으로 갈 때 위로 화면이 켠다. 홈이 다시 보이면
/// [HomeTalk] 가 이야기 대신 [afterVisitGreetings] 로 인사하고 끈다.
final homeAfterVisitProvider = NotifierProvider<HomeAfterVisit, bool>(
  HomeAfterVisit.new,
);

class HomeAfterVisit extends Notifier<bool> {
  @override
  bool build() => false;

  void returning() => state = true;

  void clear() => state = false;
}

/// 홈 가운데의 말풍선과 마스코트.
///
/// 처음에는 시간대 인사말을 한다. 면회를 마치고 돌아오면 면회 뒤 인사말을
/// 한다([homeAfterVisitProvider]). 다른 화면에서 홈으로 돌아올 때, 마스코트를
/// 눌러 반응할 때, `오늘의 대화카드 받기` 를 누를 때 일대기 이야기 하나를
/// 무작위로 골라 보여준다. 이야기가 없거나 아직 읽는 중이면 인사말을 바꾼다.
/// 같은 이야기, 같은 말은 연달아 고르지 않는다. 이야기 말풍선을 누르면 그
/// 이야기 화면으로 간다.
///
/// 어르신마다 처음부터 시작하도록 홈이 어르신 ID 를 key 로 준다. 로그아웃하면
/// 홈이 새로 만들어지므로 다른 계정도 인사말부터 시작한다.
///
/// 지금 고른 어르신의 카드를 실제로 만들고(`making`, `remaking`) 끝나 쓸 수
/// 있게 되면(`ready`, `inVisit`) 마스코트가 한 번 축하하고 말풍선이
/// [cardsReadyMessage] 로 바뀐다. 다음 이벤트가 오면 다시 이야기로 바뀐다.
/// 다른 화면에 있는 동안 다 되면 홈으로 돌아왔을 때 이 말을 그대로 둔다. 이미 있던 묶음을
/// 확인만 한 경우와 실패는 축하하지 않는다. 다른 화면에 가 있는 동안 끝나면
/// 움직임은 홈으로 돌아왔을 때 이어서 보인다.
class HomeTalk extends ConsumerStatefulWidget {
  const HomeTalk({super.key, this.random, this.mascotSize});

  /// 테스트가 고르는 순서를 정할 때 넘긴다.
  final math.Random? random;

  /// 마스코트 크기를 정해 둔다. 홈이 스크롤될 때(글자를 크게 키웠을 때) 쓴다.
  /// `null` 이면 남는 높이에 맞춰 줄어든다.
  final double? mascotSize;

  @override
  ConsumerState<HomeTalk> createState() => _HomeTalkState();
}

class _HomeTalkState extends ConsumerState<HomeTalk> {
  late final math.Random _random = widget.random ?? math.Random();
  final _mascot = MascotController();

  late _Line _line = _Line.greeting(_pick(greetingsFor(DateTime.now()), null));

  /// 바뀔 때마다 올려 말풍선이 새로 나타나게 한다.
  int _turn = 0;

  /// 지난번에 이 화면이 보였는지. 다른 화면이 위에 쌓이면 `false` 가 된다.
  bool? _onStage;

  /// 다른 화면에 있는 동안 카드가 다 됐다. 돌아올 때 이야기로 바꾸지 않는다.
  bool _keepOnReturn = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 위에 쌓였던 화면이 닫혀 홈이 다시 보이면 이야기를 바꾼다. 곧 build 가
    // 이어지므로 setState 없이 바꾼다.
    final onStage = TickerMode.valuesOf(context).enabled;
    // 면회를 마치고 왔다. 처음 만들어졌든 다시 보이든 인사부터 한다.
    if (onStage && ref.read(homeAfterVisitProvider)) {
      _line = _Line.greeting(_pick(afterVisitGreetings, _line.greeting));
      _turn++;
      _keepOnReturn = false;
      // 화면을 그리는 중에는 provider 를 바꿀 수 없어 미룬다.
      Future.microtask(() {
        if (mounted) ref.read(homeAfterVisitProvider.notifier).clear();
      });
    } else if (_onStage == false && onStage) {
      if (_keepOnReturn) {
        _keepOnReturn = false;
      } else {
        _line = _nextLine();
        _turn++;
      }
    }
    _onStage = onStage;
  }

  @override
  void dispose() {
    _mascot.dispose();
    super.dispose();
  }

  void _talk() {
    if (!mounted) return;
    setState(() {
      _line = _nextLine();
      _turn++;
    });
  }

  _Line _nextLine() {
    final stories = ref.read(lifeStoryBookProvider).value?.stories ?? const [];
    if (stories.isEmpty) {
      return _Line.greeting(
        _pick(greetingsFor(DateTime.now()), _line.greeting),
      );
    }
    final story = _pick(stories, _line.story);
    return _Line.story(story, _pick(storyRemarks, _line.remark));
  }

  /// [items] 에서 하나 고른다. 둘 이상이면 [last] 와 다른 것을 고른다.
  T _pick<T>(List<T> items, T? last) {
    final choices = items.length > 1
        ? [
            for (final item in items)
              if (item != last) item,
          ]
        : items;
    return choices[_random.nextInt(choices.length)];
  }

  void _celebrateWhenMade(String profileId) {
    ref.listen(cardGenerationProvider(profileId), (previous, next) {
      final made =
          ref.read(cardMakingProvider(profileId)) != CardMaking.checking;
      final usable =
          !next.isLoading &&
          !next.hasError &&
          (next.value == CardGenerationStatus.ready ||
              next.value == CardGenerationStatus.inVisit);
      if ((previous?.isLoading ?? false) && made && usable) {
        _mascot.celebrate();
        setState(() {
          _line = const _Line.greeting(cardsReadyMessage);
          _turn++;
          if (_onStage == false) _keepOnReturn = true;
        });
      }
    });
  }

  Widget _mascotOf(double size) => Mascot(
    size: size,
    controller: _mascot,
    onReact: _talk,
    // 카드 완성 말풍선이 떠 있는 동안 신나는 얼굴로 떠 있는다.
    cheerful: _line.greeting == cardsReadyMessage,
  );

  @override
  Widget build(BuildContext context) {
    final profileId = ref.watch(serverProfileIdProvider).value;
    if (profileId != null) _celebrateWhenMade(profileId);
    ref.listen(homeTalkNudgeProvider, (_, _) => _talk());

    // 이야기를 미리 읽어 두고, 고치거나 지운 것을 말풍선에 맞춘다.
    final book = ref.watch(lifeStoryBookProvider).value;
    var story = _line.story;
    if (story != null && book != null) {
      story = book.find(story.id);
      // 보여주던 이야기를 지웠으면 인사말로 돌아간다.
      if (story == null) {
        _line = _Line.greeting(_pick(greetingsFor(DateTime.now()), null));
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Bubble(
          key: ValueKey(_turn),
          line: _line,
          story: story,
          onOpen: story == null
              ? null
              : () => context.push(
                  AppRoutes.albumStoryOf(story!.category.name, story.id),
                ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (widget.mascotSize case final fixed?)
          _mascotOf(fixed)
        else
          Flexible(
            child: LayoutBuilder(
              builder: (context, box) => _mascotOf(
                math.min(math.min(box.maxHeight, box.maxWidth * 0.55), 220.0),
              ),
            ),
          ),
      ],
    );
  }
}

/// 말풍선 한 번에 보여줄 것. 인사말이거나, 일대기 이야기와 그 아래 말이다.
class _Line {
  const _Line.greeting(String this.greeting) : story = null, remark = null;

  const _Line.story(LifeStory this.story, String this.remark) : greeting = null;

  final String? greeting;
  final LifeStory? story;
  final String? remark;
}

/// 마스코트를 가리키는 꼬리가 달린 연회색 말풍선. 바뀔 때 살짝 커지며
/// 나타난다.
class _Bubble extends StatefulWidget {
  const _Bubble({
    super.key,
    required this.line,
    required this.story,
    required this.onOpen,
  });

  final _Line line;

  /// 일대기에서 다시 찾은 이야기. 고친 제목을 따른다.
  final LifeStory? story;
  final VoidCallback? onOpen;

  @override
  State<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<_Bubble> with SingleTickerProviderStateMixin {
  late final AnimationController _appear = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();

  @override
  void dispose() {
    _appear.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.story;
    final remark = widget.line.remark;
    final Widget content;
    if (story != null && remark != null) {
      content = Semantics(
        button: true,
        label: '일대기 이야기 ${story.title} 보러 가기. $remark',
        excludeSemantics: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StoryTitle(title: story.title),
            const SizedBox(height: AppSpacing.sm),
            Text(
              remark,
              style: AppTypography.body,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    } else {
      content = Text(
        widget.line.greeting ?? '',
        style: AppTypography.body,
        textAlign: TextAlign.center,
      );
    }

    final curve = CurvedAnimation(parent: _appear, curve: Curves.easeOutBack);
    return FadeTransition(
      opacity: _appear,
      child: ScaleTransition(
        scale: Tween(begin: 0.92, end: 1.0).animate(curve),
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          // 말풍선 몸과 꼬리를 한 모양으로 보고 그 아래에 옅은 그림자를 깐다.
          child: CustomPaint(
            painter: const _BubbleShadowPainter(
              radius: _radius,
              tail: _tailSize,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(_radius),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: widget.onOpen,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: content,
                    ),
                  ),
                ),
                const CustomPaint(
                  size: _tailSize,
                  painter: _TailPainter(AppColors.background),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const _radius = 20.0;
  static const _tailSize = Size(20, 10);
}

/// 이야기 제목 상자. 길면 한 줄로 줄이고 끝에 이동 화살표를 둔다.
class _StoryTitle extends StatelessWidget {
  const _StoryTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: HomeColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.menu_book_outlined,
            size: 20,
            color: AppColors.textSub,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              title,
              style: AppTypography.bodyStrong,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.chevron_right, size: 24, color: AppColors.textSub),
        ],
      ),
    );
  }
}

/// 꼬리 모양. 왼쪽 위가 (0, 0) 인 [size] 상자 안에 그린다.
Path _tailPath(Size size) => Path()
  ..moveTo(0, 0)
  ..lineTo(size.width, 0)
  ..quadraticBezierTo(
    size.width * 0.58,
    size.height * 0.9,
    size.width / 2,
    size.height,
  )
  ..quadraticBezierTo(size.width * 0.42, size.height * 0.9, 0, 0)
  ..close();

/// 말풍선 몸과 꼬리를 합친 모양의 그림자. 리포트 알림 배너보다 조금 진하게 해
/// 오프화이트 바탕에서 떠 보이게 한다. 장식이라 누름과 화면 낭독기에는 영향이 없다.
class _BubbleShadowPainter extends CustomPainter {
  const _BubbleShadowPainter({required this.radius, required this.tail});

  final double radius;
  final Size tail;

  @override
  void paint(Canvas canvas, Size size) {
    final body = size.height - tail.height;
    final shape = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, body),
          Radius.circular(radius),
        ),
      )
      ..addPath(_tailPath(tail), Offset((size.width - tail.width) / 2, body));
    canvas.drawPath(
      shape.shift(const Offset(0, 3)),
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  @override
  bool shouldRepaint(_BubbleShadowPainter old) =>
      old.radius != radius || old.tail != tail;
}

/// 아래를 가리키는 둥근 삼각형 꼬리.
class _TailPainter extends CustomPainter {
  const _TailPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(_tailPath(size), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TailPainter old) => old.color != color;
}
