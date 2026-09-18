import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/tokens.dart';
import '../../widgets/app_surfaces.dart';
import 'setup_steps.dart';
import 'speech_input.dart';

/// 생애 정보 한 항목의 상태.
enum _Phase {
  /// 답하는 방법을 고르기 전. 화면에 들어오면 여기서 시작한다.
  choosing,

  /// 마이크를 누르기 전.
  idle,

  /// 듣고 있는 중.
  listening,

  /// 알아들었다.
  heard,

  /// 한 번 알아듣지 못했다. 다시 시도할 수 있다.
  notHeardOnce,

  /// 글로 직접 쓴다. 처음부터 고른 경우와 두 번 실패한 경우 모두 여기로 온다.
  manualInput,
}

/// B-3 ~ B-6 생애 정보 입력.
///
/// 말로 답하는 길과 글로 답하는 길을 처음부터 함께 연다. 성공 화면만 만들지
/// 않는다. 알아듣지 못한 상태와 두 번 실패한 뒤의 직접 입력까지 함께 다룬다
/// (`app/CLAUDE.md`).
class LifeFactStepView extends ConsumerStatefulWidget {
  const LifeFactStepView({
    required this.step,
    required this.onCaptured,
    required this.onCleared,
    super.key,
  });

  final LifeFactStep step;

  /// 문장을 얻었을 때. 직접 입력으로 얻은 것도 포함한다.
  final ValueChanged<String> onCaptured;

  /// 값을 비웠을 때.
  final VoidCallback onCleared;

  @override
  ConsumerState<LifeFactStepView> createState() => _LifeFactStepViewState();
}

class _LifeFactStepViewState extends ConsumerState<LifeFactStepView> {
  _Phase _phase = _Phase.choosing;
  int _attempt = 0;
  String? _heardText;
  final _manual = TextEditingController();

  /// 직접 입력에 음성 실패로 온 것인지, 사용자가 처음부터 고른 것인지.
  /// 따로 값을 두지 않고 음성 시도 횟수로 구분한다.
  bool get _cameFromFailure => _attempt >= 2;

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  Future<void> _listen() async {
    setState(() {
      _phase = _Phase.listening;
      _attempt += 1;
    });

    final input = await ref.read(speechInputProvider.future);
    final outcome = await input.listen(
      category: widget.step.category,
      attempt: _attempt,
    );
    if (!mounted) return;

    switch (outcome) {
      case SpeechHeard(:final text):
        setState(() {
          _phase = _Phase.heard;
          _heardText = text;
        });
        widget.onCaptured(text);
      case SpeechNotHeard():
        setState(() {
          // 2회 실패하면 직접 입력으로 넘어간다.
          _phase = _attempt >= 2 ? _Phase.manualInput : _Phase.notHeardOnce;
        });
        widget.onCleared();
    }
  }

  void _retry() {
    setState(() {
      _phase = _Phase.idle;
      _heardText = null;
    });
    widget.onCleared();
  }

  /// 말로 답하러 간다. 방법을 처음 고를 때와 글로 쓰다 바꿀 때, 두 번 실패한 뒤
  /// 다시 녹음할 때 모두 이리로 온다. 어느 쪽이든 마이크 화면이 바로 나온다.
  void _startVoice() {
    setState(() {
      _phase = _Phase.idle;
      _attempt = 0;
      _heardText = null;
      _manual.clear();
    });
    widget.onCleared();
  }

  /// 글로 답하러 간다. 음성을 거치지 않았으므로 시도 횟수를 0 으로 둔다.
  void _startText() {
    setState(() {
      _phase = _Phase.manualInput;
      _attempt = 0;
      _heardText = null;
    });
    widget.onCleared();
  }

  @override
  Widget build(BuildContext context) {
    final choosing = _phase == _Phase.choosing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(flex: 2),
        Text(
          widget.step.question,
          style: AppTypography.screenTitle,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          choosing ? '편한 방법으로 답해주세요.' : '자유롭게 말씀해주세요.',
          style: AppTypography.sub,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.section),

        AppSurfaceBox(
          child: Column(
            children: [
              for (final example in widget.step.examples)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    example,
                    style: AppTypography.sub.copyWith(
                      color: AppColors.textDisabled,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
        const Spacer(flex: 3),

        if (choosing)
          _InputMethodChoice(onVoice: _startVoice, onText: _startText)
        else if (_phase == _Phase.manualInput)
          _ManualInput(
            controller: _manual,
            afterFailure: _cameFromFailure,
            onChanged: (value) => value.trim().isEmpty
                ? widget.onCleared()
                : widget.onCaptured(value.trim()),
          )
        else
          _MicArea(
            phase: _phase,
            heardText: _heardText,
            onTap: _phase == _Phase.listening ? null : _listen,
            onRetry: _retry,
          ),

        const Spacer(flex: 3),

        // 방법을 바꾸는 길은 안내 문구에서 멀리 떼어 화면 아래에 둔다. 문구
        // 바로 밑에 글자만 두면 안내의 일부인지 누르는 것인지 구분되지 않는다.
        if (_phase == _Phase.manualInput)
          _SwitchMethodButton(
            icon: Icons.record_voice_over_outlined,
            label: _cameFromFailure ? '다시 녹음하기' : '말로 답할게요',
            onTap: _startVoice,
          )
        else if (!choosing && _phase != _Phase.listening)
          _SwitchMethodButton(
            icon: Icons.chat_bubble_outline,
            label: '글로 답할게요',
            onTap: _startText,
          ),
      ],
    );
  }
}

/// 답하는 방법을 고르는 두 버튼이다.
///
/// 예전에는 음성으로 두 번 실패해야 직접 입력이 열렸다. 지금은 두 길을 같은
/// 무게로 나란히 둔다. 어느 쪽도 실패한 뒤의 대안으로 보이지 않게 한다.
class _InputMethodChoice extends StatelessWidget {
  const _InputMethodChoice({required this.onVoice, required this.onText});

  final VoidCallback onVoice;
  final VoidCallback onText;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MethodButton(
            // 고른 뒤 나오는 녹음 화면에 마이크 버튼이 따로 있어 겹치지 않게 둔다.
            icon: Icons.record_voice_over_outlined,
            label: '말로 답하기',
            onTap: onVoice,
          ),
        ),
        const SizedBox(width: AppSpacing.item),
        Expanded(
          child: _MethodButton(
            icon: Icons.chat_bubble_outline,
            label: '글로 답하기',
            onTap: onText,
          ),
        ),
      ],
    );
  }
}

