import 'dart:async' show unawaited;
import 'dart:math' show pi;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_states.dart';
import 'stop_recording_dialog.dart';
import 'visit_cards_sheet.dart';
import 'visit_controller.dart';
import 'visit_recorder.dart';

/// E-1, E-2 녹음 안내와 녹음 중.
///
/// 둘은 별도 화면이 아니라 이 화면의 상태다.
///
/// 실제 녹음은 [VisitRecorder] 가 한다. 녹음 라이브러리와 음성 형식은 AI 영역이
/// 소유하므로(`app/CLAUDE.md`) 이 화면은 형식을 알지 못하고, 시작·멈춤·끝내기와
/// 실패 안내만 다룬다. STT 연결과 서버 업로드는 아직 없다.
class RecordScreen extends ConsumerStatefulWidget {
  const RecordScreen({super.key});

  @override
  ConsumerState<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends ConsumerState<RecordScreen> {
  /// 화면이 사라진 뒤에도 파일을 닫아야 해서 미리 들고 있는다.
  ///
  /// **[initState] 에서 미리 받아 둔다.** `late final ... = ref.read(...)` 로
  /// 두면 실제로 읽는 시점이 [dispose] 안이 되는데, 그때는 `ref` 가
  /// `StateError` 를 던져 파일을 닫지 못한 채 화면만 사라진다.
  late final VisitController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(visitControllerProvider.notifier);
  }

  @override
  void dispose() {
    // 끝내기를 누르지 않고 뒤로 나간 경우다. 열린 파일을 닫지 않으면 WAV 헤더가
    // 쓰이지 않아 소리는 들어 있는데 열 수 없는 파일이 남는다. 닫을 파일이
    // 없으면 상태가 알아서 지나간다.
    unawaited(_controller.stopRecording());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visit = ref.watch(visitControllerProvider);

    return Scaffold(
      appBar: const AppTopBar(),
      body: visit.when(
        loading: () => const LoadingView(),
        error: (error, _) =>
            const ErrorStateView(message: '면회를 시작하지 못했어요.\n잠시 후 다시 시도해주세요.'),
        // 한 번 시작하면 잠시 멈춰도 녹음 화면에 머문다.
        data: (state) =>
            state.started ? _Recording(state: state) : const _Intro(),
      ),
    );
  }
}

/// E-1. 녹음 전 안내와 피보호자 동의 확인.
///
/// 계약의 `VisitSession.consent.careRecipientConfirmation` 과
/// `docs/legal/consent-draft.md` 의 필수 동의 항목에 해당한다. 가입 화면이 아니라
/// 면회를 시작하는 이 자리에서 받는다.
class _Intro extends ConsumerWidget {
  const _Intro();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(visitControllerProvider).value;
    final controller = ref.read(visitControllerProvider.notifier);
    final confirmed = state?.careRecipientConfirmed ?? false;
    final problem = state?.problem;

