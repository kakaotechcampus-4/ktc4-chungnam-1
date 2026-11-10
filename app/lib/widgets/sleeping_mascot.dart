import 'package:flutter/material.dart';

import '../design/tokens.dart';
import 'mascot.dart';

/// 눈을 감고 잠든 마스코트다. 보호자 위로 화면에 둔다.
///
/// 바닥 그림자 위에서 천천히 둥실 떠 있다. 누르면 몸이 살짝 눌렸다 돌아온다.
///
/// 기기의 애니메이션 줄이기가 켜져 있거나 테스트에서 [Mascot.motion] 을 끄면
/// 움직이지 않고 그림자와 함께 가만히 있다. 장식이라 화면 낭독기는 읽지 않는다.
class SleepingMascot extends StatefulWidget {
  const SleepingMascot({super.key, this.size = 184});

  /// 그림 한 변의 길이. 그림 아래 그림자는 이 칸 밖으로 조금 나간다.
  final double size;

  @override
  State<SleepingMascot> createState() => _SleepingMascotState();
}

class _SleepingMascotState extends State<SleepingMascot>
    with TickerProviderStateMixin {
  /// 그림에서 발끝이 닿는 높이(한 변에 대한 비율). 그림자를 여기에 둔다.
  static const _footY = 0.89;

  /// 둥실 한 번(올라갔다 내려오기)의 절반. 잠든 숨처럼 느리게 둔다.
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  /// 누르면 한 번 눌렸다 돌아오기.
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  bool _still = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = !Mascot.motion || MediaQuery.disableAnimationsOf(context);
    if (still == _still) return;
    _still = still;
    if (_still) {
      _float.stop();
      _burst.stop();
    } else {
      _float.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _float.dispose();
    _burst.dispose();
    super.dispose();
  }

  void _onTap() {
    if (_still) return;
    _burst.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final image = Image.asset(
      Mascot.sleepAsset,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );

    return ExcludeSemantics(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onTap,
        child: SizedBox.square(
          dimension: size,
          child: AnimatedBuilder(
            animation: Listenable.merge([_float, _burst]),
            builder: (context, child) {
              // 0 이면 바닥 가까이, 1 이면 가장 높이 떠 있다.
              final lift = _still
                  ? 0.0
                  : Curves.easeInOutSine.transform(_float.value);
              final dy = -size * (0.025 + 0.045 * lift);
              // 누르면 잠깐 납작해졌다가 살짝 늘어난 뒤 돌아온다.
              final squash = _still ? 0.0 : _squash(_burst.value);

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: size * (_footY + 0.03),
                    child: Center(
                      child: CustomPaint(
                        size: Size(
                          size * 0.5 * (1 - 0.22 * lift),
                          size * 0.07 * (1 - 0.15 * lift),
                        ),
                        painter: _ShadowPainter(0.17 - 0.07 * lift),
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: Offset(0, dy),
                    child: Transform(
                      alignment: const Alignment(0, _footY * 2 - 1),
                      transform: Matrix4.diagonal3Values(
                        1 + 0.06 * squash,
                        1 - 0.08 * squash,
                        1,
                      ),
                      child: child,
                    ),
                  ),
                ],
              );
            },
            child: image,
          ),
        ),
      ),
    );
  }

  /// 누른 뒤의 눌림 정도. 양수면 납작, 음수면 길쭉하다.
  static double _squash(double t) {
    if (t < 0.18) return Curves.easeOut.transform(t / 0.18);
    if (t < 0.45) {
      return 1 - 1.5 * Curves.easeInOut.transform((t - 0.18) / 0.27);
    }
    return -0.5 * (1 - Curves.easeOut.transform((t - 0.45) / 0.55));
  }
}

/// 가장자리가 흐린 타원 그림자.
class _ShadowPainter extends CustomPainter {
  _ShadowPainter(this.opacity);

  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.ink.withValues(alpha: opacity)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.height * 0.4);
    canvas.drawOval(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_ShadowPainter old) => old.opacity != opacity;
}
