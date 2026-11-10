import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../visit/pending_uploads.dart';
import '../visit/recording_share.dart';

/// 실패 알림을 눌러 녹음을 찾거나 시트를 띄운 화면 묶음([NavigatorState]).
///
/// 그 사이 알림을 한 번 더 누르면 무시한다. 시트가 두 장 뜨거나 분석 다시
/// 요청하기 화면이 두 번 열리지 않게 한다. 시트를 연 채로 화면이 사라지면 시트의
/// 결과가 오지 않으므로, 앱 전체가 아니라 화면 묶음마다 둔다.
final _opening = Expando<bool>('실패 알림을 여는 중');

/// 홈 배너와 알림 화면에서 `리포트를 만들지 못했어요` 를 눌렀을 때.
///
/// 이 기기에 그 회차([sessionId])의 녹음 파일이 남아 있으면 아래에서 올라오는
/// 시트로 `분석 다시 요청하기` 와 `녹음 파일 공유` 를 고르게 한다(2026-11-10 PM
/// 결정). 녹음이 없으면 지금처럼 바로 분석 다시 요청하기 화면을 연다. 공유는
/// 리포트 화면과 같은 [shareVisitRecording] 이고, 시트를 닫은 뒤에 연다. 시트가
/// 떠 있는 동안 알림 띠를 띄우면 시트에 가려진다.
///
/// 녹음을 찾고 시트를 띄워 고른 일을 마칠 때까지는 다시 누르면 무시한다.
///
/// 공유에 대한 안내 문구는 두지 않는다(2026-11-09 PM 결정).
Future<void> openFailedReport(
  BuildContext context,
  WidgetRef ref, {
  required String sessionId,
  required String analysisId,
}) async {
  final navigator = Navigator.of(context);
  if (_opening[navigator] ?? false) return;
  _opening[navigator] = true;
  try {
    await _openFailedReport(
      context,
      ref,
      sessionId: sessionId,
      analysisId: analysisId,
    );
  } finally {
    _opening[navigator] = null;
  }
}

Future<void> _openFailedReport(
  BuildContext context,
  WidgetRef ref, {
  required String sessionId,
  required String analysisId,
}) async {
  final retry = AppRoutes.analysisRetryOf(sessionId, analysisId);
  // 누를 때마다 다시 찾는다. 그 사이 파일이 사라졌으면 시트 없이 다시 요청한다.
  final path = await findVisitRecordingPath(
    ref.read(pendingUploadsProvider),
    sessionId,
  );
  if (!context.mounted) return;
  if (path == null) {
    context.push(retry);
    return;
  }

  final action = await showModalBottomSheet<_FailedReportAction>(
    context: context,
    backgroundColor: AppColors.background,
    showDragHandle: true,
    isScrollControlled: true,
    barrierLabel: '닫기',
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
    ),
    builder: (context) => const _FailedReportSheet(),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case _FailedReportAction.retry:
      context.push(retry);
    case _FailedReportAction.share:
      await shareVisitRecording(context, ref, sessionId: sessionId, path: path);
  }
}

enum _FailedReportAction { retry, share }

class _FailedReportSheet extends StatefulWidget {
  const _FailedReportSheet();

  @override
  State<_FailedReportSheet> createState() => _FailedReportSheetState();
}

class _FailedReportSheetState extends State<_FailedReportSheet> {
  /// 시트가 올라오는 동안과 그 직후에는 누름을 받지 않는다. 배너를 두 번
  /// 누르면 두 번째 손가락이 막 올라온 시트의 버튼에 닿는다. 412dp 화면에서
  /// 홈 배너 가운데가 `녹음 파일 공유` 자리와 겹친다.
  bool _ready = false;
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_timer != null) return;
    // 올라오는 시간에 두 번 누르기 사이의 가장 긴 간격을 더한 만큼 기다린다.
    final opening = ModalRoute.of(context)?.transitionDuration ?? Duration.zero;
    _timer = Timer(opening + kDoubleTapTimeout, () {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen,
          0,
          AppSpacing.screen,
          AppSpacing.section,
        ),
        child: AbsorbPointer(
          absorbing: !_ready,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 홈 배너와 같은 문구다. 새로 짓지 않는다.
              Semantics(
                header: true,
                child: Text('리포트를 만들지 못했어요', style: AppTypography.sectionTitle),
              ),
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                color: HomeColors.accent,
                loadingColor: HomeColors.accentLoading,
                label: '분석 다시 요청하기',
                onPressed: () =>
                    Navigator.of(context).pop(_FailedReportAction.retry),
              ),
              const SizedBox(height: AppSpacing.md),
              // 리포트 화면의 [RecordingShareButton] 과 같은 모양과 문구다.
              SecondaryButton(
                borderColor: HomeColors.outline,
                icon: Icons.share_outlined,
                label: '녹음 파일 공유',
                onPressed: () =>
                    Navigator.of(context).pop(_FailedReportAction.share),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