class _MethodButton extends StatelessWidget {
  const _MethodButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: SizedBox(
        // 주 사용자가 50~60대다. 고르는 자리를 넉넉하게 잡는다.
        height: 96,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 44, color: AppColors.ink),
            const SizedBox(height: AppSpacing.lg),
            Text(label, style: AppTypography.bodyStrong),
          ],
        ),
      ),
    );
  }
}

/// 답하는 방법을 바꾸는 버튼이다.
///
/// 안내 문구 바로 아래에 글자만 두면 안내의 일부인지 누르는 것인지 구분되지
/// 않는다. 면과 테두리를 준 알약 모양으로 감싸고 화면 아래로 내린다.
class _SwitchMethodButton extends StatelessWidget {
  const _SwitchMethodButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Container(
            height: AppSizes.minTouch,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: AppColors.ink),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  label,
                  style: AppTypography.sub.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MicArea extends StatelessWidget {
  const _MicArea({
    required this.phase,
    required this.heardText,
    required this.onTap,
    required this.onRetry,
  });

  final _Phase phase;
  final String? heardText;
  final VoidCallback? onTap;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final failed = phase == _Phase.notHeardOnce;
    final heard = phase == _Phase.heard;

    return Column(
      children: [
        SizedBox(
          width: 120,
          height: 120,
          child: heard
              ? Container(
                  decoration: const BoxDecoration(
                    color: AppColors.ink,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    size: 56,
                    color: AppColors.background,
                  ),
                )
              : InkWell(
                  onTap: onTap,
                  customBorder: const CircleBorder(),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: failed ? AppColors.danger : AppColors.line,
                        width: 2,
                      ),
                    ),
                    child: phase == _Phase.listening
                        ? const Padding(
                            padding: EdgeInsets.all(36),
                            child: CircularProgressIndicator(strokeWidth: 3),
                          )
                        : Icon(
                            Icons.mic,
                            size: 48,
                            color: failed ? AppColors.danger : AppColors.ink,
                          ),
                  ),
                ),
        ),
        const SizedBox(height: AppSpacing.lg),

        if (phase == _Phase.listening)
          const Text('듣고 있어요', style: AppTypography.body)
        else if (failed)
          Text(
            '목소리를 잘 듣지 못했어요.',
            style: AppTypography.body.copyWith(color: AppColors.danger),
          )
        else if (heard) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(
              heardText ?? '',
              style: AppTypography.body,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: AppColors.textSub),
            child: const Text('다시 녹음하기', style: AppTypography.sub),
          ),
        ] else
          const Text('마이크를 누르고 말씀해주세요', style: AppTypography.sub),
      ],
    );
  }
}

class _ManualInput extends StatelessWidget {
  const _ManualInput({
    required this.controller,
    required this.afterFailure,
    required this.onChanged,
  });

  final TextEditingController controller;

  /// 두 번 알아듣지 못해 넘어온 경우다. 사용자가 처음부터 고른 경우와 안내
  /// 문구가 달라야 한다. 스스로 고른 사람에게 실패를 알릴 이유가 없다.
  final bool afterFailure;

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (afterFailure) ...[
          Text(
            '목소리를 잘 듣지 못했어요.',
            style: AppTypography.bodyStrong.copyWith(color: AppColors.danger),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        TextField(
          controller: controller,
          onChanged: onChanged,
          maxLines: 4,
          style: AppTypography.body,
          decoration: InputDecoration(
            hintText: '여기를 눌러 직접 작성해주세요.',
            hintStyle: AppTypography.body.copyWith(
              color: AppColors.textDisabled,
            ),
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: const EdgeInsets.all(AppSpacing.lg),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              borderSide: const BorderSide(color: AppColors.ink, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}
