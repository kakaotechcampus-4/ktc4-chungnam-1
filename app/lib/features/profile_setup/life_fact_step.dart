import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/screen_awake.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_surfaces.dart';
import '../../widgets/recording_pulse.dart';
import 'setup_steps.dart';
import 'speech_input.dart';

/// 생애 정보 한 항목의 상태.
enum _Phase {
  /// 답하는 방법을 고르기 전. 적어 둔 답이 없으면 여기서 시작한다.
  choosing,

  /// 마이크를 누르기 전.
  idle,

  /// 듣고 있는 중. 보호자가 다 말했다고 알릴 때까지 이어진다.
  listening,

  /// 녹음을 끝내고 글로 옮긴 결과를 기다리는 중.
  transcribing,

  /// 알아들었다.
  heard,

  /// 한 번 알아듣지 못했다. 다시 시도할 수 있다.
  notHeardOnce,

  /// 서버에 닿지 못해 글로 옮기지 못했다. 녹음이 남아 있어 다시 보낼 수 있다.
  sendFailed,

  /// 글로 직접 쓴다. 처음부터 고른 경우와 실패한 경우 모두 여기로 온다.
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
    this.initialText,
    super.key,
  });

  final LifeFactStep step;

  /// 이 항목에 이미 적어 둔 답. 입력하다 나갔다 돌아오거나 앞 단계로 돌아왔을
  /// 때 들고 온다. 있으면 빈 화면 대신 이 답을 글 입력칸에 채워 보여준다.
  final String? initialText;

  /// 문장을 얻었을 때. 직접 입력으로 얻은 것도 포함한다.
  final ValueChanged<String> onCaptured;

  /// 값을 비웠을 때.
  final VoidCallback onCleared;

  @override
  ConsumerState<LifeFactStepView> createState() => _LifeFactStepViewState();
}

