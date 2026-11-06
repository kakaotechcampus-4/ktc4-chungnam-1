import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// 마스코트가 지금 무엇을 하는지.
enum MascotPhase {
  /// 둥실둥실 떠 있다.
  idle,

  /// 가끔 왼쪽이나 오른쪽을 잠깐 본다. 떠 있는 움직임은 그대로다.
  looking,

  /// 눌렸다. 눈웃음과 함께 꾹 눌렸다가 통 튀고 하트가 한두 개 떠오른다.
  tapReaction,

  /// 대화 카드가 다 만들어졌다. `><` 얼굴로 천천히 통통 뛰며 반짝인다.
  success,
}

/// 밖에서 마스코트에게 일을 시킨다. 지금은 성공 축하 하나다.
class MascotController extends ChangeNotifier {
  /// 성공 움직임을 한 번 재생한다. 재생 중이면 처음부터 다시 한다.
  void celebrate() => notifyListeners();
}

/// 홈의 화분 마스코트.
///
/// 그림은 모두 같은 600x600 투명 캔버스(`assets/images/mascot/`)라 자르지 않고
/// 같은 [size] 정사각 영역에 그린다. 그림을 바꿀 때는 새 그림을 위에 겹쳐
/// 서서히 보이게 해 뚝 끊기지 않게 한다. 그림자, 반짝이와 하트는 코드로 그린다.
///
/// 기기의 `움직임 줄이기`가 켜져 있으면 몸을 움직이지 않고 표정만 바꾼다.
/// 장식이라 화면 읽기에서는 뺀다.
class Mascot extends StatefulWidget {
  const Mascot({
    super.key,
    required this.size,
    this.controller,
    this.onReact,
    this.cheerful = false,
    this.hopping = false,
  });

  /// 정사각 영역의 한 변. 그림자는 이 영역 안 아래쪽에 그린다.
  final double size;

  final MascotController? controller;

  /// 눌러서 반응을 시작했을 때 부른다. 반응 중이거나 축하 중이라 무시한
  /// 누름에는 부르지 않는다.
  final VoidCallback? onReact;

  /// `true` 인 동안 평소 얼굴 대신 `><` 신나는 얼굴로 떠 있고 둘러보지
  /// 않는다. 홈은 카드 완성 말풍선이 떠 있는 동안 켠다. 눌렀을 때의 반응은
  /// 그대로 한다.
  final bool cheerful;

  /// `true` 면 떠 있는 대신 제자리에서 천천히 콩콩 뛰고, 뛸 때마다 하트가 한두
  /// 개 떠오른다. 누름에는 반응하지 않는다. 온보딩에서 [cheerful] 과 함께 쓴다.
  final bool hopping;

  /// `false` 면 떠 있기와 둘러보기를 하지 않는다. 끝나지 않는 움직임이
  /// 화면이 멈추기를 기다리는 위젯 테스트를 막으므로
  /// `test/flutter_test_config.dart` 가 끈다. 앱에서는 바꾸지 않는다.
  static bool motion = true;

  static const _dir = 'assets/images/mascot';
  static const idleAsset = '$_dir/idle.webp';
  static const lookLeftAsset = '$_dir/look_left.webp';
  static const lookRightAsset = '$_dir/look_right.webp';
  static const tapAsset = '$_dir/tap.webp';
  static const successAsset = '$_dir/success.webp';

  /// 눈을 감고 잠든 얼굴. 보호자 위로 화면의 [SleepingMascot] 이 쓴다. 홈에서는
  /// 쓰지 않아 [assets] 에 넣지 않는다.
  static const sleepAsset = '$_dir/sleep.webp';

  static const assets = [
    idleAsset,
    lookLeftAsset,
    lookRightAsset,
    tapAsset,
    successAsset,
  ];

  @override
  State<Mascot> createState() => _MascotState();
}

class _MascotState extends State<Mascot> with TickerProviderStateMixin {
  /// 그림 속 화분 바닥의 높이(위에서부터 비율). 눌림과 그림자의 기준이다.
  static const _footY = 0.89;

  /// 그림을 바꿀 때 겹치는 시간. 고개를 돌릴 때는 천천히 바꾼다.
  static const _quickSwap = Duration(milliseconds: 180);
  static const _lookSwap = Duration(milliseconds: 650);
  static const _successSwap = Duration(milliseconds: 350);

