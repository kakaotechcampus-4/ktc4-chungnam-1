import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/api_client.dart';
import '../../data/card_api.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/report_api.dart' show analysisFailureReason;
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/profile_avatar.dart';
import '../cards/card_generation_controller.dart';
import '../cards/photo_preparation_view.dart';
import '../profile/profile_dialogs.dart';
import '../profile_setup/setup_entry.dart';
import 'failed_report_sheet.dart';
import 'home_talk.dart';

/// 시작 화면.
///
/// 리포트 도착 알림은 별도 데이터가 아니라 이 화면의 상태다(피그마 `HOME`,
/// `HOME-1`). 알림을 눌러야 리포트로 들어갈 수 있고, 확인하면 사라진다.
///
/// 왼쪽 상단 알림 아이콘을 누르면 같은 상태를 다시 보여주는 `notice_screen.dart`
/// 가 뜬다. 상태를 새로 만들지 않고 `reportNoticeProvider` 를 그대로 본다.
///
/// 등록한 어르신이 없으면 이름 없이 묻고, 알림과 일대기를 누르면 등록부터
/// 안내한다. 대화 카드 받기는 안내창 없이 기본 정보 입력을 바로 연다. 가입
/// 직후에는 정보를 묻지 않고 홈부터 보여주기 때문이다.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(reportNoticeProvider);
    final info = ref.watch(reportNoticeInfoProvider);
    // 서버의 알림은 리포트와 날짜를 함께 안다. 목 데이터의 알림은 목 리포트를
    // 가리킨다.
    final mockReport = info?.fromServer ?? false
        ? null
        : ref.watch(visitReportProvider).value;
    final date = info?.visitDate ?? mockReport?.visitDate;
    final reportId = info?.reportId ?? mockReport?.reportId;
    final hasProfile = ref.watch(
      careProfilesProvider.select((p) => p.hasSelected),
    );
    final shown = ref.watch(profileProvider).value?.profile;
    final name = shown?.name;
    final profileKey = shown?.profileId;

    // 어르신이 있어야 쓰는 기능이다. 없으면 등록부터 안내한다.
    void needsProfile(VoidCallback open) =>
        hasProfile ? open() : showProfileRequiredDialog(context);

    return Scaffold(
      // 색은 홈에만 둔다(`HomeColors`).
      backgroundColor: HomeColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _HomeHills(),
          Column(
            children: [
              // 만드는 중에는 아직 볼 것이 없으므로 점을 찍지 않는다.
              _TopBar(
                hasNotice: notice == ReportNotice.ready,
                onNotice: () =>
                    needsProfile(() => context.push(AppRoutes.notifications)),
              ),
              // 버튼과 알림을 아래에 두고 남는 높이에 안내 문구와 말풍선을 담는다.
              // 남는 높이를 위 2, 아래 3 으로 나눈다. 높이가 모자라면 그림이
              // 줄어든다. 그림이 크기를 고집하면 화면이 낮을 때 알림 배너가
              // 붙는 순간 아래로 넘친다.
              //
              // 글자를 크게 키웠거나 남는 높이가 아주 낮으면 그림을 줄여도 안내
              // 문구와 말풍선만으로 넘친다. 그때는 그림 크기를 정해 두고 본문과
              // 버튼을 한 스크롤로 잇는다. 예전에는 위와 아래가 따로 스크롤되어
              // 360x640 에서 작은 창 둘로 갈렸다(2026-11-10 UX 점검 12). 글자를
              // 잘리게 두지 않는다(`app/DESIGN.md`).
              Expanded(
                child: _HomeBody(
                  bottom: Column(
                    children: [
                      _CardButton(hasProfile: hasProfile),
                      // 같은 자리에서 만드는 중이 도착으로 바뀐다. 로딩 화면을
                      // 없앤 뒤로 만드는 중을 알리는 자리가 여기뿐이다.
                      if (notice != null) ...[
                        const SizedBox(height: AppSpacing.lg),
                        switch (notice) {
                          // 리포트를 아직 읽는 중이면 날짜 없이 보여준다.
                          ReportNotice.generating => _GeneratingNotice(
                            date: date,
                          ),
                          ReportNotice.ready => _ReportNotice(
                            date: date,
                            // 여기서는 지우지 않는다. 변경 사항을 반영해야 사라진다.
                            onTap: () {
                              if (reportId == null) return;
                              context.push(AppRoutes.reportOf(reportId));
                            },
                          ),
                          ReportNotice.failed => _ResumeNotice(
                            date: date,
                            title: '리포트를 만들지 못했어요',
                            reason: analysisFailureReason(info?.failureCode),
                            hint: '눌러서 분석 다시 요청하기',
                            icon: Icons.error_outline,
                            // 녹음이 남았으면 공유도 고르게 한다.
                            onTap: () {
                              final analysisId = info?.analysisId;
                              if (reportId == null || analysisId == null) {
                                return;
                              }
                              openFailedReport(
                                context,
                                ref,
                                sessionId: reportId,
                                analysisId: analysisId,
                              );
                            },
                          ),
                          // 앱을 다시 켠 뒤 서버의 회차로 면회 흐름을 이어간다.
                          // 서버의 알림이라 회차 ID 가 있다.
                          ReportNotice.evaluationPending => _ResumeNotice(
                            date: date,
                            title: '평가 이어서 하기',
                            hint: '평가를 마치면 리포트를 만들어요',
                            onTap: () {
                              if (reportId == null) return;
                              context.push(AppRoutes.visitReviewOf(reportId));
                            },
                          ),
                          ReportNotice.audioPending => _ResumeNotice(
                            date: date,
                            title: '음성 다시 보내기',
                            hint: '녹음을 보내면 리포트를 만들어요',
                            onTap: () {
                              if (reportId == null) return;
                              context.push(AppRoutes.visitUploadOf(reportId));
                            },
                          ),
                          // 묻지 못한 것을 알릴 것이 없는 것처럼 두지 않는다.
                          ReportNotice.checkFailed => _ResumeNotice(
                            date: date,
                            icon: Icons.refresh,
                            title: '리포트 상태를 확인하지 못했어요',
                            hint: info?.rechecking ?? false
                                ? '다시 확인하고 있어요'
                                : '눌러서 다시 확인하기',
                            busy: info?.rechecking ?? false,
                            onTap: () =>
                                ref.read(reportNoticeProvider.notifier).retry(),
                          ),
                        },
                      ],
                    ],
                  ),
                  top: LayoutBuilder(
                    builder: (context, box) {
                      // 남는 높이를 받았으면 그림을 그 안에 줄여 담는다. 한
                      // 스크롤로 이을 때는 높이가 정해지지 않아 그림 크기를 둔다.
                      final roomy = box.hasBoundedHeight;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 어느 어르신의 대화 카드를 받는지 가장 큰 안내에서 알린다.
                          // 이름을 읽는 동안에는 이름 없이 묻는다.
                          Text(
                            name == null
                                ? '오늘은 무슨 주제로\n대화를 나눠볼까요?'
                                : '오늘은 $name 님과\n무슨 주제로 대화를 나눠볼까요?',
                            // '새록' 제목을 뺀 뒤로 이 문구가 화면의 제목이다.
                            style: AppTypography.sectionTitle,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppSpacing.xxl),
                          // 어르신을 바꾸면 인사말부터 다시 시작한다.
                          if (roomy)
                            Flexible(child: HomeTalk(key: ValueKey(profileKey)))
                          else
                            HomeTalk(
                              key: ValueKey(profileKey),
                              mascotSize: 140,
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 홈 본문. [bottom] (버튼과 알림)을 화면 아래에 두고 남는 높이에 [top] 을 담는다.
///
/// 글자가 1.3배 이하이고 남는 높이가 [_FitOrScroll.minTop] 이상이면 [top] 에
/// 그 높이를 주어 그림을 줄인다. 아니면 [top] 을 제 높이대로 두고 [bottom] 과
/// 함께 한 스크롤로 잇는다. 여백은 [ScreenBody] 와 같다.
class _HomeBody extends StatelessWidget {
  const _HomeBody({required this.top, required this.bottom});

  final Widget top;
  final Widget bottom;

  @override
  Widget build(BuildContext context) {
    final fit = MediaQuery.textScalerOf(context).scale(1) <= 1.3;
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, viewport) => SingleChildScrollView(
          child: _FitOrScroll(
            minHeight: viewport.maxHeight,
            fit: fit,
            top: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screen,
              ),
              child: top,
            ),
            bottom: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen,
                AppSpacing.lg,
                AppSpacing.screen,
                AppSpacing.xxl,
              ),
              child: bottom,
            ),
          ),
        ),
      ),
    );
  }
}

/// [_HomeBody] 의 배치. 아래 칸을 먼저 재고 남는 높이를 보고 위 칸의 높이를 정한다.
///
/// 남는 높이를 미리 알아야 해서 위젯을 엮어서는 만들 수 없다. 위 칸의 그림은
/// 남는 높이에 맞춰 줄어드는데(`LayoutBuilder`), 이런 위젯은 스크롤 안에서
/// 내용 높이를 미리 재는 `IntrinsicHeight` 를 쓸 수 없다. 면회 상태 안내의
/// `_NoticeLayout`(`status_notice.dart`)과 같은 방식이다.
class _FitOrScroll extends MultiChildRenderObjectWidget {
  _FitOrScroll({
    required this.minHeight,
    required this.fit,
    required Widget top,
    required Widget bottom,
  }) : super(children: [top, bottom]);

  /// 스크롤 창의 높이. 내용이 적어도 이만큼 채워 [bottom] 을 화면 아래에 둔다.
  final double minHeight;

  /// 위 칸을 남는 높이에 맞춰도 되는지. 글자를 크게 키웠으면 `false` 다.
  final bool fit;

  /// 위 칸에 줄 남는 높이의 최소값. 이보다 낮으면 그림을 줄여도 넘친다.
  static const minTop = 300.0;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFitOrScroll(minHeight, fit);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderFitOrScroll renderObject,
  ) {
    renderObject
      ..minHeight = minHeight
      ..fit = fit;
  }
}