class _LifeFactStepViewState extends ConsumerState<LifeFactStepView>
    with WidgetsBindingObserver {
  _Phase _phase = _Phase.choosing;

  /// 알아들었는지 판정을 받은 녹음 수. 서버에 닿지 못한 실패는 세지 않는다.
  int _attempt = 0;
  String? _heardText;
  final _manual = TextEditingController();

  /// 진행 중인 녹음. 녹음이 시작되기 전과 끝낸 뒤에는 없다.
  SpeechRecording? _recording;

  /// 보내지 못해 남겨 둔 녹음. [_Phase.sendFailed] 에서만 있다.
  SpeechRecording? _unsent;

  /// 남겨 둔 녹음을 다시 보낸 횟수. 새로 녹음하면 0 이다.
  int _resends = 0;

  /// 알아들은 녹음이 최대 길이에 닿아 멈춘 것이다.
  bool _stoppedAtLimit = false;

  /// 직접 입력으로 넘어온 이유. 사용자가 처음부터 고른 경우는 없다.
  String? _manualNotice;

  /// 직접 입력에 실패로 온 것인지, 사용자가 처음부터 고른 것인지.
  bool get _cameFromFailure => _manualNotice != null;

  /// 이 항목에서는 다시 녹음해도 같은 결과라 말로 돌아가는 버튼을 숨긴다.
  /// 동의 없음, 형식 오류처럼 다시 해도 안 되는 실패로 넘어온 경우다.
  bool _voiceUnavailable = false;

  /// 재시도를 이만큼 실패하면 직접 입력으로 넘어간다.
  static const _maxResends = 2;

  // 넘어온 이유마다 문구가 다르다. 다시 녹음하기를 두는 경우는 원인이 풀리면
  // 다시 말로 답할 수 있는 경우다.
  static const _notHeardNotice = '목소리를 잘 듣지 못했어요.\n글로 적어 보시겠어요?';
  static const _connectionNotice = '지금은 연결이 원활하지 않아요.\n글로 적어 보시겠어요?';
  static const _micDeniedNotice = '마이크가 꺼져 있어요.\n휴대전화 설정에서 새록의 마이크를 켜 주세요.';
  // 세부 정보는 선택 사항이다. 글을 쓰기 어려운 사람도 막히지 않게 화면
  // 아래 `건너뛰기` 로 넘어갈 수 있음을 알린다.
  static const _unavailableNotice = '지금은 말씀을 글로 옮기기 어려워요.\n글로 적거나 건너뛰어도 괜찮아요.';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 말로 얻은 답인지 글로 얻은 답인지는 남지 않는다. 어느 쪽이든 고칠 수 있게
    // 글 입력칸에 채운다. 값은 이미 저장본에 있으므로 다시 알리지 않는다.
    final saved = widget.initialText?.trim() ?? '';
    if (saved.isNotEmpty) {
      _phase = _Phase.manualInput;
      _manual.text = saved;
    }
  }

  /// 키보드가 오르내리면 다시 그린다. [_keyboardOpen] 참고.
  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  /// 키보드가 올라와 있다.
  ///
  /// 이 화면은 `Scaffold` 본문이라 [MediaQuery] 의 키보드 높이가 늘 0 이다.
  /// `Scaffold` 가 본문 높이를 줄이며 그 값을 지운다. 그래서 창의 값을 직접
  /// 읽고, 바뀔 때는 [didChangeMetrics] 로 다시 그린다.
  bool get _keyboardOpen => View.of(context).viewInsets.bottom > 0;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 듣는 중이거나 보내지 못한 녹음이 있으면 화면을 벗어날 때 지운다.
    _recording?.cancel();
    _unsent?.cancel();
    _manual.dispose();
    super.dispose();
  }

  /// 남겨 둔 녹음을 버린다. 새로 녹음하거나 방법을 바꿀 때 부른다.
  Future<void> _dropUnsent() async {
    final unsent = _unsent;
    _unsent = null;
    _resends = 0;
    await unsent?.cancel();
  }

  Future<void> _startListening() async {
    // 남은 녹음을 다 지운 뒤 시작한다. 지우는 중에 새 녹음을 시작하면 지우는
    // 쪽이 녹음 중인 장치를 멈출 수 있다.
    final dropping = _dropUnsent();
    setState(() {
      _phase = _Phase.listening;
      _stoppedAtLimit = false;
    });

    final input = await ref.read(speechInputProvider.future);
    await dropping;
    final SpeechRecording recording;
    try {
      recording = await input.start(
        category: widget.step.category,
        attempt: _attempt + 1,
      );
    } on SpeechStartFailure catch (failure) {
      if (!mounted) return;
      _toManual(switch (failure.problem) {
        SpeechStartProblem.micDenied => _micDeniedNotice,
        SpeechStartProblem.unavailable => _unavailableNotice,
      }, voiceUnavailable: failure.problem == SpeechStartProblem.unavailable);
      return;
    }
    if (!mounted) {
      await recording.cancel();
      return;
    }
    setState(() => _recording = recording);

    // 최대 길이에 닿으면 다 말했다고 알린 것처럼 끝낸다.
    unawaited(
      recording.limitReached.then((_) {
        if (mounted && _recording == recording) {
          _finishListening(atLimit: true);
        }
      }),
    );
  }

  /// 녹음을 끝내고 글로 옮기는 동안 기다린다.
  Future<void> _finishListening({bool atLimit = false}) async {
    final recording = _recording;
    // 녹음이 아직 시작되지 않았다.
    if (recording == null) return;

    setState(() {
      _recording = null;
      _phase = _Phase.transcribing;
    });

    final outcome = await recording.finish();
    if (!mounted) {
      // 보내지 못해 남은 녹음이 있어도 화면을 벗어났으니 지운다.
      await recording.cancel();
      return;
    }
    _settle(recording, outcome, atLimit: atLimit);
  }

  /// 보내지 못한 녹음을 다시 보낸다. 다시 말하지 않아도 된다.
  Future<void> _resend() async {
    final recording = _unsent;
    if (recording == null) return;

    setState(() {
      _unsent = null;
      _resends += 1;
      _phase = _Phase.transcribing;
    });

    final outcome = await recording.resend();
    if (!mounted) {
      await recording.cancel();
      return;
    }
    _settle(recording, outcome, atLimit: _stoppedAtLimit);
  }

  void _settle(
    SpeechRecording recording,
    SpeechOutcome outcome, {
    required bool atLimit,
  }) {
    switch (outcome) {
      case SpeechHeard(:final text):
        setState(() {
          _attempt += 1;
          _resends = 0;
          _phase = _Phase.heard;
          _heardText = text;
          _stoppedAtLimit = atLimit;
        });
        widget.onCaptured(text);
      case SpeechNotHeard():
        _resends = 0;
        _attempt += 1;
        // 2회 실패하면 직접 입력으로 넘어간다.
        if (_attempt >= 2) {
          _toManual(_notHeardNotice);
        } else {
          setState(() => _phase = _Phase.notHeardOnce);
          widget.onCleared();
        }
      case SpeechFailed(canResend: true) when _resends < _maxResends:
        setState(() {
          _unsent = recording;
          _stoppedAtLimit = atLimit;
          _phase = _Phase.sendFailed;
        });
        widget.onCleared();
      // 재시도를 다 써도 연결 문제다. 연결이 돌아오면 다시 말할 수 있다.
      case SpeechFailed(canResend: true):
        recording.cancel();
        _toManual(_connectionNotice);
      case SpeechFailed():
        recording.cancel();
        _toManual(_unavailableNotice, voiceUnavailable: true);
    }
  }

  /// 실패해서 직접 입력으로 넘어간다. [notice] 로 이유를 알린다.
  void _toManual(String notice, {bool voiceUnavailable = false}) {
    unawaited(_dropUnsent());
    setState(() {
      _phase = _Phase.manualInput;
      _manualNotice = notice;
      _voiceUnavailable = voiceUnavailable;
      _heardText = null;
      _manual.clear();
    });
    widget.onCleared();
  }

  /// 알아들은 뒤 다시 녹음한다. 새로 말하는 것이라 못 알아들은 횟수도 처음부터
  /// 센다. 알아들은 녹음까지 세면 다음에 한 번만 못 알아들어도 직접 입력으로
  /// 넘어갔다.
  void _retry() {
    setState(() {
      _phase = _Phase.idle;
      _attempt = 0;
      _heardText = null;
      _stoppedAtLimit = false;
    });
    widget.onCleared();
  }

  /// 말로 답하러 간다. 방법을 처음 고를 때와 글로 쓰다 바꿀 때, 실패한 뒤
  /// 다시 녹음할 때 모두 이리로 온다. 어느 쪽이든 마이크 화면이 바로 나온다.
  void _startVoice() {
    unawaited(_dropUnsent());
    setState(() {
      _phase = _Phase.idle;
      _attempt = 0;
      _heardText = null;
      _stoppedAtLimit = false;
      _manualNotice = null;
      _voiceUnavailable = false;
      _manual.clear();
    });
    widget.onCleared();
  }

  /// 글로 답하러 간다. 음성을 거치지 않았으므로 시도 횟수를 0 으로 둔다.
  ///
  /// 알아들은 문장이 있으면 입력칸에 채운다. 틀린 곳을 고치거나 녹음이 끊긴
  /// 뒤를 이어 쓸 수 있게 하려는 것이다. 이미 넘긴 값이므로 다시 알리지 않는다.
  void _startText() {
    unawaited(_dropUnsent());
    final heard = _phase == _Phase.heard ? _heardText : null;
    setState(() {
      _phase = _Phase.manualInput;
      _attempt = 0;
      _heardText = null;
      _stoppedAtLimit = false;
      _manualNotice = null;
      _voiceUnavailable = false;
      if (heard != null) _manual.text = heard;
    });
    if (heard == null) widget.onCleared();
  }

  /// 원 아래 보조 내용(한 줄 글과 버튼)이 차지하는 가장 큰 높이.
  static double _extraHeight(BuildContext context) {
    const style = AppTypography.body;
    final line =
        MediaQuery.textScalerOf(context).scale(style.fontSize!) * style.height!;
    return AppSpacing.sm + line + AppSpacing.md + AppSizes.minTouch;
  }

  _MicArea _micArea(_MicPart part) => _MicArea(
    part: part,
    phase: _phase,
    heardText: _heardText,
    onStart: _startListening,
    onFinish: _recording == null ? null : _finishListening,
    onResend: _resend,
    stoppedAtLimit: _stoppedAtLimit,
  );

  @override
  Widget build(BuildContext context) {
    final choosing = _phase == _Phase.choosing;

    // 글로 쓰는 중 키보드가 올라오면 높이가 절반쯤으로 줄어 입력칸 아래
    // 버튼이 화면 아래 고정된 `다음` 과 겹친다. 쓰는 동안에는 질문과 입력칸만
    // 남기고 예시와 방법 바꾸기를 숨긴다. 키보드를 내리면 되돌린다.
    final typing = _phase == _Phase.manualInput && _keyboardOpen;

    // 녹음이 시작된 뒤 다 말했다고 알리거나 5분에 닿을 때까지만 화면을 켜
    // 둔다. 글로 옮기는 중, 시작 실패와 화면을 벗어날 때는 놓는다.
    return KeepScreenOn(
      enabled: _recording != null,
      child: _content(choosing: choosing, typing: typing),
    );
  }

  Widget _content({required bool choosing, required bool typing}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (typing)
          const SizedBox(height: AppSpacing.xl)
        else
          const Spacer(flex: 2),
        Text(
          widget.step.question,
          style: AppTypography.screenTitle,
          textAlign: TextAlign.center,
        ),
        if (typing) const SizedBox(height: AppSpacing.section),
        if (!typing) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            choosing ? '편한 방법으로 답해주세요.' : '자유롭게 말씀해주세요.',
            style: AppTypography.sub,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.section),

          AppSurfaceBox(
            color: HomeColors.bubble,
            child: Column(
              children: [
                for (final example in widget.step.examples)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      example,
                      style: AppTypography.sub,
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
          const Spacer(flex: 3),
        ],

        if (choosing)
          _InputMethodChoice(onVoice: _startVoice, onText: _startText)
        else if (_phase == _Phase.manualInput)
          _ManualInput(
            // 키보드가 오르내리며 앞의 항목이 빠져도 입력칸을 새로 만들지 않게
            // 한다. 새로 만들면 포커스를 잃고 키보드가 내려간다.
            key: const ValueKey('manualInput'),
            label: widget.step.label,
            controller: _manual,
            // 쓰기 시작하면 안내를 숨긴다. 키보드가 올라온 좁은 화면에서 안내가
            // 입력칸을 밀어 일부가 가려졌다.
            notice: typing ? null : _manualNotice,
            onChanged: (value) => value.trim().isEmpty
                ? widget.onCleared()
                : widget.onCaptured(value.trim()),
          )
        else
          _micArea(_MicPart.main),

        // 마이크 화면에서는 원 아래 빈 공간의 맨 위에 보조 내용(다 말했어요,
        // 둘째 줄 안내)을 둔다. 원과 첫 줄 안내는 위아래 같은 빈 공간 사이
        // 한가운데에 오고, 보조 내용은 높이 계산에 들지 않아 상태가 바뀌어도 원이
        // 오르내리지 않는다.
        if (!choosing && _phase != _Phase.manualInput && _phase != _Phase.heard)
          Expanded(
            flex: 3,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 보조 내용이 들어갈 높이를 알린다. 등록 화면은 내용 높이를
                // 미리 재어 모자라면 스크롤하므로, 좁거나 글자가 커도 이 영역이
                // 이만큼은 남아 버튼이 늘 눌린다.
                SizedBox(width: double.infinity, height: _extraHeight(context)),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: _micArea(_MicPart.extra),
                ),
              ],
            ),
          )
        else
          const Spacer(flex: 3),

        // 방법을 바꾸는 길은 안내 문구에서 멀리 떼어 화면 아래에 둔다. 문구
        // 바로 밑에 글자만 두면 안내의 일부인지 누르는 것인지 구분되지 않는다.
        if (typing || (_phase == _Phase.manualInput && _voiceUnavailable))
          const SizedBox.shrink()
        else if (_phase == _Phase.manualInput)
          Center(
            child: _SwitchMethodButton(
              icon: Icons.record_voice_over_outlined,
              label: _cameFromFailure ? '다시 녹음하기' : '말로 답할게요',
              onTap: _startVoice,
            ),
          )
        else if (!choosing)
          // 알아들은 뒤에는 다시 녹음하기를 글로 답할게요 옆에 같은 알약으로
          // 둔다. 5분에 닿아 멈췄으면 그 결과를 한 번에 버리지 않게 숨긴다.
          // 한 줄에 다 들어가지 않으면 두 줄로 넘긴다.
          //
          // 듣는 중과 옮기는 중에는 방법을 바꾸지 못하게 숨기되 자리는 남긴다.
          // 자리까지 빼면 화면 높이가 바뀌어 위의 마이크 원이 오르내린다.
          Visibility(
            visible:
                _phase != _Phase.listening && _phase != _Phase.transcribing,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (_phase == _Phase.heard && !_stoppedAtLimit)
                  _SwitchMethodButton(
                    icon: Icons.refresh,
                    label: '다시 녹음하기',
                    onTap: _retry,
                  ),
                _SwitchMethodButton(
                  icon: Icons.chat_bubble_outline,
                  label: '글로 답할게요',
                  onTap: _startText,
                ),
              ],
            ),
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

