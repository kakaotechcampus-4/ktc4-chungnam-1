import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../design/tokens.dart';
import '../../widgets/app_scaffold.dart';
import 'life_story_book_loader.dart';

/// H 일대기의 첫 화면. 책 표지를 누르면 표지가 넘어가며 책 안으로 들어간다.
///
/// 표지가 넘어가는 움직임은 `app/DESIGN.md` 움직임 규칙의 예외다. 기기의
/// 애니메이션 줄이기가 켜져 있으면 움직이지 않고 바로 넘어간다.
class LifeStoryCoverScreen extends StatelessWidget {
  const LifeStoryCoverScreen({super.key});

  /// 화면 제목보다 크다. 책 표지와 함께 이 화면의 이름표 노릇을 한다
  /// (`app/DESIGN.md` 글자).
  static const _coverTitle = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 1.35,
    letterSpacing: -0.4,
    color: AppColors.ink,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppTopBar(),
      body: LifeStoryBookLoader(
        // 제목, 책, 편수를 한 덩어리로 묶어 화면 가운데에 둔다. 화면이 낮으면
        // 책이 줄어든다.
        builder: (context, book) => ScreenBody(
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.section),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '쌓아온 이야기',
                  style: _coverTitle,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '책을 눌러 펼쳐 보세요',
                  style: AppTypography.body.copyWith(color: AppColors.textSub),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 44),
                Flexible(child: _OpeningBook(name: book.profile.name)),
                const SizedBox(height: AppSpacing.xxl),
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: '지금까지 '),
                      TextSpan(
                        text: '${book.total}편',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const TextSpan(text: '의 이야기가 담겨 있어요'),
                    ],
                  ),
                  style: AppTypography.body,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OpeningBook extends StatefulWidget {
  const _OpeningBook({required this.name});

  final String name;

  @override
  State<_OpeningBook> createState() => _OpeningBookState();
}

class _OpeningBookState extends State<_OpeningBook>
    with SingleTickerProviderStateMixin {
  /// 표지가 다 넘어가기 전에 다음 화면으로 넘어간다. 프로토타입과 같은 값이다.
  static const _openDuration = Duration(milliseconds: 900);
  static const _navigateAfter = Duration(milliseconds: 650);

  /// 책의 세로 대 가로 비율. 3:4.2 다.
  static const _heightPerWidth = 4.2 / 3;

  /// 표지가 젖혀지는 최대 각도.
  static const _maxAngle = 155 * math.pi / 180;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _openDuration,
  );
  late final Animation<double> _turn = CurvedAnimation(
    parent: _controller,
    curve: const Cubic(0.6, 0.05, 0.3, 1),
  );

  bool _opening = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (_opening) return;
    _opening = true;
    if (!MediaQuery.disableAnimationsOf(context)) {
      _controller.forward();
      await Future<void>.delayed(_navigateAfter);
      if (!mounted) return;
    }
    await context.push(AppRoutes.albumBook);
    // 책 안에서 돌아오면 표지를 다시 덮는다.
    if (!mounted) return;
    _controller.reset();
    _opening = false;
  }

  @override
  Widget build(BuildContext context) {
    // 화면 폭의 72% 를 넘지 않고, 높이가 모자라면 그에 맞춰 줄인다.
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(
          constraints.maxWidth * 0.72,
          constraints.maxHeight / _heightPerWidth,
        );
        return Center(
          heightFactor: 1,
          child: SizedBox(
            width: width,
            height: width * _heightPerWidth,
            child: _book(),
          ),
        );
      },
    );
  }

  Widget _book() {
    return Semantics(
      button: true,
      label: '일대기 책 펼치기',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: _open,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 표지 뒤로 비치는 책장.
            Positioned.fill(
              left: 6,
              top: 6,
              right: -6,
              bottom: -6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.line),
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(2),
                    right: Radius.circular(8),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _turn,
                builder: (context, child) {
                  final angle = _turn.value * _maxAngle;
                  // 표지가 보는 사람 쪽으로 열린다. 90도를 넘으면 뒷면이
                  // 보일 차례라 감춘다.
                  if (angle > math.pi / 2) return const SizedBox.shrink();
                  return Transform(
                    alignment: Alignment.centerLeft,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0012)
                      ..rotateY(angle),
                    child: child,
                  );
                },
                child: _Cover(name: widget.name),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 부드러운 회색 면에 검정 글자의 표지다. 화면이 흑백이라 금박 대신 선을 쓴다.
class _Cover extends StatelessWidget {
  const _Cover({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    const onCover = AppColors.ink;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bookCover,
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(3),
          right: Radius.circular(10),
        ),
        boxShadow: AppShadows.high,
      ),
      child: Stack(
        children: [
          // 책등.
          const Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 14,
            child: ColoredBox(color: AppColors.bookSpine),
          ),
          // 표지 안쪽 테두리.
          Positioned.fill(
            left: 28,
            top: 16,
            right: 14,
            bottom: 16,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.textSub),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          Positioned.fill(
            left: 34,
            right: 22,
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.spa_outlined, size: 40, color: onCover),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      '$name님의',
                      textAlign: TextAlign.center,
                      style: AppTypography.screenTitle,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '일대기',
                      textAlign: TextAlign.center,
                      style: AppTypography.sectionTitle.copyWith(
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