class _FitOrScrollParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderFitOrScroll extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _FitOrScrollParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _FitOrScrollParentData> {
  _RenderFitOrScroll(this._minHeight, this._fit);

  /// 남는 높이를 위 2, 아래 3 으로 나눈다.
  static const _alignment = Alignment(0, -0.2);

  double _minHeight;
  set minHeight(double value) {
    if (value == _minHeight) return;
    _minHeight = value;
    markNeedsLayout();
  }

  bool _fit;
  set fit(bool value) {
    if (value == _fit) return;
    _fit = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FitOrScrollParentData) {
      child.parentData = _FitOrScrollParentData();
    }
  }

  @override
  void performLayout() {
    final top = firstChild!;
    final bottom = childAfter(top)!;
    final width = constraints.maxWidth;

    bottom.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
    final room = _minHeight - bottom.size.height;
    final fits = _fit && room >= _FitOrScroll.minTop;
    // 맞출 때는 남는 높이까지만, 이을 때는 높이를 정하지 않는다.
    top.layout(
      BoxConstraints(maxWidth: width, maxHeight: fits ? room : double.infinity),
      parentUsesSize: true,
    );

    final height = fits
        ? _minHeight
        : math.max(_minHeight, top.size.height + bottom.size.height);
    size = constraints.constrain(Size(width, height));

    final topArea = Size(size.width, size.height - bottom.size.height);
    (top.parentData! as _FitOrScrollParentData).offset = _alignment.alongOffset(
      (topArea - top.size) as Offset,
    );
    (bottom.parentData! as _FitOrScrollParentData).offset = Offset(
      0,
      size.height - bottom.size.height,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// 홈 바닥의 연한 세이지 언덕 두 겹. 장식이라 누를 수 없고 화면 낭독기도 읽지 않는다.
///
/// 버튼과 알림은 이 위에 올라간다. 언덕 위 보조 글자(`#5C5C5C`)는 앞 언덕에서
/// 5.0:1, 오류 글자(`#99392E`)는 5.3:1 이다.
class _HomeHills extends StatelessWidget {
  const _HomeHills();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: ExcludeSemantics(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            widthFactor: 1,
            heightFactor: 0.22,
            child: RepaintBoundary(
              child: CustomPaint(painter: _HillsPainter()),
            ),
          ),
        ),
      ),
    );
  }
}