/// 답하는 방법 하나. 누르면 바탕이 진해지고 테두리가 검어지며 살짝 눌린 뒤
/// 다음 화면으로 넘어간다. 바로 넘어가면 무엇을 눌렀는지 보이지 않는다.
/// 움직임 줄이기가 켜져 있으면 바로 넘어간다.
class _MethodButton extends StatefulWidget {
  const _MethodButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_MethodButton> createState() => _MethodButtonState();
}

class _MethodButtonState extends State<_MethodButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..addStatusListener(_onPressed);

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _tap() {
    if (_press.isAnimating || _press.isCompleted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      widget.onTap();
      return;
    }
    _press.forward();
  }

  void _onPressed(AnimationStatus status) {
    if (status == AnimationStatus.completed) widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: AnimatedBuilder(
        animation: _press,
        builder: (context, child) {
          final t = Curves.easeOut.transform(_press.value);
          return Transform.scale(
            scale: 1 - 0.04 * t,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _tap,
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                  decoration: BoxDecoration(
                    color: Color.lerp(
                      AppColors.background,
                      HomeColors.bubble,
                      t,
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(
                      color: Color.lerp(
                        HomeColors.outline,
                        HomeColors.accent,
                        t,
                      )!,
                      width: 1 + t,
                    ),
                    boxShadow: AppShadows.low,
                  ),
                  child: child,
                ),
              ),
            ),
          );
        },
        child: SizedBox(
          // 주 사용자가 50~60대다. 고르는 자리를 넉넉하게 잡는다.
          height: 96,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, size: 44, color: HomeColors.accent),
              const SizedBox(height: AppSpacing.lg),
              Text(widget.label, style: AppTypography.bodyStrong),
            ],
          ),
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
    return Material(
      color: HomeColors.bubble,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          height: AppSizes.minTouch,
          // 두 알약(다시 녹음하기, 글로 답할게요)이 기준 화면 한 줄에 들어가는 여백.
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: HomeColors.bubbleLine),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: HomeColors.accent),
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
    );
  }
}

