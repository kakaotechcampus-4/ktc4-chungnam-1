import 'dart:async' show unawaited;
import 'dart:math' show pi;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/screen_awake.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_states.dart';
import '../profile/profile_dialogs.dart' show showChoiceDialog;
import 'stop_recording_dialog.dart';
import 'visit_cards_sheet.dart';
import 'visit_controller.dart';
import 'visit_recorder.dart';

/// E-1, E-2 녹음 안내와 녹음 중.
///
/// 둘은 별도 화면이 아니라 이 화면의 상태다.
///
/// 실제 녹음은 [VisitRecorder] 가 한다. 녹음 라이브러리와 음성 형식은 AI 영역이
/// 소유하므로(`app/CLAUDE.md`) 이 화면은 형식을 알지 못하고, 시작, 멈춤, 끝내기와
/// 실패 안내만 다룬다. STT 연결과 서버 업로드는 아직 없다.
///
/// 녹음하는 동안에는 [KeepScreenOn] 으로 화면이 저절로 꺼지지 않게 한다. 앱이
/// 백그라운드로 내려간 뒤의 녹음은 보장하지 않는다(`app/README.md`).
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

  /// 면회 사진을 올리지 못했다는 알림 띠. 화면을 떠나면 닫는다.
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _photoNotice;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(visitControllerProvider.notifier);
  }

  /// 사진 업로드 결과를 알린다. 녹음 화면이 뜨기 전에 끝나도 놓치지 않게
  /// 녹음 전 안내부터 지켜본다. 만남을 끝내면(참여자 수 확인) 닫는다.
  void _onPhotoUpload(
    (VisitPhotoUpload?, bool)? previous,
    (VisitPhotoUpload?, bool) next,
  ) {
    final (upload, stopped) = next;
    _closePhotoNotice();
    if (stopped) return;
    if (upload == VisitPhotoUpload.failed ||
        upload == VisitPhotoUpload.rejected ||
        upload == VisitPhotoUpload.missing) {
      _photoNotice = _showPhotoNotice(
        context,
        upload: upload!,
        onRetry: _controller.retryPhotoUpload,
      );
    }
  }

  void _closePhotoNotice() {
    _photoNotice?.close();
    _photoNotice = null;
  }

  @override
  void dispose() {
    _closePhotoNotice();
    // 끝내기를 누르지 않고 뒤로 나간 경우다. 열린 파일을 닫지 않으면 WAV 헤더가
    // 쓰이지 않아 소리는 들어 있는데 열 수 없는 파일이 남는다. 닫을 파일이
    // 없으면 상태가 알아서 지나간다. 파일은 바로 닫고, 트리 정리 중에 상태를
    // 바꾸지 않도록 상태 변경은 정리 뒤로 미루는 쪽을 부른다.
    unawaited(_controller.stopRecordingOnLeave());
    super.dispose();
  }

  /// 확인 창에서 나가기를 골랐다. 이때는 다시 묻지 않고 나간다.
  bool _leaving = false;

  /// 녹음을 시작했고 아직 만남을 끝내지 않았는지. 잠시 멈춘 때도 포함한다.
  ///
  /// 이때 뒤로 나가면 녹음이 멈추고, 지금은 같은 카드로 회차를 다시 만들 수
  /// 없어(서버 `CARD_SET_ALREADY_USED`) 한 번 더 묻는다.
  bool _inProgress(VisitState? state) =>
      state != null && state.started && state.participantCount == null;

  Future<void> _confirmLeave() async {
    final leave = await showChoiceDialog(
      context,
      title: '녹음을 그만둘까요?',
      detail: '지금 나가면 녹음이 멈춰요.\n만남을 마치려면 만남 끝내기를 눌러주세요.',
      primaryLabel: '그만두고 나가기',
      secondaryLabel: '계속 녹음하기',
    );
    if (!leave || !mounted) return;
    setState(() => _leaving = true);
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final visit = ref.watch(visitControllerProvider);
    ref.listen(
      visitControllerProvider.select(
        (v) => (v.value?.photoUpload, v.value?.participantCount != null),
      ),
      _onPhotoUpload,
    );

    // 녹음하는 동안만 화면을 켜 둔다. 잠시 멈춤, 끝내기 확인 창(멈춘 채로
    // 묻는다), 끝내기와 녹음 실패에서는 놓고, 화면을 떠나면 [KeepScreenOn] 이
    // 빠지면서 놓는다.
    return PopScope(
      canPop: _leaving || !_inProgress(visit.value),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: KeepScreenOn(
        enabled: visit.value?.recording ?? false,
        // 홈과 같은 세이지 색감이다(`HomeColors`).
        child: Scaffold(
          backgroundColor: HomeColors.background,
          appBar: const AppTopBar(backgroundColor: HomeColors.background),
          body: visit.when(
            loading: () => const LoadingView(),
            error: (error, _) => const ErrorStateView(
              message: '면회를 시작하지 못했어요.\n잠시 후 다시 시도해주세요.',
            ),
            // 한 번 시작하면 잠시 멈춰도 녹음 화면에 머문다.
            data: (state) =>
                state.started ? _Recording(state: state) : const _Intro(),
          ),
        ),
      ),
    );
  }
}