class _HillsPainter extends CustomPainter {
  const _HillsPainter();

  /// 뒤 언덕. 앞 언덕보다 연하다.
  static const _back = HomeColors.hillBack;

  /// 앞 언덕.
  static const _front = HomeColors.hillFront;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 참고 시안의 윤곽을 따랐다. 꼭대기는 눌리지 않게 둥글게 부풀린다.
    // 뒤 언덕은 왼쪽 꼭대기에서 오른쪽으로 내려가고, 앞 언덕은 왼쪽이 낮고
    // 가운데가 완만하다가 오른쪽에서 둥글게 솟는다.
    final back = Path()
      ..moveTo(0, h * 0.05)
      ..cubicTo(w * 0.025, h * 0.012, w * 0.06, 0, w * 0.10, 0)
      ..cubicTo(w * 0.16, 0, w * 0.24, h * 0.03, w * 0.33, h * 0.09)
      ..cubicTo(w * 0.42, h * 0.15, w * 0.50, h * 0.21, w * 0.62, h * 0.23)
      ..cubicTo(w * 0.78, h * 0.25, w * 0.90, h * 0.22, w, h * 0.18)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(back, Paint()..color = _back);

    final front = Path()
      ..moveTo(0, h * 0.45)
      ..cubicTo(w * 0.05, h * 0.36, w * 0.13, h * 0.29, w * 0.24, h * 0.275)
      ..cubicTo(w * 0.34, h * 0.26, w * 0.42, h * 0.29, w * 0.50, h * 0.285)
      ..cubicTo(w * 0.57, h * 0.28, w * 0.63, h * 0.20, w * 0.70, h * 0.12)
      ..cubicTo(w * 0.77, h * 0.045, w * 0.84, 0, w * 0.91, 0)
      ..cubicTo(w * 0.95, 0, w * 0.98, h * 0.005, w, h * 0.012)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(front, Paint()..color = _front);
  }

  @override
  bool shouldRepaint(_HillsPainter oldDelegate) => false;
}