/// 마이크 화면에서 그릴 부분. [main] 은 원과 첫 줄 안내(알아들은 뒤에는 체크와
/// 결과 상자), [extra] 는 원 아래 빈 공간 맨 위에 두는 보조 내용이다.
enum _MicPart { main, extra }

class _MicArea extends StatelessWidget {
  const _MicArea({
    required this.part,
    required this.phase,
    required this.heardText,
    required this.onStart,
    required this.onFinish,
    required this.onResend,
    required this.stoppedAtLimit,
  });

  final _MicPart part;
  final _Phase phase;
  final String? heardText;
  final VoidCallback onStart;

  /// 녹음을 끝낸다. 녹음이 시작되기 전에는 없다.
  final VoidCallback? onFinish;

  /// 보내지 못한 녹음을 다시 보낸다.
  final VoidCallback onResend;

  /// 알아들은 녹음이 최대 길이에 닿아 멈췄다.
  final bool stoppedAtLimit;

  @override
  Widget build(BuildContext context) {
    final sendFailed = phase == _Phase.sendFailed;
    final failed = phase == _Phase.notHeardOnce || sendFailed;
    final heard = phase == _Phase.heard;
    final listening = phase == _Phase.listening;
    final transcribing = phase == _Phase.transcribing;

    // 녹음이 실제로 시작된 뒤다. 마이크를 누른 직후 권한을 묻는 동안에는
    // 아직 녹음하지 않으므로 녹음 중 표시를 하지 않는다.
    final recording = listening && onFinish != null;

    // 듣는 중에는 마이크를 다시 눌러도 녹음을 끝낸다. 옮기는 중에는 누를 수 없다.
    // 보내지 못했을 때도 막는다. 할 일을 재시도 하나로 두기 위해서다. 다시
    // 말하려면 글로 답할게요 → 말로 답할게요로 간다.
    final VoidCallback? onTap = transcribing || sendFailed
        ? null
        : listening
        ? onFinish
        : onStart;

    // 원과 첫 줄 안내가 한 묶음으로 위의 예시 상자와 아래 알약 사이 한가운데에
    // 온다. 둘째 줄이나 버튼 같은 보조 내용은 [_MicPart.extra] 로 따로 그린다.
    const statusStyle = AppTypography.body;

    if (heard) {
      // 체크와 결과 상자도 위아래 여백을 같게 두어 한가운데에 온다.
      return Column(
        children: [
          const SizedBox(height: AppSpacing.lg),
          const _PopIn(child: _HeardCheck()),
          const SizedBox(height: AppSpacing.xl),
          if (stoppedAtLimit) ...[
            const Text(
              "5분이 지나 녹음을 멈췄어요.\n이어서 적으려면 '글로 답할게요'를 눌러주세요.",
              style: AppTypography.sub,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          _HeardBox(text: heardText ?? ''),
          const SizedBox(height: AppSpacing.lg),
        ],
      );
    }

    // 묶음에 들어가는 첫 줄과 보조 자리에 넣는 나머지.
    final (Widget primary, Widget? secondary) = switch (phase) {
      _ when listening => (
        const Text('듣고 있어요', style: statusStyle),
        SecondaryButton(
          borderColor: HomeColors.outline,
          label: '다 말했어요',
          onPressed: onFinish,
          expand: false,
        ),
      ),
      _ when transcribing => (
        const Text('말씀을 글로 옮기고 있어요', style: statusStyle),
        null,
      ),
      // 인터넷이 끊긴 경우와 서버가 처리하지 못한 경우를 함께 덮는다.
      // 확인하지 않은 원인을 단정하지 않는다.
      _ when sendFailed => (
        Text(
          '연결이 원활하지 않아',
          style: statusStyle.copyWith(color: AppColors.danger),
        ),
        Column(
          children: [
            Text(
              '말씀을 글로 옮기지 못했어요.',
              style: statusStyle.copyWith(color: AppColors.danger),
            ),
            const SizedBox(height: AppSpacing.md),
            SecondaryButton(
              borderColor: HomeColors.outline,
              label: '재시도',
              icon: Icons.refresh,
              onPressed: onResend,
              expand: false,
            ),
          ],
        ),
      ),
      // 처음 안내가 실패 문구로 바뀌면 마이크를 다시 누르면 된다는 것을 알기
      // 어렵다. 버튼을 따로 두지 않고 할 일을 마이크 하나로 둔다.
      _ when failed => (
        Text(
          '목소리를 잘 듣지 못했어요.',
          style: statusStyle.copyWith(color: AppColors.danger),
        ),
        const Text('마이크를 눌러 다시 말씀해주세요.', style: AppTypography.sub),
      ),
      _ => (const Text('마이크를 누르고 말씀해주세요', style: statusStyle), null),
    };

    if (part == _MicPart.extra) {
      if (secondary == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: Center(child: secondary),
      );
    }

    return Column(
      children: [
        // 녹음하는 동안 원 둘레로 물결이 퍼진다. 원 밖에 그려 자리를 차지하지
        // 않으므로 원과 글자가 오르내리지 않는다.
        RecordingPulse(
          active: recording,
          child: SizedBox(
            width: _micSize,
            height: _micSize,
            // 아이콘만 있는 버튼이라 지금 누르면 하는 일을 이름으로 붙인다
            // (접근성 보고서 7쪽). 옮기는 중과 보내지 못했을 때는 누를 수
            // 없으므로 버튼으로 읽지 않고 아래 상태 문구에 맡긴다.
            child: ExcludeSemantics(
              excluding: onTap == null,
              child: Semantics(
                button: true,
                label: listening ? '음성 입력 종료' : '음성 입력 시작',
                child: InkWell(
                  onTap: onTap,
                  customBorder: const CircleBorder(),
                  // 대기, 듣는 중, 옮기는 중 모두 같은 크기와 두께의 원이다.
                  // 색만 바뀐다. 녹음하는 동안에는 E-2 녹음 화면처럼 초록 면에
                  // 흰 아이콘으로 채워, 움직임 줄이기가 켜져 있어도 대기와
                  // 구분된다.
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: recording ? HomeColors.accent : null,
                      border: Border.all(
                        color: failed
                            ? AppColors.danger
                            : listening
                            ? HomeColors.accent
                            : HomeColors.outline,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: SizedBox.square(
                        dimension: _iconSize,
                        child: transcribing
                            ? const CircularProgressIndicator(strokeWidth: 3)
                            : Icon(
                                Icons.mic,
                                size: _iconSize,
                                color: failed
                                    ? AppColors.danger
                                    : recording
                                    ? AppColors.background
                                    : HomeColors.accent,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        primary,
      ],
    );
  }

  /// 마이크 원의 지름과 그 안의 아이콘(또는 도는 표시) 크기. 모든 상태가 같다.
  static const _micSize = 120.0;
  static const _iconSize = 48.0;
}

/// 다 알아들었다는 체크.
class _HeardCheck extends StatelessWidget {
  const _HeardCheck();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: const BoxDecoration(
        color: HomeColors.accent,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.check, size: 32, color: AppColors.background),
    );
  }
}

/// 작게 시작해 통 튀어나오며 커진다. 움직임 줄이기가 켜져 있으면 바로 보인다.
class _PopIn extends StatelessWidget {
  const _PopIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: still ? 1 : 0, end: 1),
      duration: still ? Duration.zero : const Duration(milliseconds: 520),
      curve: Curves.elasticOut,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: child,
    );
  }
}

/// 알아들은 문장을 담는 상자.
///
/// 세부 정보 화면은 스크롤하지 않는다. 길게 말하면 문장이 화면을 넘치므로
/// 상자 높이를 [_lines] 줄로 정하고 상자 안에서 스크롤한다. 뒤에 더 있다는
/// 것을 알 수 있게 스크롤 막대를 늘 보인다. 대부분 4줄을 넘기므로 짧은
/// 답에도 같은 높이를 둬 화면 모양이 답마다 달라지지 않게 한다.
/// 위의 예시 문장 상자(회색)와 헷갈리지 않게 흰 바탕에 테두리를 둔다.
class _HeardBox extends StatefulWidget {
  const _HeardBox({required this.text});

  final String text;

  static const _lines = 4;

  @override
  State<_HeardBox> createState() => _HeardBoxState();
}

class _HeardBoxState extends State<_HeardBox> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const style = AppTypography.body;
    final lineHeight =
        MediaQuery.textScalerOf(context).scale(style.fontSize!) * style.height!;

    return Container(
      height: lineHeight * _HeardBox._lines + AppSpacing.md * 2,
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: HomeColors.bubbleLine),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Scrollbar(
        controller: _scroll,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: SizedBox(
            width: double.infinity,
            child: Text(widget.text, style: style),
          ),
        ),
      ),
    );
  }
}

class _ManualInput extends StatelessWidget {
  const _ManualInput({
    required this.label,
    required this.controller,
    super.key,
    required this.notice,
    required this.onChanged,
  });

