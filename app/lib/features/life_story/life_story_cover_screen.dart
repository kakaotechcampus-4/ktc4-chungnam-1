import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../design/tokens.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/profile_avatar.dart';
import 'life_story_book_loader.dart';

/// 앨범 표지 화면에서만 쓰는 색이다.
///
/// 2026-11-06 디자인 리뉴얼에서 이 화면부터 색을 입혔다(시안 B: 버건디 천,
/// 가죽 모서리, 금박). 다른 화면은 아직 흑백이고 하단 탭도 그대로다.
abstract final class _AlbumColors {
  /// 화면 바탕. 흰색에 가까운 아이보리다.
  static const background = Color(0xFFFDF9F4);

  /// 표지 천. `편` 수 강조 글자에도 쓴다(바탕과 대비 9:1 이상).
  static const cloth = Color(0xFF7E2F33);

  static const spineDark = Color(0xFF45271F);
  static const spine = Color(0xFF5C362C);

  /// 오른쪽 위아래 모서리에 덧댄 가죽.
  static const leather = Color(0xFF55332A);

  /// 금박 글자와 선. 천 위에서 대비 5.8:1 이다.
  static const gold = Color(0xFFE2C27E);
  static const goldDeep = Color(0xFFB48A3E);

  /// 표지 뒤로 보이는 책장.
  static const page = Color(0xFFF6EFE3);
  static const pageLine = Color(0xFFE4D7C2);

  static const subText = Color(0xFF6E6360);
}

/// H 일대기의 첫 화면. 앨범 표지를 누르면 표지가 넘어가며 책 안으로 들어간다.
///
/// 표지가 넘어가는 움직임은 `app/DESIGN.md` 움직임 규칙의 예외다. 기기의
/// 애니메이션 줄이기가 켜져 있으면 움직이지 않고 바로 넘어간다. 바탕에는 초록
/// 꽃잎 몇 장이 오른쪽에서 왼쪽으로 천천히 날아간다([AlbumPetals]).
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
      backgroundColor: _AlbumColors.background,
      appBar: const AppTopBar(
        title: '일대기',
        backgroundColor: _AlbumColors.background,
      ),
      body: LifeStoryBookLoader(
        // 제목, 책, 편수를 한 덩어리로 묶어 화면 가운데에 둔다. 화면이 낮으면
        // 책이 줄어든다.
        builder: (context, book) => Stack(
          children: [
            const Positioned.fill(child: AlbumPetals()),
            ScreenBody(
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
                      style: AppTypography.body.copyWith(
                        color: _AlbumColors.subText,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 44),
                    Flexible(
                      child: _OpeningBook(
                        name: book.profile.name,
                        gender: book.profile.gender,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxxl),
                    Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: '지금까지 '),
                          TextSpan(
                            text: '${book.total}편',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _AlbumColors.cloth,
                            ),
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
          ],
        ),
      ),
    );
  }
}

class _OpeningBook extends StatefulWidget {
  const _OpeningBook({required this.name, required this.gender});