/// `오늘의 대화카드 받기`. 카드 화면으로 가기 전에 여기서 쓸 묶음을 준비한다.
///
/// 바로 쓸 묶음이 있으면 카드 화면으로 간다. 만들어야 하면(처음, 다 쓴 뒤,
/// 받은 뒤 정보를 고친 뒤) 이 버튼이 도는 표시로 바뀌고, 그동안 일대기나
/// 프로필을 볼 수 있다. 다 되면 알림창으로 알리고 카드 화면으로 데려가지
/// 않는다. 보호자가 다른 화면에 있을 수 있어서다. 알림창의 `카드 보기` 나
/// 이 버튼을 다시 누르면 들어간다. 실패는 버튼 아래 빨간 글로 남긴다.
/// 알림창은 버튼을 가린다. 앱을 다시 켜 이어 물은 작업도 같이 알린다.
///
/// 받은 뒤 정보를 고친 묶음이면 옛 카드를 보여주지 않고 12장을 모두 새로
/// 만든다(2026-11-01 #171 에서 PM 확인). 만드는 동안 버튼 아래 회색 상자에
/// 까닭을 둔다.
///
/// 버튼은 지금 고른 어르신의 상태를 보여준다. 다른 분으로 바꿔도 앞의 분은
/// 서버와 앱 모두에서 이어서 만든다.
///
/// 등록을 마친 분이 없으면 카드를 준비하지 않고 기본 정보 입력을 연다. 입력하다
/// 나간 분이 있으면 그 입력을 이어서 연다([openFirstProfileSetup]).
class _CardButton extends ConsumerStatefulWidget {
  const _CardButton({required this.hasProfile});

  final bool hasProfile;

  @override
  ConsumerState<_CardButton> createState() => _CardButtonState();
}

