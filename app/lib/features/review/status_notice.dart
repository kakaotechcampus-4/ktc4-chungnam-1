import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';

/// 면회 기록을 보내거나 찾는 화면의 안내 한 장.
///
/// 음성 다시 보내기와 평가 이어서 하기가 같은 자리에 안내를 두도록 함께 쓴다.
///
/// 보내는 중과 결과가 같은 자리에 보이게, 안내는 버튼과 상관없이 화면의 같은
/// 높이에 두고 버튼은 아래에 따로 붙인다. 버튼 수가 달라도 안내가 움직이지
/// 않는다. 홈으로 버튼은 늘 두고, 다시 할 일이 있으면 그 버튼을 위에 둔다.
/// 다시 할 일과 홈으로 사이에 버튼 하나([extraAction])를 더 둘 수 있다.
///
/// 작은 화면에서 글자를 키워 안내와 버튼이 겹치게 되면 안내를 버튼 위로
/// 올리고, 그래도 모자라면 안내 바로 아래에 버튼을 이어 화면을 내려 보게 한다.
class StatusNotice extends StatelessWidget {
  const StatusNotice({
    required this.title,
    required this.body,
    this.onHome,
    this.icon,
    this.loading = false,
    this.danger = false,
    this.primaryLabel,
    this.onPrimary,
    this.extraAction,
    super.key,
  });

  final String title;
  final String body;

  /// 보내는 중에는 버튼을 두지 않는다.
  final VoidCallback? onHome;
  final IconData? icon;

  /// 아이콘 자리에 로딩 표시를 둔다.
  final bool loading;

  /// 실패라 붉은 안내로 보여준다.
  final bool danger;

  final String? primaryLabel;
  final VoidCallback? onPrimary;

  /// 다시 할 일([primaryLabel])과 홈으로 사이에 더 둘 버튼. 다시 할 일이 있을
  /// 때만 둔다. 분석을 다시 요청하지 못했을 때의 `녹음 파일 공유` 가 쓴다.
  final Widget? extraAction;

  /// 안내를 둘 높이. 가운데보다 조금 위다.
  static const _alignment = Alignment(0, -0.25);

  /// 아이콘과 로딩 표시가 같은 크기의 자리를 차지하게 한다.
  static const _markSize = 56.0;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.ink;
    final retry = primaryLabel != null && onPrimary != null;

    final notice = Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: _markSize,
            child: loading
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(strokeWidth: 3),
                  )
                : Icon(
                    icon ?? (danger ? Icons.error_outline : Icons.info_outline),
                    size: _markSize,
                    color: color,
                  ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            title,
            style: AppTypography.sectionTitle.copyWith(color: color),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            body,
            style: AppTypography.body.copyWith(color: AppColors.textSub),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );

    final actions = onHome == null
        ? null
        : Padding(
            // 위 여백은 안내와 띄울 가장 작은 간격이다.
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen,
              AppSpacing.xl,
              AppSpacing.screen,
              AppSpacing.xxl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (retry) ...[
                  PrimaryButton(
                    color: HomeColors.accent,
                    loadingColor: HomeColors.accentLoading,
                    label: primaryLabel!,
                    onPressed: onPrimary,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (extraAction case final extra?) ...[
                    extra,
                    const SizedBox(height: AppSpacing.md),
                  ],
                  SecondaryButton(
                    borderColor: HomeColors.outline,
                    label: '홈으로',
                    onPressed: onHome,
                  ),
                ] else
                  PrimaryButton(
                    color: HomeColors.accent,
                    loadingColor: HomeColors.accentLoading,
                    label: '홈으로',
                    onPressed: onHome,
                  ),
              ],
            ),
          );

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: _NoticeLayout(
            minHeight: constraints.maxHeight,
            notice: notice,
            actions: actions,
          ),
        ),
      ),
    );
  }
}

/// [StatusNotice] 의 안내와 버튼을 놓는다.
///
/// 안내는 [minHeight] 높이 안에서 [StatusNotice._alignment] 자리에, 버튼은
/// 바닥에 둔다. 둘이 겹치면 안내를 버튼 바로 위로 올리되 위 끝에서
/// [AppSpacing.xl] 보다 가까이 올리지 않는다. 그래도 모자라면 안내 바로 아래에
/// 버튼을 이어 높이를 늘리고, 늘어난 만큼은 바깥 스크롤로 내려 본다.
class _NoticeLayout extends MultiChildRenderObjectWidget {
  _NoticeLayout({
    required this.minHeight,
    required Widget notice,
    Widget? actions,
  }) : super(children: [notice, ?actions]);

  final double minHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderNoticeLayout(minHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderNoticeLayout renderObject,
  ) {
    renderObject.minHeight = minHeight;
  }
}

class _NoticeLayoutParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderNoticeLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _NoticeLayoutParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _NoticeLayoutParentData> {
  _RenderNoticeLayout(this._minHeight);

  double _minHeight;
  set minHeight(double value) {
    if (value == _minHeight) return;
    _minHeight = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _NoticeLayoutParentData) {
      child.parentData = _NoticeLayoutParentData();
    }
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final notice = firstChild!;
    final actions = childAfter(notice);
    notice.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
    actions?.layout(
      BoxConstraints.tightFor(width: width),
      parentUsesSize: true,
    );

    final noticeHeight = notice.size.height;
    final actionsHeight = actions?.size.height ?? 0;
    final preferredTop =
        (_minHeight - noticeHeight) * (1 + StatusNotice._alignment.y) / 2;
    final top = math.max(
      AppSpacing.xl,
      math.min(preferredTop, _minHeight - actionsHeight - noticeHeight),
    );
    size = constraints.constrain(
      Size(width, math.max(_minHeight, top + noticeHeight + actionsHeight)),
    );

    (notice.parentData! as BoxParentData).offset = Offset(
      (width - notice.size.width) / 2,
      top,
    );
    if (actions != null) {
      (actions.parentData! as BoxParentData).offset = Offset(
        0,
        size.height - actionsHeight,
      );
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// 기기에도 서버에도 녹음이 없는 회차의 안내. 소감 화면과 음성 다시 보내기가
/// 함께 쓴다. 면회 기록과 소감은 지우지 않는다.
const noRecordingTitle = '녹음이 없어 이 면회의 리포트는 만들 수 없어요.';
const noRecordingBody = '면회 기록과 남겨주신 소감은 그대로 남아 있어요.';