  final String name;
  final String gender;

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
    // 화면 폭의 72% 를 넘지 않고, 높이가 모자라면 그에 맞춰 줄인다. 책장
    // 두께가 오른쪽과 아래로 10 만큼 나오므로 그만큼 빼고 잰다.
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(
          constraints.maxWidth * 0.72,
          (constraints.maxHeight - 10) / _heightPerWidth,
        );
        return Center(
          heightFactor: 1,
          child: SizedBox(
            width: width,
            height: width * _heightPerWidth,
            child: _book(width),
          ),
        );
      },
    );
  }

  Widget _book(double width) {
    return Semantics(
      button: true,
      label: '앨범 펼치기',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: _open,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 책장 두께. 오른쪽과 아래로 종이 줄이 보이고 책 아래에 그림자가
            // 진다.
            const Positioned(
              left: 10,
              top: 8,
              right: -10,
              bottom: -10,
              child: _Pages(vertical: true, shadow: true),
            ),
            const Positioned(
              left: 6,
              top: 4,
              right: -5,
              bottom: -5,
              child: _Pages(vertical: false, shadow: false),
            ),
            // 표지 밑의 첫 장. 표지가 넘어가는 동안 보인다.
            Positioned.fill(child: _InnerPage(scale: width / 268)),
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
                child: _Cover(
                  name: widget.name,
                  gender: widget.gender,
                  scale: width / 268,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 표지 뒤로 보이는 책장 묶음. 가는 줄을 촘촘히 그어 종이가 쌓인 것처럼 보인다.
class _Pages extends StatelessWidget {
  const _Pages({required this.vertical, required this.shadow});

  /// `true` 면 세로줄(오른쪽 옆면), `false` 면 가로줄(아래 옆면)이다.
  final bool vertical;
  final bool shadow;

  static const _radius = BorderRadius.horizontal(
    left: Radius.circular(3),
    right: Radius.circular(9),
  );

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _AlbumColors.page,
        borderRadius: _radius,
        boxShadow: shadow
            ? const [
                BoxShadow(
                  color: Color(0x38461E1E),
                  blurRadius: 32,
                  offset: Offset(0, 20),
                ),
                BoxShadow(
                  color: Color(0x1F461E1E),
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: _radius,
        child: CustomPaint(painter: _PageLinesPainter(vertical: vertical)),
      ),
    );
  }
}

class _PageLinesPainter extends CustomPainter {
  const _PageLinesPainter({required this.vertical});

  final bool vertical;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _AlbumColors.pageLine
      ..strokeWidth = 1;
    if (vertical) {
      for (var x = 2.5; x < size.width; x += 3) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
    } else {
      for (var y = 2.5; y < size.height; y += 3) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_PageLinesPainter old) => old.vertical != vertical;
}

/// 버건디 천 표지. 왼쪽 책등, 오른쪽 위아래 가죽 모서리, 금박 테두리 안에
/// 동그란 액자와 이름을 둔다.
///
/// 이름이 길어도 깨지지 않게 `○○○ 님의` 와 `앨범` 을 두 줄로 나누고, 이름
/// 줄은 넘치면 글자를 줄인다.
class _Cover extends StatelessWidget {
  const _Cover({required this.name, required this.gender, required this.scale});

  final String name;
  final String gender;

  /// 기준 너비 268 대비 비율. 화면이 낮아 책이 줄면 안의 것도 함께 준다.
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final title = AppTypography.sectionTitle.copyWith(
      fontSize: 22 * s,
      height: 1.35,
      color: _AlbumColors.gold,
      shadows: const [Shadow(color: Color(0x59000000), offset: Offset(0, 1))],
    );

    return Container(
      decoration: const BoxDecoration(
        color: _AlbumColors.cloth,
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(4),
          right: Radius.circular(10),
        ),
        boxShadow: AppShadows.high,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // 천 결과 은은한 빛.
          const Positioned.fill(child: CustomPaint(painter: _ClothPainter())),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-0.3, -0.5),
                  radius: 1,
                  colors: [Color(0x1FFFFFFF), Color(0x00FFFFFF)],
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.5, 0.8),
                  radius: 0.9,
                  colors: [Color(0x38000000), Color(0x00000000)],
                ),
              ),
            ),
          ),
          // 책등.
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 24 * s,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _AlbumColors.spineDark,
                    _AlbumColors.spine,
                    _AlbumColors.spineDark,
                  ],
                  stops: [0, 0.6, 1],
                ),
              ),
            ),
          ),
          // 가죽 모서리.
          Positioned(
            right: 0,
            top: 0,
            width: 44 * s,
            height: 44 * s,
            child: const CustomPaint(painter: _CornerPainter(top: true)),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            width: 44 * s,
            height: 44 * s,
            child: const CustomPaint(painter: _CornerPainter(top: false)),
          ),
          // 금박 테두리.
          Positioned(
            left: 36 * s,
            right: 14 * s,
            top: 18 * s,
            bottom: 18 * s,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: _AlbumColors.gold.withValues(alpha: 0.7),
                ),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          // 액자, 이름, 밑줄을 한 묶음으로 금박 테두리 한가운데에 둔다.
          Positioned(
            left: 36 * s,
            right: 14 * s,
            top: 18 * s,
            bottom: 18 * s,
            child: Center(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.symmetric(horizontal: 8 * s),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 동그란 금 액자 안의 프로필 사진.
                    Container(
                      padding: EdgeInsets.all(5 * s),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFE4C27A), _AlbumColors.goldDeep],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x59000000),
                            blurRadius: 8,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: ProfileAvatar(gender: gender, size: 92 * s),
                    ),
                    SizedBox(height: 18 * s),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$name 님의',
                        maxLines: 1,
                        style: title,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Text('앨범', style: title, textAlign: TextAlign.center),
                    SizedBox(height: 16 * s),
                    Container(
                      width: 64 * s,
                      height: 1,
                      color: _AlbumColors.gold.withValues(alpha: 0.8),
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

/// 천의 씨실과 날실. 비스듬한 가는 줄을 두 방향으로 엷게 긋는다.
class _ClothPainter extends CustomPainter {
  const _ClothPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final light = Paint()
      ..color = const Color(0x0BFFFFFF)
      ..strokeWidth = 1;
    final dark = Paint()
      ..color = const Color(0x14000000)
      ..strokeWidth = 1;
    final span = size.width + size.height;
    for (var d = 0.0; d < span; d += 4) {
      canvas.drawLine(
        Offset(d, 0),
        Offset(d - size.height, size.height),
        light,
      );
      canvas.drawLine(Offset(d - size.height, 0), Offset(d, size.height), dark);
    }
  }

  @override
  bool shouldRepaint(_ClothPainter old) => false;
}