class _CardButtonState extends ConsumerState<_CardButton>
    with WidgetsBindingObserver {
  /// 상태를 묻는 동안 이만큼 지나도 답이 없으면 버튼을 확인 중으로 바꾼다.
  /// 그 전에 답이 오면 바꾸지 않는다. 이미 준비됐으면 곧 카드 화면으로 가므로
  /// 바꾸면 깜빡인다. 신호가 약하면 4-2 가 15초까지 걸려 그동안 눌리지 않은
  /// 것처럼 보였다(2026-11-10 UX 점검 6번).
  static const slowCheck = Duration(milliseconds: 400);

  String? _seenProfile;

  /// 상태를 묻기 시작하고 [slowCheck] 를 재는 시계.
  Timer? _checkTimer;

  /// 상태를 [slowCheck] 넘게 묻고 있다.
  bool _checkingLong = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 앱을 다시 켜거나 돌아오면 이미 접수한 작업을 이어받고, 그 결과를 누른
  /// 때와 같이 알린다. 실패하고도 시작 버튼으로 조용히 돌아가면, 앱을 닫아도
  /// 계속된다는 안내를 본 보호자는 준비된 줄 알았다(2026-11-10 UX 점검 11번).
  Future<void> _resume() async {
    final id = ref.read(serverProfileIdProvider).value;
    if (id == null || ref.read(cardApiProvider) is! PhotoPreparationApi) {
      return;
    }
    final name = ref.read(profileProvider).value?.profile.name;
    final waited = await ref.read(cardGenerationProvider(id).notifier).resume();
    if (!mounted) return;
    _announce(id, name, waited: waited, resumed: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_resume());
  }

  /// 상태를 묻는 동안 [slowCheck] 를 잰다. 묻기가 끝나면 시계를 멈춘다.
  void _followCheck(bool checking) {
    if (!checking) {
      _checkTimer?.cancel();
      _checkTimer = null;
      _checkingLong = false;
      return;
    }
    _checkTimer ??= Timer(slowCheck, () {
      if (mounted) setState(() => _checkingLong = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final profileId = ref.watch(serverProfileIdProvider).value;
    if (_seenProfile != profileId) {
      _seenProfile = profileId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_resume());
      });
    }
    final photos = profileId == null
        ? null
        : ref.watch(cardPhotoPreparationProvider(profileId));
    final generation = profileId == null
        ? null
        : ref.watch(cardGenerationProvider(profileId));
    final loading = generation?.isLoading ?? false;
    // 상태를 묻는 짧은 동안은 모양을 바꾸지 않는다. 이미 준비됐으면 곧 카드
    // 화면으로 가므로 바꾸면 깜빡인다. 그동안 다시 눌러도 생성 흐름이 무시한다.
    // [slowCheck] 를 넘기면 확인 중으로 바꾼다.
    final stage = loading
        ? ref.watch(cardMakingProvider(profileId!))
        : CardMaking.checking;
    final making = stage != CardMaking.checking;
    _followCheck(loading && !making);
    final checkingLong = _checkingLong;
    // 만드는 동안은 지난 결과를 보이지 않는다.
    final notice = profileId == null || loading
        ? null
        : ref.watch(cardNoticeProvider(profileId));
    final name = ref.watch(profileProvider).value?.profile.name;

    return Column(
      children: [
        if (!(photos?.needsChoice ?? false))
          PrimaryButton(
            label: photos != null && !photos.needsChoice
                ? '사진을 준비하고 있어요'
                : making
                ? '대화 카드를 만들고 있어요'
                : checkingLong
                ? '카드를 확인하고 있어요'
                : '오늘의 대화카드 받기',
            loading: making || checkingLong,
            color: HomeColors.accent,
            loadingColor: HomeColors.accentLoading,
            onPressed: () => widget.hasProfile
                ? _getCards(context, ref)
                : openFirstProfileSetup(context, ref),
          ),
        if (photos != null) ...[
          const SizedBox(height: AppSpacing.md),
          PhotoPreparationView(
            profileId: profileId!,
            recheck: _resume,
            resolve: _resolvePhotos,
          ),
        ] else if (stage == CardMaking.remaking) ...[
          const SizedBox(height: AppSpacing.md),
          const _RemakingNotice(),
        ] else if (notice != null) ...[
          const SizedBox(height: AppSpacing.md),
          _CardResult(notice: notice, name: name),
        ],
      ],
    );
  }

  Future<void> _getCards(BuildContext context, WidgetRef ref) async {
    // 기다리는 동안 볼 이야기를 말풍선에 꺼낸다.
    ref.read(homeTalkNudgeProvider.notifier).nudge();
    // 이미 읽은 값이 있으면 기다리지 않는다. 누르자마자 버튼이 돌게 한다.
    final profileId =
        ref.read(serverProfileIdProvider).value ??
        await ref.read(serverProfileIdProvider.future);
    if (profileId == null || !context.mounted) return;
    final name = ref.read(profileProvider).value?.profile.name;
    ref.read(cardNoticeProvider(profileId).notifier).set(null);

    final waited = await ref
        .read(cardGenerationProvider(profileId).notifier)
        .prepare();
    if (!context.mounted) return;
    _announce(profileId, name, waited: waited);
  }

  /// 사진 준비 화면의 선택(`준비된 설명으로 카드 만들기`, `사진 분석 다시 시도`
  /// 등)을 보내고, 기다려 만든 결과를 홈 버튼을 누른 때와 같이 알린다. 알리지
  /// 않으면 다 되거나 실패해도 홈 버튼이 시작 전 글자로 조용히 돌아갔다
  /// (2026-11-10 UX 점검 11번, 18번). 선택을 처리하지 못했거나 다시 고를 일이
  /// 생겨 사진 준비 화면이 남아 있으면 그 화면이 알린다.
  Future<void> _resolvePhotos(String action) async {
    final profileId = ref.read(serverProfileIdProvider).value;
    if (profileId == null) return;
    final name = ref.read(profileProvider).value?.profile.name;
    ref.read(cardNoticeProvider(profileId).notifier).set(null);

    final waited = await ref
        .read(cardGenerationProvider(profileId).notifier)
        .resolvePhotos(action);
    if (!mounted) return;
    if (ref.read(cardPhotoPreparationProvider(profileId)) != null) return;
    _announce(profileId, name, waited: waited);
  }

  /// 생성 흐름이 끝난 뒤 결과를 알린다.
  ///
  /// [resumed] 면 보호자가 누르지 않고 이어 물은 결과다(앱을 다시 켰거나 돌아옴).
  /// 그때는 카드 화면으로 데려가지 않고, 이미 있던 묶음을 확인만 했으면 알리지
  /// 않는다. 서버에 묻지 못한 것도 기다리던 작업을 놓쳤을 때만 알리고, 알릴 것이
  /// 없으면 앞의 안내를 지우지 않는다. 4-2 의 `failed` 는 기다리지 않았어도
  /// 알린다. 앱을 닫은 사이 실패했을 수 있다.
  void _announce(
    String profileId,
    String? name, {
    required bool waited,
    bool resumed = false,
  }) {
    final result = ref.read(cardGenerationProvider(profileId));
    // 다른 흐름이 이어서 묻는 중이거나, 로그아웃으로 지웠다.
    if (result.isLoading || !result.hasValue && !result.hasError) return;

    final status = result.value;
    final opens =
        !result.hasError &&
        (status == CardGenerationStatus.ready ||
            status == CardGenerationStatus.inVisit);
    final stillSelected = ref.read(serverProfileIdProvider).value == profileId;
    if (opens && !waited && !resumed && stillSelected) {
      unawaited(context.push(AppRoutes.cards));
      return;
    }

    // 다 만든 것은 알림창으로 알린다. 기다리는 동안 다른 화면에 있어도 보인다.
    if (opens) {
      if (waited || !resumed) {
        _showReady(profileId, name, canOpen: stillSelected);
      }
      return;
    }

    // 실패는 버튼 아래에 빨간 글로 남긴다. 알림창은 버튼을 가려 "다시 누르면"
    // 이라고 하는 동안 누를 버튼이 보이지 않았다.
    final notice = switch (result) {
      AsyncError(error: ApiNetworkFailure()) => CardNotice.offline,
      AsyncError() => CardNotice.error,
      _ when status == CardGenerationStatus.failed => CardNotice.failed,
      _ => null,
    };
    if (resumed && (notice == null || result.hasError && !waited)) return;
    ref.read(cardNoticeProvider(profileId).notifier).set(notice);
  }

  /// 카드가 준비됐다는 알림창. 알림창을 놓쳐도 홈 버튼 글자는 시작 전과 같아
  /// 할 일을 알기 어려워 `카드 보기` 를 붙인다(2026-11-10 UX 점검 11번).
  ///
  /// 버튼이 있어도 변경 사항 확인의 `되돌리기` 알림창처럼 저절로 닫는다
  /// (`changes_screen.dart`). 떠 있는 동안 홈 버튼을 가리므로 닫히지 않으면
  /// 홈 버튼을 누를 수 없다. 닫힌 뒤에는 홈 말풍선의 `대화 카드가 완성됐어요!`
  /// 가 남아 알린다. 기다리는 동안 다른 분으로 바꿨으면 그분의 카드 화면을 열게
  /// 되므로 버튼을 두지 않는다([canOpen]).
  void _showReady(String profileId, String? name, {required bool canOpen}) {
    final who = name == null ? '' : '$name 어르신의 ';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$who대화 카드가 준비됐어요.'),
          persist: false,
          action: canOpen
              ? SnackBarAction(
                  label: '카드 보기',
                  onPressed: () => _openCards(profileId),
                )
              : null,
        ),
      );
  }

  /// 알림창의 `카드 보기`. 그사이 다른 분으로 바꿨으면 열지 않는다.
  void _openCards(String profileId) {
    if (!mounted) return;
    if (ref.read(serverProfileIdProvider).value != profileId) return;
    unawaited(context.push(AppRoutes.cards));
  }
}