/// E-1 녹음 전 안내의 보관 문구.
///
/// 서버에 올린 녹음 사본은 STT 직후 지우지만, 기기의 녹음 파일은 다시 보내기를
/// 위해 남긴다(`app/README.md` 의 녹음 보관, PR #117 리뷰). 그래서 "분석이 끝나면
/// 바로 지워요" 처럼 모든 녹음을 지우는 것처럼 쓰지 않는다. 기기 파일을 언제
/// 지우는지는 약속하지 않는다. 탈퇴 때 삭제를 시도하지만 실패해도 넘어가기
/// 때문이다. 문구를 바꾸면 동의 화면의 보유 기간 문구와 함께 PM 확인을 받는다.
///
/// 첫 줄도 리포트만 말하지 않는다. 전사문으로 리포트와 함께 이야기 후보와 주제
/// 조정 제안을 만들고, 보호자가 확인한 제안은 `다음 대화 준비하기` 의 카드에
/// 반영된다.
///
/// 세 줄이 길어 두 줄로 줄였다(2026-11-06 디자인 리뉴얼, 2026-11-07 PM 확인).
/// 쓰는 곳, 서버 사본 삭제, 휴대폰에 남는 녹음 세 가지는 그대로 둔다.
const recordingRetentionNotice =
    '녹음은 리포트와 다음 대화 준비에만 써요.\n'
    '서버에서는 분석 후 지우고, 휴대폰에만 남겨요.';

/// E-1. 녹음 전 안내.
///
/// 회차마다 피보호자 동의를 확인하지 않는다. 녹음과 음성 처리 동의는 가입 때
/// 보호자의 필수 동의로 받는다(`docs/architecture/data-contracts.md`). 녹음 전
/// 동의 확인 체크는 팀 회의에서 빼기로 했다(2026-10-13 확인).
class _Intro extends ConsumerWidget {
  const _Intro();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(visitControllerProvider).value;
    final controller = ref.read(visitControllerProvider.notifier);
    final problem = state?.problem;