  /// 화면 낭독기가 입력칸 이름으로 읽는 항목 이름. 예: `하시던 일`.
  final String label;

  final TextEditingController controller;

  /// 실패해서 넘어온 이유. 두 번 알아듣지 못했거나, 마이크를 쓸 수 없거나,
  /// 서버가 글로 옮기지 못한 경우다. 사용자가 처음부터 고른 경우는 `null` 이다.
  /// 스스로 고른 사람에게 실패를 알릴 이유가 없다.
  final String? notice;

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (notice case final notice?) ...[
          Text(
            notice,
            style: AppTypography.bodyStrong.copyWith(color: AppColors.danger),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        // 안내 문구는 글을 쓰면 사라진다. 쓰기 전후 모두 무엇을 적는 칸인지
        // 읽히게 항목 이름을 붙인다(접근성 보고서 13쪽).
        Semantics(
          label: label,
          child: TextField(
            // 안내가 빠져도 입력칸을 새로 만들지 않게 한다. 포커스를 잃으면
            // 키보드가 내려간다.
            key: const ValueKey('manualField'),
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
              // 흰 칸에 연한 세이지 테두리다. 흰 칸 위 안내 글자는 4.5:1.
              fillColor: AppColors.background,
              contentPadding: const EdgeInsets.all(AppSpacing.lg),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
                borderSide: const BorderSide(color: HomeColors.bubbleLine),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
                borderSide: const BorderSide(color: HomeColors.bubbleLine),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
                borderSide: const BorderSide(
                  color: HomeColors.accent,
                  width: 2,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