/// 오른쪽 위나 아래 모서리를 덮는 삼각형 가죽.
class _CornerPainter extends CustomPainter {
  const _CornerPainter({required this.top});

  final bool top;

  @override
  void paint(Canvas canvas, Size size) {
    final path = top
        ? (Path()
            ..moveTo(0, 0)
            ..lineTo(size.width, 0)
            ..lineTo(size.width, size.height)
            ..close())
        : (Path()
            ..moveTo(size.width, 0)
            ..lineTo(size.width, size.height)
            ..lineTo(0, size.height)
            ..close());
    canvas.drawPath(path, Paint()..color = _AlbumColors.leather);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => old.top != top;
}

/// 바탕 위로 초록 꽃잎 몇 장이 바람에 날리듯 오른쪽에서 왼쪽으로 지나간다.
///
/// 책이나 글자 뒤로 지나가고 어디에도 내려앉지 않는다. 붙었다 떨어지니 벌레처럼
/// 보였다. 움직임 줄이기가 켜져 있으면 그리지 않는다.
class AlbumPetals extends StatefulWidget {
  const AlbumPetals({super.key});

  /// 테스트에서 끈다. 계속 움직여 pumpAndSettle 이 끝나지 않는다.
  static bool motion = true;

  @override
  State<AlbumPetals> createState() => _AlbumPetalsState();
}

class _AlbumPetalsState extends State<AlbumPetals>
    with SingleTickerProviderStateMixin {
  /// 한 바퀴. 꽃잎마다 이 시간 동안 1~2 번 화면을 건넌다.
  static const _cycle = Duration(seconds: 44);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _cycle,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still =
        MediaQuery.disableAnimationsOf(context) || !AlbumPetals.motion;
    if (still) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context) || !AlbumPetals.motion) {
      return const SizedBox.shrink();
    }
    return ExcludeSemantics(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(painter: _PetalsPainter(_controller)),
        ),
      ),
    );
  }
}

/// 꽃잎 한 장의 경로와 모양.
class _Petal {
  const _Petal({
    required this.laps,
    required this.phase,
    required this.y,
    required this.sway,
    required this.size,
    required this.color,
  });