/// 받은 뒤 정보를 고친 묶음을 새로 만드는 까닭이다. 버튼 바로 아래 연한 회색
/// 상자에 둔다(#171 코멘트의 예시 화면).
class _RemakingNotice extends StatelessWidget {
  const _RemakingNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: HomeColors.background,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 22, color: AppColors.textSub),
          SizedBox(width: AppSpacing.md),
          // 낱말 가운데서 줄이 바뀌지 않게 끊을 곳을 정한다.
          Expanded(
            child: Text(
              '카드를 받은 뒤 어르신 정보가 바뀌어서\n'
              '대화 카드를 새로 만들고 있어요.',
              style: AppTypography.sub,
            ),
          ),
        ],
      ),
    );
  }
}

/// 버튼을 누른 결과다. 실패와 연결 끊김은 경고라 빨간 글로 쓴다.
class _CardResult extends StatelessWidget {
  const _CardResult({required this.notice, required this.name});

  final CardNotice notice;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final who = name == null ? '' : '$name 어르신의 ';
    final message = switch (notice) {
      // 4-2 는 실패 이유를 주지 않으므로 공통 문구만 둔다.
      CardNotice.failed => '$who대화 카드를 만들지 못했어요.\n다시 누르면 새로 만들어요.',
      CardNotice.offline => '서버에 연결하지 못했어요.\n인터넷 연결을 확인한 뒤 다시 눌러주세요.',
      CardNotice.error => '대화 카드를 불러오지 못했어요.\n잠시 후 다시 눌러주세요.',
    };
    return Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: AppTypography.sub.copyWith(color: AppColors.danger),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.hasNotice, required this.onNotice});

  final bool hasNotice;
  final VoidCallback onNotice;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      // 알약이 상태바에 붙어 보이지 않게 위를 띄운다. 양 끝 아이콘은 버튼 안쪽
      // 여백이 있어 좌우는 덜 띄운다. 오른쪽 아이콘이 없을 때의 알약 간격은
      // [_ProfileSwitcher] 가 채운다.
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.sm,
          0,
        ),
        child: ConstrainedBox(
          // 글자를 키워 알약이 높아지면 함께 늘어나도록 높이를 못 박지 않는다.
          constraints: const BoxConstraints(minHeight: AppSizes.topBar),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: onNotice,
                tooltip: '알림',
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.notifications_none, size: 32),
                    if (hasNotice)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: AppColors.danger,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: HomeColors.background,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const _ProfileSwitcher(),
            ],
          ),
        ),
      ),
    );
  }
}