    return ScreenBody(
      scrollable: true,
      bottom: PrimaryButton(
        label: '네, 좋아요',
        color: HomeColors.accent,
        loadingColor: HomeColors.accentLoading,
        onPressed: controller.startRecording,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        // 제목은 앞 화면(만남 사진)의 제목과 같은 자리에 두고, 보관 안내와
        // 마이크 원이 그 아래로 이어진다. 남는 자리는 아래 버튼 쪽에 둔다.
        children: [
          const SizedBox(height: AppSpacing.visitTitleTop),
          const Text(
            '소중한 대화 내용을\n놓치지 않게 녹음할게요',
            style: AppTypography.screenTitle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg + AppSpacing.xs),
          const Text(
            recordingRetentionNotice,
            style: AppTypography.sub,
            textAlign: TextAlign.center,
          ),
          // 실기기에서 보고 마이크 원을 16 더 내렸다(2026-11-07).
          const SizedBox(
            height: AppSpacing.xxxl * 2 + AppSpacing.xxl + AppSpacing.lg,
          ),

          Center(
            child: Container(
              width: 140,
              height: 140,
              decoration: const BoxDecoration(
                color: HomeColors.bubble,
                shape: BoxShape.circle,
                // 연초록 원이 오프화이트 바탕에 묻히지 않게 테두리를 둔다.
                border: Border.fromBorderSide(
                  BorderSide(color: HomeColors.outline, width: 2),
                ),
              ),
              child: const Icon(Icons.mic, size: 56, color: HomeColors.accent),
            ),
          ),

          const Spacer(),

          if (problem != null) ...[
            const SizedBox(height: AppSpacing.lg),
            _ProblemNotice(problem: problem),
          ],

          const SizedBox(height: AppSpacing.lg + AppSpacing.xxl),
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
    VisitRecordingProblem.sessionFailed =>
      '면회를 시작하지 못했어요.\n인터넷 연결을 확인한 뒤 다시 눌러주세요.',
    VisitRecordingProblem.cardsOutdated =>
      '카드를 받은 뒤 어르신 정보가 바뀌었어요.\n홈에서 오늘의 대화카드 받기를 누르면 새로 만들어요.',
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
          const Icon(Icons.mic_off_outlined, size: 22, color: AppColors.danger),
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

/// 면회 사진을 올리지 못했으면 화면 아래 알림 띠로 알린다(API 5-2).
///
/// 녹음 화면은 아래 카드 자리 때문에 안내를 둘 높이가 남지 않아, 본문에 두면
/// 스크롤해야 보인다. 녹음은 그대로 이어지므로 녹음 실패보다 약하게 알린다.
/// 다시 올릴 수 있는 실패는 버튼을 달아 닫을 때까지 남기고, 받지 않는 거절은
/// 잠시 보여주고 사라진다. 사진 파일을 찾지 못했을 때도 다시 올릴 수 없다.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> _showPhotoNotice(
  BuildContext context, {
  required VisitPhotoUpload upload,
  required VoidCallback onRetry,
}) {
  final retryable = upload == VisitPhotoUpload.failed;
  return ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(switch (upload) {
        VisitPhotoUpload.failed => '사진을 올리지 못했어요.\n녹음은 그대로 이어져요.',
        VisitPhotoUpload.missing =>
          '찍은 사진을 찾지 못해 리포트에 사진 없이 담겨요.\n녹음은 그대로 이어져요.',
        _ => '사진을 올리지 못해 리포트에 사진 없이 담겨요.',
      }),
      action: retryable
          ? SnackBarAction(label: '사진 다시 올리기', onPressed: onRetry)
          : null,
      showCloseIcon: retryable,
    ),
  );
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
        final peekHeight = (constraints.maxHeight - _statusHeight - bottomInset)
            .clamp(_CardPeek.minHeight, _CardPeek.maxHeight + bottomInset);

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
                // 멈춤과 이어서 녹음을 누르면 바뀐 상태를 화면 낭독기가 바로
                // 읽는다. 1초마다 바뀌는 시간은 읽지 않게 여기에만 둔다.
                Semantics(
                  liveRegion: true,
                  child: Text(
                    state.recording ? '녹음 중이에요' : '잠시 멈췄어요',
                    // 아래 카드 자리를 내주려고 다른 화면보다 작게 쓴다.
                    style: AppTypography.screenTitle.copyWith(fontSize: 24),
                    textAlign: TextAlign.center,
                  ),
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
                          ? HomeColors.accent
                          : HomeColors.bubble,
                      shape: BoxShape.circle,
                      // 멈춘 연초록 원이 오프화이트 바탕에 묻히지 않게 테두리를 둔다.
                      border: state.recording
                          ? null
                          : Border.all(color: HomeColors.outline, width: 2),
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
          onOpen: (sheet) => showVisitCardsSheet(context, controller: sheet),
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

  /// 주어진 움직임으로 시트를 열고, 시트가 닫히면 끝나는 Future 를 돌려준다.
  final Future<void> Function(AnimationController sheet) onOpen;

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

class _CardPeekState extends State<_CardPeek>
    with SingleTickerProviderStateMixin {
  /// 이 속도보다 빠르게 위로 그으면 덜 올라왔어도 연다. 아래로 이만큼 빠르게
  /// 그으면 많이 올라왔어도 닫는다.
  static const _flingVelocity = 700.0;

  /// 손을 뗐을 때 시트가 이만큼(비율) 넘게 올라와 있으면 끝까지 연다.
  static const _openFraction = 0.3;

  /// 시트의 움직임. 끌어올리는 동안 손가락이 직접 값을 바꾼다.
  late final AnimationController _sheet;

  @override
  void initState() {
    super.initState();
    _sheet = BottomSheet.createAnimationController(this);
  }

  /// 손가락으로 끌어 연 시트를 따라 움직이는 중이다.
  bool _following = false;

  /// 끄는 동안 녹음 화면 위에 그리는 시트([VisitCardsSheetPreview]).
  final _preview = OverlayPortalController();

  /// 한 번의 끌어올리기에서 시트가 두 번 열리지 않게 막는다. 시트가 닫히면
  /// 푼다. 끌기 시작에서만 풀면 끌 수 없는 화면 낭독기 사용자는 한 번 닫은 뒤
  /// 다시 꺼낼 수 없다.
  bool _opening = false;

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  void _open() {
    if (_opening) return;
    _opening = true;
    widget.onOpen(_sheet).whenComplete(() {
      if (mounted) _opening = false;
    });
  }

  /// 시트 높이. 시트는 화면 높이의 [visitCardsSheetHeightFactor] 만큼이다.
  double get _sheetHeight =>
      MediaQuery.sizeOf(context).height * visitCardsSheetHeightFactor;

  /// 끌기 시작하면 녹음 화면 위에 그린 시트가 손가락을 따라오게 한다.
  void _startFollow() {
    if (_opening) return;
    _sheet.value = 0;
    _preview.show();
    _following = true;
  }

  void _follow(DragUpdateDetails details) {
    if (!_following) return;
    _sheet.value -= details.delta.dy / _sheetHeight;
  }

  /// 손을 떼면 충분히 올라왔거나 위로 그었을 때 끝까지 열고, 아니면 내린다.
  void _endFollow(double velocity) {
    if (!_following) return;
    _following = false;
    final open =
        velocity < -_flingVelocity ||
        (_sheet.value > _openFraction && velocity <= _flingVelocity);
    if (open) {
      // 그린 시트를 거두고 같은 높이에서 진짜 시트가 이어 올라간다.
      _preview.hide();
      _open();
    } else {
      _sheet.reverse().whenCompleteOrCancel(() {
        if (mounted && !_following) _preview.hide();
      });
    }
  }

  /// 끄는 동안 그리는 시트와 뒤 어둡게 하기. 진짜 시트와 같은 높이와 색이다.
  Widget _buildPreview(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _sheet,
        builder: (context, child) {
          final height = _sheetHeight;
          return Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: Color.lerp(
                    Colors.transparent,
                    Colors.black54,
                    _sheet.value,
                  )!,
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                height: height,
                bottom: -height * (1 - _sheet.value),
                child: child!,
              ),
            ],
          );
        },
        child: const VisitCardsSheetPreview(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final fanHeight = widget.height - bottomInset - _CardPeek._fanInset;

    // 화면 낭독기에서는 끌어올릴 수 없으므로 두 번 눌러 꺼내는 버튼 하나로 읽는다.
    // 부채 그림과 `위로 올려서` 안내는 읽지 않는다.
    return OverlayPortal(
      controller: _preview,
      overlayChildBuilder: _buildPreview,
      child: Semantics(
        container: true,
        button: true,
        label: '대화 카드 꺼내기',
        onTap: _open,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _open,
          // 끌어올리는 동안 시트가 손가락을 따라 올라온다.
          onVerticalDragStart: (_) => _startFollow(),
          onVerticalDragUpdate: _follow,
          onVerticalDragEnd: (details) =>
              _endFollow(details.primaryVelocity ?? 0),
          onVerticalDragCancel: () => _endFollow(0),
          child: SizedBox(
            height: widget.height,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: _CardPeek._fanBottom + bottomInset,
                  child: _CardFan(
                    key: const Key('cardPeekFan'),
                    height: fanHeight,
                  ),
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

  /// 카드 테두리. [HomeColors.outline] 과 [HomeColors.bubbleLine] 사이로 한
  /// 단계 연하게 둔다.
  static const _fanOutline = Color(0xFFB0BAA5);

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
      color: front ? AppColors.background : HomeColors.bubble,
      borderRadius: BorderRadius.circular(AppRadius.card * scale),
      // 오프화이트 바탕에서 흐려 보이지 않게 테두리와 그림자를 진하게 둔다.
      border: Border.all(color: _fanOutline, width: 1.5),
      boxShadow: AppShadows.card,
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
          color: HomeColors.background.withValues(alpha: 0.72),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: HomeColors.bubbleLine,
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
    // 둥근 버튼과 아래 이름을 화면 낭독기에서 버튼 하나로 읽는다. 이름이 버튼
    // 밖에 있으면 아이콘만 있는 이름 없는 버튼과 글자가 따로 읽힌다(접근성
    // 보고서 11쪽). 이름은 지금 누르면 하는 일이라 멈춘 뒤에는 `이어서 녹음` 이 된다.
    return Semantics(
      container: true,
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Column(
        children: [
          InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.background,
                border: Border.all(color: HomeColors.outline, width: 2),
              ),
              child: Icon(icon, size: 30, color: HomeColors.accent),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(label, style: AppTypography.sub),
        ],
      ),
    );
  }
}