  final _random = math.Random();

  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  late final AnimationController _tap = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..addStatusListener(_onTapStatus);
  late final AnimationController _success = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..addStatusListener(_onSuccessStatus);
  late final AnimationController _heart = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  /// 콩콩 한 번. 뒤쪽은 쉬는 시간이라 너무 빨리 뛰지 않는다.
  late final AnimationController _hop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  )..addStatusListener(_onHopStatus);

  MascotPhase _phase = MascotPhase.idle;
  String _lookAsset = Mascot.lookLeftAsset;
  Duration _swap = _quickSwap;
  List<_Heart> _hearts = const [];
  Timer? _lookTimer;
  bool _precached = false;
  bool _still = false;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_celebrate);
    _scheduleLook();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 바꿀 그림을 미리 읽어 두어 처음 바꾸는 순간 비지 않게 한다.
    if (!_precached) {
      _precached = true;
      for (final asset in Mascot.assets) {
        unawaited(precacheImage(AssetImage(asset), context));
      }
    }
    _still = !Mascot.motion || MediaQuery.disableAnimationsOf(context);
    _syncMotion();
  }

  /// 떠 있기와 콩콩 중 지금 맞는 것을 돌린다.
  void _syncMotion() {
    final hop = widget.hopping && !_still;
    final float = !widget.hopping && !_still;
    if (float && !_float.isAnimating) {
      _float.repeat(reverse: true);
    } else if (!float) {
      _float.stop();
      _float.value = 0;
    }
    if (hop && !_hop.isAnimating) {
      _hopOnce();
    } else if (!hop) {
      _hop.stop();
      _hop.value = 0;
    }
  }

  void _hopOnce() {
    _spawnHearts();
    _heart.forward(from: 0);
    _hop.forward(from: 0);
  }

  void _onHopStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && widget.hopping && !_still) {
      _hopOnce();
    }
  }

  @override
  void didUpdateWidget(Mascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_celebrate);
      widget.controller?.addListener(_celebrate);
    }
    // 신나는 얼굴과 평소 얼굴을 오갈 때는 천천히 바꾼다.
    if (oldWidget.cheerful != widget.cheerful) _swap = _successSwap;
    if (oldWidget.hopping != widget.hopping) _syncMotion();
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_celebrate);
    _lookTimer?.cancel();
    _float.dispose();
    _tap.dispose();
    _success.dispose();
    _heart.dispose();
    _hop.dispose();
    super.dispose();
  }

  // ── 상태 바꾸기 ──────────────────────────────────

  void _setPhase(MascotPhase phase) {
    if (!mounted || _phase == phase) return;
    final from = _phase;
    setState(() {
      _phase = phase;
      // 고개를 돌리거나 돌아올 때, 축하를 시작하거나 마칠 때는 천천히 바꾼다.
      _swap = switch ((from, phase)) {
        (MascotPhase.looking, _) || (_, MascotPhase.looking) => _lookSwap,
        (MascotPhase.success, _) || (_, MascotPhase.success) => _successSwap,
        _ => _quickSwap,
      };
    });
  }

  /// 5~10초에 한 번 둘러본다.
  void _scheduleLook() {
    _lookTimer?.cancel();
    if (!Mascot.motion) return;
    _lookTimer = Timer(
      Duration(milliseconds: 5000 + _random.nextInt(5000)),
      _look,
    );
  }

  void _look() {
    if (!mounted) return;
    // 다른 화면이 위에 있으면 보이지 않으므로 다음으로 미룬다.
    if (_phase != MascotPhase.idle ||
        widget.cheerful ||
        widget.hopping ||
        !TickerMode.valuesOf(context).enabled) {
      _scheduleLook();
      return;
    }
    _lookAsset = _random.nextBool()
        ? Mascot.lookLeftAsset
        : Mascot.lookRightAsset;
    _setPhase(MascotPhase.looking);
    _lookTimer = Timer(const Duration(milliseconds: 2400), () {
      if (_phase == MascotPhase.looking) _setPhase(MascotPhase.idle);
      _scheduleLook();
    });
  }

  /// 하트를 한두 개 새로 정한다.
  void _spawnHearts() {
    _hearts = [
      for (var i = 0, n = 1 + _random.nextInt(2); i < n; i++)
        _Heart(
          // 첫째는 오른쪽, 둘째는 왼쪽 위로 조금 늦게 떠오른다.
          x: i == 0
              ? 0.64 + _random.nextDouble() * 0.1
              : 0.28 + _random.nextDouble() * 0.1,
          delay: i * 0.18,
          size: 0.075 + _random.nextDouble() * 0.02,
        ),
    ];
  }

  void _onTap() {
    // 반응 중이거나 축하 중, 콩콩 뛰는 중이면 겹치지 않게 무시한다.
    if (_phase == MascotPhase.tapReaction ||
        _phase == MascotPhase.success ||
        widget.hopping) {
      return;
    }
    _lookTimer?.cancel();
    _spawnHearts();
    _setPhase(MascotPhase.tapReaction);
    _tap.forward(from: 0);
    _heart.forward(from: 0);
    widget.onReact?.call();
  }

  void _onTapStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_phase == MascotPhase.tapReaction) _setPhase(MascotPhase.idle);
    _scheduleLook();
  }

  void _celebrate() {
    _lookTimer?.cancel();
    _tap.stop();
    _heart.stop();
    _setPhase(MascotPhase.success);
    _success.forward(from: 0);
  }

  void _onSuccessStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_phase == MascotPhase.success) _setPhase(MascotPhase.idle);
    _scheduleLook();
  }

  // ── 그리기 ─────────────────────────────────────

  /// 아무 반응도 하지 않을 때의 얼굴.
  String get _restFace =>
      widget.cheerful ? Mascot.successAsset : Mascot.idleAsset;

  /// 지금 보여줄 그림.
  String get _asset => switch (_phase) {
    MascotPhase.idle => _restFace,
    MascotPhase.looking => _lookAsset,
    // 착지하고 작게 튄 뒤 원래 얼굴로 돌아온다.
    MascotPhase.tapReaction =>
      _tap.value < 0.8 ? Mascot.tapAsset : Mascot.idleAsset,
    // 바로 `><` 얼굴이 되어 약 2초 좋아한 뒤 기본으로 돌아온다.
    MascotPhase.success =>
      _success.value < 0.8 ? Mascot.successAsset : _restFace,
  };

  /// 몸의 가로 배율, 세로 배율, 위로 뜬 높이(한 변에 대한 비율, 위가 음수).
  _Pose get _pose {
    if (_still) return const _Pose();
    if (widget.hopping) return _hopFrames.at(_hop.value);
    final floatT = Curves.easeInOutSine.transform(_float.value);
    final floating = _Pose(dy: -0.035 * floatT);
    return switch (_phase) {
      MascotPhase.tapReaction => floating + _tapFrames.at(_tap.value),
      MascotPhase.success => floating + _successFrames.at(_success.value),
      _ => floating,
    };
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return ExcludeSemantics(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onTap,
        child: SizedBox.square(
          dimension: size,
          child: AnimatedBuilder(
            animation: Listenable.merge([_float, _tap, _success, _heart, _hop]),
            builder: (context, _) {
              final pose = _pose;
              // 얼마나 떠 있는지(0~1). 그림자 크기와 진하기에 쓴다.
              final lift = (-pose.dy / 0.12).clamp(0.0, 1.0);
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: size * (_footY + 0.012),
                    child: Center(
                      child: _Shadow(
                        width: size * 0.46 * (1 - 0.28 * lift),
                        height: size * 0.065 * (1 - 0.2 * lift),
                        opacity: 0.16 - 0.09 * lift,
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: Offset(0, pose.dy * size),
                    child: Transform(
                      alignment: const Alignment(0, _footY * 2 - 1),
                      transform: Matrix4.diagonal3Values(pose.sx, pose.sy, 1),
                      child: _Face(asset: _asset, size: size, swap: _swap),
                    ),
                  ),
                  if (_heart.isAnimating && !_still)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _HeartPainter(_heart.value, _hearts),
                        ),
                      ),
                    ),
                  if (_phase == MascotPhase.success && !_still)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _SparklePainter(
                            const Interval(0.1, 0.8).transform(_success.value),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 그림. 바뀌면 새 그림이 위에서 서서히 나타나고, 앞 그림은 뒤 절반 동안
/// 사라진다. 둘이 같이 반투명해져 몸이 비쳐 보이지 않게 하기 위해서다.
class _Face extends StatelessWidget {
  const _Face({required this.asset, required this.size, required this.swap});

  final String asset;
  final double size;
  final Duration swap;

  @override
  Widget build(BuildContext context) {
    final currentKey = ValueKey(asset);
    return AnimatedSwitcher(
      duration: swap,
      switchInCurve: Curves.easeOut,
      layoutBuilder: (current, previous) =>
          Stack(alignment: Alignment.center, children: [...previous, ?current]),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: child.key == currentKey
            ? animation
            : CurvedAnimation(parent: animation, curve: const Interval(0, 0.5)),
        child: child,
      ),
      child: Image.asset(
        asset,
        key: currentKey,
        width: size,
        height: size,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

class _Shadow extends StatelessWidget {
  const _Shadow({
    required this.width,
    required this.height,
    required this.opacity,
  });

  final double width;
  final double height;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _ShadowPainter(opacity),
    );
  }
}

/// 가장자리가 흐린 타원.
class _ShadowPainter extends CustomPainter {
  _ShadowPainter(this.opacity);

  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.ink.withValues(alpha: opacity)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.height * 0.35);
    canvas.drawOval(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_ShadowPainter old) => old.opacity != opacity;
}

/// 몸의 모양 하나.
class _Pose {
  const _Pose({this.sx = 1, this.sy = 1, this.dy = 0});

  final double sx;
  final double sy;
  final double dy;

  /// 떠 있는 움직임 위에 반응을 더한다. 배율은 곱하고 높이는 더한다.
  _Pose operator +(_Pose other) =>
      _Pose(sx: sx * other.sx, sy: sy * other.sy, dy: dy + other.dy);
}

/// 시간(0~1)에 따른 몸 모양. 칸 사이는 [curve] 로 잇는다.
class _Frames {
  const _Frames(this.frames);

  final List<({double t, _Pose pose, Curve curve})> frames;

  _Pose at(double t) {
    for (var i = 1; i < frames.length; i++) {
      final b = frames[i];
      if (t > b.t) continue;
      final a = frames[i - 1];
      final k = b.curve.transform(((t - a.t) / (b.t - a.t)).clamp(0.0, 1.0));
      double lerp(double x, double y) => x + (y - x) * k;
      return _Pose(
        sx: lerp(a.pose.sx, b.pose.sx),
        sy: lerp(a.pose.sy, b.pose.sy),
        dy: lerp(a.pose.dy, b.pose.dy),
      );
    }
    return frames.last.pose;
  }
}

/// 눌림: 꾹 → 통 튀어 오름 → 착지 → 작게 한 번 더 → 제자리.
const _tapFrames = _Frames([
  (t: 0, pose: _Pose(), curve: Curves.linear),
  (t: 0.13, pose: _Pose(sx: 1.1, sy: 0.86), curve: Curves.easeOut),
  (t: 0.38, pose: _Pose(sx: 0.96, sy: 1.06, dy: -0.1), curve: Curves.easeOut),
  (t: 0.58, pose: _Pose(), curve: Curves.easeIn),
  (t: 0.66, pose: _Pose(sx: 1.05, sy: 0.94), curve: Curves.easeOut),
  (t: 0.8, pose: _Pose(dy: -0.03), curve: Curves.easeOut),
  (t: 1, pose: _Pose(), curve: Curves.easeInOut),
]);

/// 성공: 살짝 움츠렸다가 천천히 크게 통, 작게 통, 더 작게 통. 그다음 그대로
/// 웃는다. 전체 2.6초라 한 번 뛰는 데 0.5초쯤 걸린다.
/// 콩콩: 살짝 움츠렸다가 통 뛰어올라 내려오고, 작게 눌렸다 펴진 뒤 쉰다.
/// 전체 1.25초 중 뒤 3분의 1은 쉬어서 차분하게 뛴다.
const _hopFrames = _Frames([
  (t: 0, pose: _Pose(), curve: Curves.linear),
  (t: 0.1, pose: _Pose(sx: 1.06, sy: 0.92), curve: Curves.easeOut),
  (t: 0.32, pose: _Pose(sx: 0.97, sy: 1.04, dy: -0.11), curve: Curves.easeOut),
  (t: 0.52, pose: _Pose(), curve: Curves.easeIn),
  (t: 0.58, pose: _Pose(sx: 1.05, sy: 0.94), curve: Curves.easeOut),
  (t: 0.68, pose: _Pose(), curve: Curves.easeOut),
  (t: 1, pose: _Pose(), curve: Curves.linear),
]);

const _successFrames = _Frames([
  (t: 0, pose: _Pose(), curve: Curves.linear),
  (t: 0.07, pose: _Pose(sx: 1.05, sy: 0.93), curve: Curves.easeOut),
  (t: 0.23, pose: _Pose(sx: 0.97, sy: 1.05, dy: -0.09), curve: Curves.easeOut),
  (t: 0.36, pose: _Pose(), curve: Curves.easeIn),
  (t: 0.4, pose: _Pose(sx: 1.04, sy: 0.96), curve: Curves.easeOut),
  (t: 0.5, pose: _Pose(dy: -0.05), curve: Curves.easeOut),
  (t: 0.59, pose: _Pose(), curve: Curves.easeIn),
  (t: 0.66, pose: _Pose(dy: -0.02), curve: Curves.easeOut),
  (t: 0.72, pose: _Pose(), curve: Curves.easeIn),
  (t: 1, pose: _Pose(), curve: Curves.linear),
]);

/// 캐릭터 둘레의 반짝이 5개. [progress] 0~1 동안 하나씩 커졌다가 사라진다.
class _SparklePainter extends CustomPainter {
  _SparklePainter(this.progress);

  final double progress;

  /// 꽃 가운데와 같은 노란색.
  static const _color = Color(0xFFF2C94C);

  /// (가로 위치, 세로 위치, 크기, 시작 시점). 위치와 크기는 한 변에 대한 비율.
  static const _sparkles = [
    (0.2, 0.22, 0.07, 0.0),
    (0.82, 0.16, 0.06, 0.12),
    (0.88, 0.5, 0.05, 0.25),
    (0.12, 0.55, 0.055, 0.35),
    (0.68, 0.04, 0.045, 0.45),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    for (final (x, y, r, start) in _sparkles) {
      // 각 반짝이는 전체의 절반 동안 나타났다 사라진다.
      final local = ((progress - start) / 0.5).clamp(0.0, 1.0);
      if (local <= 0 || local >= 1) continue;
      final grow = math.sin(local * math.pi);
      final paint = Paint()..color = _color.withValues(alpha: grow);
      _star(
        canvas,
        Offset(x * size.width, y * size.height),
        r * size.width * grow,
        paint,
      );
    }
  }

  /// 네 갈래 별.
  void _star(Canvas canvas, Offset c, double r, Paint paint) {
    final w = r * 0.28;
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + w * 0.3, c.dy - w * 0.3, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + w * 0.3, c.dy + w * 0.3, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - w * 0.3, c.dy + w * 0.3, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - w * 0.3, c.dy - w * 0.3, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.progress != progress;
}

/// 눌렀을 때 떠오르는 하트 하나. 위치와 크기는 한 변에 대한 비율이다.
class _Heart {
  const _Heart({required this.x, required this.delay, required this.size});

  final double x;

  /// 전체(0~1) 중 늦게 시작하는 만큼.
  final double delay;
  final double size;
}

/// 하트가 화분 위에서 나타나 조금 커지며 위로 떠오르다 사라진다.
class _HeartPainter extends CustomPainter {
  _HeartPainter(this.progress, this.hearts);

  final double progress;
  final List<_Heart> hearts;

  /// 볼터치와 어울리는 연분홍.
  static const _color = Color(0xFFF08A9B);

  @override
  void paint(Canvas canvas, Size size) {
    for (final heart in hearts) {
      final t = ((progress - heart.delay) / (1 - heart.delay)).clamp(0.0, 1.0);
      if (t <= 0 || t >= 1) continue;
      final rise = Curves.easeOut.transform(t);
      // 앞 20% 동안 나타나고 뒤 40% 동안 사라진다.
      final opacity = t < 0.2 ? t / 0.2 : (t > 0.6 ? (1 - t) / 0.4 : 1.0);
      final pop = Curves.easeOutBack.transform(math.min(t / 0.3, 1));
      final scale = 0.6 + 0.4 * pop;
      // 조금씩 좌우로 흔들리며 오른다.
      final sway = math.sin(t * math.pi * 2) * 0.02;
      final center = Offset(
        (heart.x + sway) * size.width,
        (0.34 - 0.22 * rise) * size.height,
      );
      final r = heart.size * size.width * scale;
      final paint = Paint()..color = _color.withValues(alpha: opacity);
      canvas.drawPath(_heartPath(center, r), paint);
    }
  }

  /// [r] 은 하트 폭의 절반.
  Path _heartPath(Offset c, double r) {
    final top = c.dy - r * 0.45;
    final bottom = c.dy + r * 0.85;
    return Path()
      ..moveTo(c.dx, bottom)
      ..cubicTo(
        c.dx - r * 1.3,
        c.dy + r * 0.05,
        c.dx - r * 0.95,
        top - r * 0.75,
        c.dx,
        top,
      )
      ..cubicTo(
        c.dx + r * 0.95,
        top - r * 0.75,
        c.dx + r * 1.3,
        c.dy + r * 0.05,
        c.dx,
        bottom,
      )
      ..close();
  }

  @override
  bool shouldRepaint(_HeartPainter old) =>
      old.progress != progress || old.hearts != hearts;
}
