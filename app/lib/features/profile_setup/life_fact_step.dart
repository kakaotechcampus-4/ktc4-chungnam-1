import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/tokens.dart';
import '../../widgets/app_surfaces.dart';
import 'setup_steps.dart';
import 'speech_input.dart';

/// 음성 입력 한 항목의 상태.
enum _Phase {
  /// 마이크를 누르기 전.
  idle,

  /// 듣고 있는 중.
  listening,

  /// 알아들었다.
  heard,

  /// 한 번 알아듣지 못했다. 다시 시도할 수 있다.
  notHeardOnce,

  /// 두 번 알아듣지 못했다. 직접 입력으로 넘어간다.
  manualInput,
}

/// B-3 ~ B-6 생애 정보 음성 입력.
///
/// 성공 화면만 만들지 않는다. 알아듣지 못한 상태와 두 번 실패한 뒤의 직접 입력
/// 까지 함께 다룬다(`app/CLAUDE.md`).
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
  _Phase _phase = _Phase.idle;
  int _attempt = 0;
  String? _heardText;
  final _manual = TextEditingController();

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

  @override
  Widget build(BuildContext context) {
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
        const Text(
          '자유롭게 말씀해주세요.',
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

        if (_phase == _Phase.manualInput)
          _ManualInput(
            controller: _manual,
            onChanged: (value) => value.trim().isEmpty
                ? widget.onCleared()
                : widget.onCaptured(value.trim()),
            onRetry: () {
              setState(() {
                _phase = _Phase.idle;
                _attempt = 0;
              });
              widget.onCleared();
            },
          )
        else
          _MicArea(
            phase: _phase,
            heardText: _heardText,
            onTap: _phase == _Phase.listening ? null : _listen,
            onRetry: _retry,
          ),

        const Spacer(flex: 3),
      ],
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
          const Text(
            '마이크를 누르고 말씀해주세요',
            style: AppTypography.sub,
          ),
      ],
    );
  }
}

class _ManualInput extends StatelessWidget {
  const _ManualInput({
    required this.controller,
    required this.onChanged,
    required this.onRetry,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '목소리를 잘 듣지 못했어요.',
          style: AppTypography.bodyStrong.copyWith(color: AppColors.danger),
        ),
        const SizedBox(height: AppSpacing.md),
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
        const SizedBox(height: AppSpacing.md),
        Center(
          child: TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: AppColors.textSub),
            child: const Text('다시 녹음하기', style: AppTypography.sub),
          ),
        ),
      ],
    );
  }
}