/// 지금 보고 있는 어르신과 어르신을 바꾸는 버튼이다.
///
/// 사진만으로는 같은 성별의 어르신을 구분할 수 없어 이름을 함께 둔다. 다른
/// 어르신의 대화 카드를 받는 실수를 막으려는 자리다.
///
/// 원형 화살표는 목록 순서대로 다음 어르신으로 바로 바꾼다. 어르신이 한
/// 분이면 바꿀 대상이 없어 두지 않는다.
///
/// 등록한 어르신이 없으면 같은 자리에 `프로필 등록` 알약을 둔다. 누르면 함께
/// 하는 소중한 분 화면으로 간다.
class _ProfileSwitcher extends ConsumerWidget {
  const _ProfileSwitcher();

  static const _photo = 32.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasProfile = ref.watch(
      careProfilesProvider.select((p) => p.hasSelected),
    );
    final profile = ref.watch(profileProvider).value?.profile;
    final canSwitch = ref.watch(
      careProfilesProvider.select((p) => p.ready.length > 1),
    );
    if (!hasProfile) return const _RegisterPill();
    if (profile == null) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 누르면 어르신을 고르는 화면으로 간다.
        Material(
          color: HomeColors.bubble,
          shape: const StadiumBorder(
            side: BorderSide(color: HomeColors.bubbleLine),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push(AppRoutes.profileSwitch),
            child: Container(
              constraints: const BoxConstraints(minHeight: AppSizes.minTouch),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.xs,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ProfileAvatar(gender: profile.gender, size: _photo),
                  const SizedBox(width: AppSpacing.sm),
                  ConstrainedBox(
                    // 이름이 길어도 알림 아이콘을 밀어내지 않게 폭을 묶는다.
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      careDisplayName(profile.name, profile.relationship),
                      style: AppTypography.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // 엄지가 닿기 쉬운 오른쪽 끝에 둔다.
        if (canSwitch)
          IconButton(
            onPressed: () => _switchToNext(context, ref),
            tooltip: '다음 분 보기',
            // 알림 아이콘과 같은 크기다.
            icon: const Icon(Icons.sync, size: 32),
          )
        else
          // 아이콘이 없으면 알약이 벽에 붙지 않게 화면 여백만큼 띄운다.
          const SizedBox(width: AppSpacing.screen - AppSpacing.sm),
      ],
    );
  }

  /// 다음 어르신으로 바꾸고 누구로 바뀌었는지 알린다.
  ///
  /// 한 번 누르면 바로 바뀌므로, 잘못 눌러도 알아챌 수 있게 이름을 말해 준다.
  Future<void> _switchToNext(BuildContext context, WidgetRef ref) async {
    ref.read(careProfilesProvider.notifier).selectNext();
    final next = await ref.read(profileProvider.future);
    if (next == null || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('지금부터 ${next.profile.name}님과 함께해요')),
      );
  }
}