    return ScreenBody(
      scrollable: true,
      bottom: PrimaryButton(
        label: '네, 좋아요',
        onPressed: confirmed ? controller.startRecording : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),
          const Text(
            '소중한 대화 내용을\n놓치지 않게 녹음할게요',
            style: AppTypography.screenTitle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),
          const Text(
            '녹음은 리포트를 만드는 데만 쓰고\n분석이 끝나면 바로 지워요.',
            style: AppTypography.sub,
            textAlign: TextAlign.center,
          ),
          const Spacer(flex: 2),

          Center(
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.mic, size: 56, color: AppColors.ink),
            ),
          ),

          const Spacer(flex: 2),

          // 필수 확인이다. 체크해야 녹음을 시작할 수 있다.
          InkWell(
            onTap: () => controller.confirmCareRecipient(confirmed: !confirmed),
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: confirmed,
                    onChanged: (value) => controller.confirmCareRecipient(
                      confirmed: value ?? false,
                    ),
                    activeColor: AppColors.ink,
                    side: const BorderSide(color: AppColors.line, width: 2),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '[필수] ',
                            style: AppTypography.body.copyWith(
                              color: AppColors.danger,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const TextSpan(
                            text: '어르신께 녹음한다는 것을 알려드렸고 동의를 확인했어요.',
                            style: AppTypography.body,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (problem != null) ...[
            const SizedBox(height: AppSpacing.lg),
            _ProblemNotice(problem: problem),
          ],

          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

/// 끝내기를 누르면 묻고 나서 끝낸다.
///
/// 묻는 동안 녹음과 시간을 **잠시 멈춘다.** 창을 보는 사이의 침묵을 대화로
/// 남기지 않으려는 것이고, 이어서 녹음하면 같은 파일에 이어 쓴다. 취소하면
/// 멈추기 전으로 돌아간다.
///
/// 끝내기를 고르면 참여자 수를 함께 받아 파일을 닫는다. 파일을 닫은 뒤에
/// 넘어간다. 먼저 넘어가면 마지막 몇 초가 파일에 남지 않을 수 있다.
Future<void> _confirmStop(
  BuildContext context,
  VisitController controller,
  VisitState state,
) async {
  final wasRecording = state.recording;
  if (wasRecording) await controller.pauseRecording();
  if (!context.mounted) return;

  final participantCount = await showStopRecordingDialog(context);

  if (participantCount == null) {
    // 이어서 녹음. 멈추기 전에 녹음 중이었을 때만 되돌린다.
    if (wasRecording) await controller.startRecording();
    return;
  }

  await controller.stopRecording(participantCount: participantCount);
  if (!context.mounted) return;
  context.push(AppRoutes.visitReview);
}

/// 녹음이 되지 않았을 때 그 자리에서 알린다.
///
/// 성공 화면만 두지 않는다(`app/CLAUDE.md`). 권한을 대신 켜 줄 수는 없으므로
/// 무엇을 해야 하는지만 적는다.
class _ProblemNotice extends StatelessWidget {
  const _ProblemNotice({required this.problem});

  final VisitRecordingProblem problem;

  String get _message => switch (problem) {
    VisitRecordingProblem.permissionDenied =>
      '마이크 사용을 허용해야 녹음할 수 있어요.\n휴대전화 설정에서 새록의 마이크를 켜주세요.',
    VisitRecordingProblem.startFailed => '녹음을 시작하지 못했어요.\n잠시 후 다시 눌러주세요.',
    VisitRecordingProblem.saveFailed =>
      '녹음 파일을 저장하지 못했어요.\n기억나는 내용은 소감에 적어주세요.',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.dangerSurface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.mic_off_outlined,
            size: 22,
            color: AppColors.danger,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              _message,
              style: AppTypography.body.copyWith(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }
}

/// E-2. 녹음 중.
class _Recording extends ConsumerWidget {
  const _Recording({required this.state});

  final VisitState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(visitControllerProvider.notifier);

    // 카드를 꺼내는 자리가 화면 끝까지 닿아야 해서 ScreenBody 의 bottom 슬롯을
    // 쓰지 않고 그 아래에 직접 둔다.
    //
    // 카드 자리 높이를 못 박으면 기준 화면보다 짧은 기기에서 녹음 컨트롤이
    // 스크롤 밖으로 밀려 잘린다. 녹음 상태가 쓸 높이를 먼저 떼어 두고 남는
    // 만큼만 카드에 준다.
    return LayoutBuilder(
      builder: (context, constraints) {
        // ScreenBody 의 SafeArea 가 하단 안전영역을 한 번 더 쓰므로 카드 자리와
        // 따로 빼 둔다. 빼지 않으면 그만큼 컨트롤이 스크롤 밖으로 밀린다.
        final bottomInset = MediaQuery.paddingOf(context).bottom;
        final peekHeight =
            (constraints.maxHeight - _statusHeight - bottomInset).clamp(
              _CardPeek.minHeight,
              _CardPeek.maxHeight + bottomInset,
            );

        return _body(context, controller, peekHeight);
      },
    );
  }

  /// 녹음 상태가 잘리지 않는 높이. 여백과 글자, 원, 컨트롤의 합에 여유를 더했다.
  static const _statusHeight = 410.0;

  Widget _body(
    BuildContext context,
    VisitController controller,
    double peekHeight,
  ) {
    return Column(
      children: [
        Expanded(
          child: ScreenBody(
            scrollable: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.xxxl),
                Text(
                  state.recording ? '녹음 중이에요' : '잠시 멈췄어요',
                  // 아래 카드 자리를 내주려고 다른 화면보다 작게 쓴다.
                  style: AppTypography.screenTitle.copyWith(fontSize: 24),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  state.elapsedLabel,
                  style: AppTypography.screenTitle.copyWith(
                    fontSize: 30,
                    color: AppColors.textSub,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: AppSpacing.xxxl),

                Center(
                  child: Container(
                    width: 112,
                    height: 112,
                    decoration: BoxDecoration(
                      color: state.recording
                          ? AppColors.ink
                          : AppColors.surface,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      state.recording ? Icons.mic : Icons.pause,
                      size: 46,
                      color: state.recording
                          ? AppColors.background
                          : AppColors.textSub,
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.xxl),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ControlButton(
                      icon: state.recording ? Icons.pause : Icons.play_arrow,
                      label: state.recording ? '잠시 멈춤' : '이어서 녹음',
                      onTap: state.recording
                          ? controller.pauseRecording
                          : controller.startRecording,
                    ),
                    const SizedBox(width: AppSpacing.xxl),
                    _ControlButton(
                      icon: Icons.stop,
                      label: '만남 끝내기',
                      onTap: () => _confirmStop(context, controller, state),
                    ),
                  ],
                ),

                if (state.problem != null) ...[
                  const SizedBox(height: AppSpacing.xl),
                  _ProblemNotice(problem: state.problem!),
                ],

                const Spacer(),
              ],
            ),
          ),
        ),

        _CardPeek(
          height: peekHeight,
          onOpen: () => showVisitCardsSheet(context),
        ),
      ],
    );
  }
}

/// 녹음 화면 아래에 떠 있는 대화 카드다.
///
/// 예전에는 `대화 카드 살펴보기` 주 버튼이었다. 누르기 전에는 무엇이 나오는지
/// 알 수 없어서, 카드를 화면 아래에 내어 두고 끌어올려 꺼내는 자리로 바꿨다.
/// 끌어올리기와 누르기 둘 다 같은 시트를 연다.
class _CardPeek extends StatefulWidget {
  const _CardPeek({required this.height, required this.onOpen});

  /// 하단 안전영역까지 포함한 전체 높이.
  final double height;

  final VoidCallback onOpen;

  /// 기준 화면에서 쓰는 높이. 짧은 기기에서는 이보다 줄어든다.
  static const maxHeight = 380.0;

  /// 짧은 기기에서 녹음 컨트롤을 먼저 지키려고 여기까지 양보한다.
  static const minHeight = 200.0;

  /// 카드가 블러 띠에 걸치는 만큼 뺀 자리를 부채에 준다.
  static const _fanInset = 80.0;

  /// 부채 아랫변을 띄우는 높이.
  static const _fanBottom = 58.0;

  @override
  State<_CardPeek> createState() => _CardPeekState();
}

class _CardPeekState extends State<_CardPeek> {
  /// 이 속도보다 빠르게 위로 그으면 꺼낸 것으로 본다.
  static const _flingVelocity = -200.0;

  /// 천천히 끌어올리는 경우다. 이만큼 올라오면 속도와 상관없이 꺼낸다.
  static const _dragDistance = 48.0;

  double _dragged = 0;
  bool _opening = false;

  void _open() {
    if (_opening) return;
    _opening = true;
    widget.onOpen();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final fanHeight = widget.height - bottomInset - _CardPeek._fanInset;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _open,
      onVerticalDragStart: (_) {
        _dragged = 0;
        _opening = false;
      },
      onVerticalDragUpdate: (details) {
        _dragged += details.delta.dy;
        if (_dragged < -_dragDistance) _open();
      },
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) < _flingVelocity) _open();
      },
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: _CardPeek._fanBottom + bottomInset,
              child: _CardFan(key: const Key('cardPeekFan'), height: fanHeight),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _PullHint(bottomInset: bottomInset),
            ),
          ],
        ),
      ),
    );
  }
}

