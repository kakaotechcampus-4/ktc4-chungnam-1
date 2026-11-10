import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// 녹음하는 동안 마이크 원 둘레로 초록 물결이 천천히 퍼진다.
///
/// PM이 녹음 버튼을 누른 뒤 녹음이 시작됐는지 알 수 없었다(2026-11-10). 원의
/// 테두리 색이나 글자만 바뀌어서는 한눈에 보이지 않아, 녹음하는 동안 원 둘레가
/// 숨 쉬듯 움직이게 한다. E-2 녹음 화면과 B-3 ~ B-6 세부 정보의 음성 입력이
/// 함께 쓴다.
///
/// 물결은 [child] 밖에 그리고 자리를 차지하지 않는다. 원 크기와 화면 높이가
/// 그대로라 상태가 바뀌어도 아래 글자와 버튼이 오르내리지 않는다. 원 밖으로
/// [spread] 만큼 그리므로 둘레에 그만큼 빈 자리를 두는 곳에 쓴다.
///
/// [active] 가 아니면(멈춤, 글로 옮기는 중, 실패, 대기) 아무것도 그리지 않는다.
/// 기기의 움직임 줄이기가 켜져 있으면 움직이지 않고 원 둘레에 고정된 고리를
/// 그린다. 녹음 중이라는 것은 화면의 글자가 함께 알리므로 화면 낭독기는 이
/// 그림을 읽지 않는다.
class RecordingPulse extends StatefulWidget {
  const RecordingPulse({super.key, required this.active, required this.child});

  /// 지금 녹음하고 있다.
  final bool active;

  /// 마이크 원. 물결은 이 영역에 꼭 맞는 원을 기준으로 그린다.
  final Widget child;

  /// 원 밖으로 물결이 퍼지는 거리. 세부 정보 입력에서 원과 아래 안내 글자
  /// 사이(16)에 닿지 않게 둔다.
  static const spread = 14.0;

  /// `false` 면 움직이지 않고 움직임 줄이기처럼 고정된 고리를 그린다. 끝나지
  /// 않는 움직임이 화면이 멈추기를 기다리는 위젯 테스트를 막으므로
  /// `test/flutter_test_config.dart` 가 끈다. 앱에서는 바꾸지 않는다.
  static bool motion = true;

  @override
  State<RecordingPulse> createState() => _RecordingPulseState();
}

class _RecordingPulseState extends State<RecordingPulse>
    with SingleTickerProviderStateMixin {
  /// 물결 하나가 원에서 퍼져 사라지는 시간. 숨 쉬듯 느리게 둔다.
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  bool _still = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = !RecordingPulse.motion || MediaQuery.disableAnimationsOf(context);
    _syncMotion();
  }

  @override
  void didUpdateWidget(RecordingPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _syncMotion();
  }

  /// 녹음 중이고 움직여도 될 때만 물결을 돌린다.
  void _syncMotion() {
    if (widget.active && !_still) {
      if (!_wave.isAnimating) _wave.repeat();
    } else {
      _wave.stop();
      _wave.value = 0;
    }
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        // 원과 따로 그려 물결이 움직일 때 원과 주변을 다시 그리지 않게 한다.
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _PulsePainter(
                  wave: _wave,
                  active: widget.active,
                  still: _still,
                ),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter({required this.wave, required this.active, required this.still})
    : super(repaint: wave);

  final Animation<double> wave;
  final bool active;
  final bool still;

  /// 물결이 원에서 막 나올 때의 진하기. 퍼지며 옅어져 끝에서 사라진다.
  static const _waveAlpha = 0.4;

  /// 움직이지 않을 때의 고리. 원과 조금 떨어뜨려 원의 테두리와 겹쳐 보이지
  /// 않게 한다. 바깥 끝이 [RecordingPulse.spread] 안에 든다.
  static const _ringGap = 5.0;
  static const _ringWidth = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (!active) return;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;

    if (still) {
      canvas.drawCircle(
        center,
        radius + _ringGap + _ringWidth / 2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _ringWidth
          ..color = HomeColors.accent,
      );
      return;
    }

    // 물결 두 개를 반 바퀴 어긋나게 보내 끊기지 않고 이어 퍼지게 한다. 원
    // 바깥 띠로 그려 원 안의 색에 섞이지 않는다.
    for (final shift in const [0.0, 0.5]) {
      final t = (wave.value + shift) % 1;
      final width = RecordingPulse.spread * Curves.easeOut.transform(t);
      if (width <= 0) continue;
      canvas.drawCircle(
        center,
        radius + width / 2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..color = HomeColors.accent.withValues(alpha: _waveAlpha * (1 - t)),
      );
    }
  }

  @override
  bool shouldRepaint(_PulsePainter old) =>
      old.wave != wave || old.active != active || old.still != still;
}
