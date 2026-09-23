import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';

/// 만남을 끝내기 전에 띄우는 확인 창이다.
///
/// 두 가지를 한 자리에서 받는다.
///
/// 1. 정말 끝낼 것인지. 녹음은 되돌릴 수 없으므로 한 번 묻는다.
/// 2. 대화에 함께한 사람 수. 계약의 `VisitSession.participantCount` 이며 STT
///    화자 분리 요청의 `speakerCount` 로 그대로 넘어간다.
///
/// **앱이 목소리를 세어 짐작하지 않는다.** 보호자가 확인해 준 수만 쓴다.
///
/// 끝내기를 누르면 그 수를, 취소하거나 창을 닫으면 `null` 을 돌려준다. 창이 떠
/// 있는 동안 녹음은 부르는 쪽에서 멈춰 두고, `null` 이 돌아오면 이어서 녹음한다.
///
/// 글은 물음 두 줄만 둔다. 녹음 시간과 안내 문구를 더 두면 눌러야 할 것이 어디
/// 있는지 찾기 어려워진다. 시간은 뒤에 있는 녹음 화면에 그대로 보인다.
Future<int?> showStopRecordingDialog(BuildContext context) {
  return showDialog<int>(
    context: context,
    // 바깥을 눌러 닫으면 취소다. 녹음이 사라지지 않으므로 막지 않는다.
    barrierDismissible: true,
    builder: (context) => const _StopRecordingDialog(),
  );
}

class _StopRecordingDialog extends StatefulWidget {
  const _StopRecordingDialog();

  @override
  State<_StopRecordingDialog> createState() => _StopRecordingDialogState();
}

class _StopRecordingDialogState extends State<_StopRecordingDialog> {
  /// 어르신과 보호자 두 사람이 가장 흔하다.
  static const _defaultCount = 2;

  /// 계약상 1 이상이다. 혼자 남아 말을 건넨 회차도 있을 수 있어 1까지 내린다.
  static const _minCount = 1;

  /// 요양 시설 면회에서 이보다 많은 경우는 드물다. 끝없이 누르게 두지 않는다.
  static const _maxCount = 8;

  int _count = _defaultCount;

  void _change(int delta) {
    final next = _count + delta;
    if (next < _minCount || next > _maxCount) return;
    setState(() => _count = next);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.background,
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: SingleChildScrollView(
        child: Padding(
          // 글이 두 줄뿐이라 위아래를 좌우보다 조금 더 준다. 그래야 창이
          // 납작해 보이지 않는다.
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.xxl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '만남을 끝낼까요?',
                style: AppTypography.sectionTitle,
                textAlign: TextAlign.center,
              ),

              // 물음을 제목 바로 아래에 붙여 한 덩어리로 읽히게 한다. 다른
              // 화면의 제목과 부제목 사이와 같은 간격이다.
              const SizedBox(height: AppSpacing.sm),

              const Text(
                '오늘 대화에 몇 분이 함께했나요?',
                // 제목보다 한 단계 연하고 얇다. 눈이 제목과 숫자에 먼저 가게
                // 두고, 이 줄은 곁들이는 설명으로 읽히게 한다.
                style: AppTypography.sub,
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: AppSpacing.xl),

              _CountStepper(
                count: _count,
                canDecrease: _count > _minCount,
                canIncrease: _count < _maxCount,
                onChange: _change,
              ),

              // 고르는 자리와 누르는 자리를 확실히 떼어 둔다.
              const SizedBox(height: AppSpacing.xxl),

              PrimaryButton(
                label: '끝내기',
                onPressed: () => Navigator.of(context).pop(_count),
              ),
              const SizedBox(height: AppSpacing.md),
              SecondaryButton(
                label: '이어서 녹음',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 사람 수를 빼고 더하는 자리다.
///
/// 글자를 키워도 눌리는 자리가 줄지 않게 원 크기를 고정하고, 가운데 숫자만
/// 늘어나게 둔다.
class _CountStepper extends StatelessWidget {
  const _CountStepper({
    required this.count,
    required this.canDecrease,
    required this.canIncrease,
    required this.onChange,
  });

  final int count;
  final bool canDecrease;
  final bool canIncrease;
  final void Function(int delta) onChange;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _StepButton(
          key: const Key('participantMinus'),
          icon: Icons.remove,
          label: '한 명 줄이기',
          onTap: canDecrease ? () => onChange(-1) : null,
        ),
        Expanded(
          child: Semantics(
            liveRegion: true,
            label: '참여자 $count명',
            excludeSemantics: true,
            child: Text(
              '$count명',
              key: const Key('participantCount'),
              style: AppTypography.screenTitle,
              textAlign: TextAlign.center,
            ),
          ),
        ),
        _StepButton(
          key: const Key('participantPlus'),
          icon: Icons.add,
          label: '한 명 늘리기',
          onTap: canIncrease ? () => onChange(1) : null,
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;

  /// `null` 이면 더 갈 곳이 없다는 뜻이다.
  final VoidCallback? onTap;

  /// `app/DESIGN.md` 의 최소 터치 크기를 지킨다.
  static const _size = 56.0;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: enabled ? AppColors.ink : AppColors.line,
              width: 2,
            ),
          ),
          child: Icon(
            icon,
            size: 28,
            color: enabled ? AppColors.ink : AppColors.textDisabled,
          ),
        ),
      ),
    );
  }
}