/// 부채처럼 편 카드 세 장이다.
///
/// **고른 카드가 몇 장이든 세 장으로 그린다.** 여기는 장수를 세는 자리가 아니라
/// 꺼낼 것이 있다는 것을 알리는 자리다. 실제 장수와 내용은 꺼낸 시트에서 본다.
/// 그래서 카드 안에 질문을 미리 적지 않는다. 꼬리 질문까지 보려면 어차피
/// 꺼내야 한다.
class _CardFan extends StatelessWidget {
  const _CardFan({required this.height, super.key});

  /// 부채가 쓸 수 있는 높이. 기기가 짧으면 [_designHeight] 보다 작게 들어온다.
  final double height;

  static const _spread = 26 * pi / 180;

  /// 기준 화면에서의 크기다. 좁은 기기에서는 이 비율 그대로 줄인다.
  static const _designHeight = 300.0;
  static const _width = 136.0;
  static const _frontHeight = 200.0;
  static const _backHeight = 188.0;

  /// 부채의 축을 카드 아래에 두려고 세 장을 함께 끌어올린 높이.
  static const _lift = 40.0;

  @override
  Widget build(BuildContext context) {
    final scale = (height / _designHeight).clamp(0.0, 1.0);

    return SizedBox(
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          _fanned(-_spread, scale),
          _fanned(_spread, scale),
          Transform.translate(
            offset: Offset(0, -_lift * scale),
            child: _card(
              height: _frontHeight * scale,
              scale: scale,
              front: true,
            ),
          ),
        ],
      ),
    );
  }

  /// 카드 아랫변 한가운데를 축으로 돌려 편다.
  Widget _fanned(double angle, double scale) => Transform.rotate(
    angle: angle,
    origin: Offset(0, _backHeight * scale / 2),
    child: Transform.translate(
      offset: Offset(0, -_lift * scale),
      child: _card(height: _backHeight * scale, scale: scale, front: false),
    ),
  );

  Widget _card({
    required double height,
    required double scale,
    required bool front,
  }) => Container(
    width: _width * scale,
    height: height,
    decoration: BoxDecoration(
      color: front ? AppColors.background : AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.card * scale),
      border: Border.all(color: AppColors.line),
      boxShadow: front ? AppShadows.low : null,
    ),
  );
}

/// 카드 아랫머리를 흐리고 그 위에 꺼내는 방법을 적는다.
class _PullHint extends StatelessWidget {
  const _PullHint({required this.bottomInset});

  final double bottomInset;

  static const _height = 112.0;
  static const _blur = 14.0;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: _blur, sigmaY: _blur),
        child: Container(
          height: _height + bottomInset,
          padding: EdgeInsets.only(bottom: AppSpacing.xl + bottomInset),
          color: AppColors.background.withValues(alpha: 0.72),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const Text('위로 올려서 대화 카드 꺼내기', style: AppTypography.bodyStrong),
            ],
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.line, width: 2),
            ),
            child: Icon(icon, size: 30, color: AppColors.ink),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(label, style: AppTypography.sub),
      ],
    );
  }
}