  /// 한 바퀴([_AlbumPetalsState._cycle]) 동안 화면을 건너는 횟수.
  final int laps;

  /// 출발을 엇갈리게 하는 0~1 값.
  final double phase;

  /// 화면 높이에 대한 지나가는 높이(0~1).
  final double y;

  /// 위아래로 살랑이는 폭.
  final double sway;

  final double size;
  final Color color;
}

class _PetalsPainter extends CustomPainter {
  _PetalsPainter(this.time) : super(repaint: time);

  final Animation<double> time;

  static const _petals = [
    _Petal(
      laps: 2,
      phase: 0.05,
      y: 0.08,
      sway: 14,
      size: 12,
      color: Color(0xFF8DB580),
    ),
    _Petal(
      laps: 1,
      phase: 0.42,
      y: 0.18,
      sway: 18,
      size: 10,
      color: Color(0xFFB9D5AA),
    ),
    _Petal(
      laps: 2,
      phase: 0.71,
      y: 0.46,
      sway: 16,
      size: 11,
      color: Color(0xFF6F9A63),
    ),
    _Petal(
      laps: 1,
      phase: 0.18,
      y: 0.62,
      sway: 20,
      size: 13,
      color: Color(0xFF9DC28F),
    ),
    _Petal(
      laps: 2,
      phase: 0.33,
      y: 0.82,
      sway: 12,
      size: 10,
      color: Color(0xFFB0CFA2),
    ),
    _Petal(
      laps: 1,
      phase: 0.88,
      y: 0.92,
      sway: 16,
      size: 12,
      color: Color(0xFF7FA672),
    ),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    for (final petal in _petals) {
      final progress = (t * petal.laps + petal.phase) % 1;
      final x = size.width + 30 - progress * (size.width + 60);
      final wave = math.sin(progress * math.pi * 2 * 3 + petal.phase * 9);
      final y = size.height * petal.y + wave * petal.sway;
      final flutter = math.sin(progress * math.pi * 2 * 7 + petal.phase * 5);
      canvas
        ..save()
        ..translate(x, y)
        ..rotate(0.5 + flutter * 0.6)
        ..scale(0.55 + 0.45 * flutter.abs(), 1);
      _drawPetal(canvas, petal.size, petal.color);
      canvas.restore();
    }
  }

  /// 양 끝이 뾰족한 잎 모양.
  void _drawPetal(Canvas canvas, double size, Color color) {
    final w = size;
    final h = size * 0.66;
    final path = Path()
      ..moveTo(-w / 2, 0)
      ..quadraticBezierTo(-w / 6, -h, w / 2, 0)
      ..quadraticBezierTo(w / 6, h, -w / 2, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.9));
  }

  @override
  bool shouldRepaint(_PetalsPainter old) => false;
}

/// 표지 밑의 첫 장. 표지가 넘어갈 때 잠깐 보인다.
///
/// 빈 줄 종이 대신 사진 한 장이 테이프로 붙어 있고 손글씨가 몇 줄 적힌 앨범
/// 속지처럼 그린다. 사진과 글씨는 장식이고 실제 이야기를 담지 않는다.
class _InnerPage extends StatelessWidget {
  const _InnerPage({required this.scale});