/// 등록한 어르신이 없을 때 알약 자리에 둔다. 어르신 알약과 같은 모양이다.
class _RegisterPill extends StatelessWidget {
  const _RegisterPill();

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 오른쪽 아이콘이 없을 때의 알약과 같은 간격이다.
      padding: const EdgeInsets.only(right: AppSpacing.screen - AppSpacing.sm),
      child: Material(
        color: HomeColors.bubble,
        shape: const StadiumBorder(
          side: BorderSide(color: HomeColors.bubbleLine),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(AppRoutes.profileSwitch),
          child: Container(
            constraints: const BoxConstraints(minHeight: AppSizes.minTouch),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 24, color: AppColors.ink),
                SizedBox(width: AppSpacing.xs),
                Text('프로필 등록', style: AppTypography.bodyStrong),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 배너 안의 글 묶음이다.
///
/// 날짜를 제목에 붙이면 어떤 문구로도 한 줄에 들어가지 않는다. 쓸 수 있는 폭이
/// 230 인데 가장 짧은 조합인 `8월 21일 리포트를 만들고 있어요` 가 323 이다.
/// 날짜를 위 줄로 빼고 제목을 짧게 둔다.
class _NoticeText extends StatelessWidget {
  const _NoticeText({
    required this.date,
    required this.title,
    required this.hint,
    this.reason,
  });

  final String? date;
  final String title;

  /// 제목 아래의 이유. 없으면 `null` 이다.
  final String? reason;

  /// 할 일이 없으면 `null` 이다.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (date != null) ...[
          Text(_friendlyDate(date!), style: AppTypography.caption),
          const SizedBox(height: AppSpacing.xs),
        ],
        Text(title, style: AppTypography.bodyStrong),
        if (reason != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(reason!, style: AppTypography.sub),
        ],
        if (hint != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(hint!, style: AppTypography.sub),
        ],
      ],
    );
  }
}

/// 리포트를 만드는 중임을 알리는 배너다.
///
/// 도착 배너와 같은 자리에 서고, 다 만들어지면 그 자리에서 도착 배너로 바뀐다.
/// 아직 들어갈 곳이 없으므로 누르지 않는다.
class _GeneratingNotice extends StatelessWidget {
  const _GeneratingNotice({required this.date});

  final String? date;

  static const _character = 64.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: HomeColors.background,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadows.high,
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/images/logo.webp',
            width: _character,
            // 옆 글자가 같은 것을 말한다.
            excludeFromSemantics: true,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _NoticeText(
              date: date,
              title: '리포트를 만들고 있어요',
              hint: '조금만 기다려 주세요',
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ],
      ),
    );
  }
}

/// `2026-08-21` 을 `8월 21일 만남` 으로 바꾼다.
String _friendlyDate(String isoDate) {
  final parts = isoDate.split('-');
  if (parts.length != 3) return isoDate;
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (month == null || day == null) return isoDate;
  return '$month월 $day일 만남';
}

/// 리포트가 도착했음을 알리는 배너다. 이것을 눌러야 리포트로 들어간다.
class _ReportNotice extends StatelessWidget {
  const _ReportNotice({required this.date, required this.onTap});

  final String? date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: HomeColors.background,
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow: AppShadows.high,
        ),
        child: Row(
          children: [
            const Icon(Icons.mail_outline, size: 32, color: AppColors.ink),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _NoticeText(
                date: date,
                title: '리포트가 도착했어요',
                hint: '눌러서 확인하기',
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSub),
          ],
        ),
      ),
    );
  }
}

/// 눌러서 이어갈 일이 있는 배너다. 앱을 떠난 사이 멈춘 면회 흐름
/// (`api-spec.md` 5-4 의 `evaluationPending`, `audioPending`)을 그 회차의 화면에서
/// 이어가고, 회차 상태를 묻지 못했으면 다시 묻는다.
class _ResumeNotice extends StatelessWidget {
  const _ResumeNotice({
    required this.date,
    required this.title,
    required this.hint,
    required this.onTap,
    this.icon = Icons.history,
    this.reason,
    this.busy = false,
  });

  final String? date;
  final String title;

  /// 제목 아래에 덧붙이는 이유. 분석 실패의 이유를 알 때만 있다.
  final String? reason;
  final String hint;
  final VoidCallback onTap;
  final IconData icon;

  /// 누른 일을 하는 중이다. 화살표 자리에 도는 표시를 두고 누름을 받지 않는다.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: HomeColors.background,
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow: AppShadows.high,
        ),
        child: Row(
          children: [
            Icon(icon, size: 32, color: AppColors.ink),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _NoticeText(
                date: date,
                title: title,
                reason: reason,
                hint: hint,
              ),
            ),
            if (busy)
              // 만드는 중 배너의 도는 표시와 같다. 글 줄이 바뀌지 않게 화살표
              // 아이콘(24)과 같은 폭을 차지한다.
              const SizedBox.square(
                dimension: 24,
                child: Center(
                  child: SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              )
            else
              const Icon(Icons.chevron_right, color: AppColors.textSub),
          ],
        ),
      ),
    );
  }
}