  /// 기준 너비 268 대비 비율.
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFBF6EC),
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(3),
          right: Radius.circular(10),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // 책등 쪽으로 종이가 말려 들어가는 그늘.
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 28 * s,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0x26000000), Color(0x00000000)],
                ),
              ),
            ),
          ),
          Positioned(
            left: 36 * s,
            right: 24 * s,
            top: 34 * s,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Transform.rotate(
                  angle: -0.05,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 150 * s,
                        padding: EdgeInsets.fromLTRB(
                          6 * s,
                          6 * s,
                          6 * s,
                          14 * s,
                        ),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: SizedBox(
                          height: 100 * s,
                          width: double.infinity,
                          child: const CustomPaint(painter: _SnapshotPainter()),
                        ),
                      ),
                      // 사진을 붙인 테이프.
                      Positioned(
                        left: 50 * s,
                        top: -8 * s,
                        width: 50 * s,
                        height: 16 * s,
                        child: Transform.rotate(
                          angle: 0.08,
                          child: const ColoredBox(color: Color(0xB3EADFC4)),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 26 * s),
                SizedBox(
                  height: 70 * s,
                  width: double.infinity,
                  child: CustomPaint(painter: _ScribblePainter(scale: s)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 속지 사진. 하늘, 해, 언덕만 있는 흑백 풍경이다.
///
/// 색이 있으면 표지가 넘어가는 잠깐에도 눈에 띄어 흑백으로 두고, 빛과 그늘의
/// 농담으로 언덕의 둥근 양감을 낸다.
class _SnapshotPainter extends CustomPainter {
  const _SnapshotPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;

    // 하늘. 위는 조금 어둡고 지평선 쪽이 밝다.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFD9D9D9), Color(0xFFF3F3F3)],
        ).createShader(rect),
    );

    // 해와 그 둘레의 번지는 빛.
    final sun = Offset(w * 0.72, h * 0.32);
    canvas.drawCircle(
      sun,
      h * 0.34,
      Paint()
        ..shader = RadialGradient(
          colors: const [Color(0x99FFFFFF), Color(0x00FFFFFF)],
        ).createShader(Rect.fromCircle(center: sun, radius: h * 0.34)),
    );
    canvas.drawCircle(sun, h * 0.1, Paint()..color = const Color(0xFFFCFCFC));

    // 먼 언덕. 해를 받는 왼쪽 위가 밝고 아래로 갈수록 어둡다.
    final far = Path()
      ..moveTo(0, h * 0.68)
      ..quadraticBezierTo(w * 0.3, h * 0.42, w * 0.62, h * 0.64)
      ..quadraticBezierTo(w * 0.82, h * 0.52, w, h * 0.62)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      far,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment(-0.6, -1),
          end: Alignment(0.4, 1),
          colors: [Color(0xFFCDCDCD), Color(0xFFB0B0B0)],
        ).createShader(Rect.fromLTWH(0, h * 0.42, w, h * 0.58)),
    );

    // 가까운 언덕. 더 진하고, 등성이에 빛이 얇게 걸린다.
    final near = Path()
      ..moveTo(0, h * 0.86)
      ..quadraticBezierTo(w * 0.45, h * 0.66, w, h * 0.84)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    final nearRect = Rect.fromLTWH(0, h * 0.66, w, h * 0.34);
    canvas.drawPath(
      near,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFA9A9A9), Color(0xFF8C8C8C)],
        ).createShader(nearRect),
    );
    final ridge = Path()
      ..moveTo(0, h * 0.86)
      ..quadraticBezierTo(w * 0.45, h * 0.66, w, h * 0.84);
    canvas.drawPath(
      ridge,
      Paint()
        ..color = const Color(0x66FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // 오래된 사진처럼 가장자리를 살짝 어둡게.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          radius: 0.85,
          colors: [Color(0x00000000), Color(0x14000000)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_SnapshotPainter old) => false;
}

/// 손글씨처럼 보이는 몇 줄. 글자가 아니라 잔물결 선이다.
class _ScribblePainter extends CustomPainter {
  const _ScribblePainter({required this.scale});

  final double scale;

  /// 줄마다 쓴 길이(폭 대비).
  static const _lengths = [0.92, 0.78, 0.86, 0.5];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x8C7A6A5A)
      ..strokeWidth = 1.3 * scale
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final gap = 17 * scale;
    for (var line = 0; line < _lengths.length; line++) {
      final y = 6 * scale + line * gap;
      final end = size.width * _lengths[line];
      final path = Path()..moveTo(0, y);
      for (var x = 0.0; x <= end; x += 2) {
        final wobble =
            math.sin(x * 0.55 + line * 1.7) * 1.6 +
            math.sin(x * 0.17 + line) * 1.1;
        path.lineTo(x, y + wobble * scale);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_ScribblePainter old) => old.scale != scale;
}
