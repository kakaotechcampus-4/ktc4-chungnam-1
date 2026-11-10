/// 보호자 모르게 면회 녹음이 멈췄을 때 크게 알리는 띠다.
///
/// 2026-11-10 PM 결정: 앱을 떠나거나 화면이 꺼져도 녹음은 이어 가고, 녹음이 어떤
/// 이유로든 멈추면 보호자에게 크게 알린다. 녹음 화면 맨 위와 대화 카드 시트 맨 위에
/// 같은 띠를 둔다. 시트가 녹음 화면의 5분의 4를 덮어 녹음 화면의 띠가 가려지기
/// 때문이다.
///
/// 색은 경고에만 쓰는 붉은색(`AppColors.danger`)을 면으로 깔고 흰 글자를 올린다
/// (7.1:1). 화면 낭독기는 띠가 나타나거나 문구가 바뀔 때 바로 읽는다.
library;

import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import 'visit_controller.dart';

/// 크게 알릴 녹음 멈춤의 종류다.
enum RecordingAlert {
  /// 다른 앱의 소리나 전화로 장치가 잠시 멈췄다. 이어서 녹음할 수 있다.
  interrupted,

  /// 장치가 녹음을 끝냈다. 같은 파일에 이어 쓸 수 없어 만남을 끝내 저장한다.
  deviceStopped,

  /// 멈춘 녹음을 이어 가지 못했다. 다시 눌러 볼 수 있다.
  resumeFailed,

  /// 만남을 끝냈는데 녹음 파일을 저장하지 못했다.
  saveFailed,
}

/// 면회 상태에서 크게 알릴 멈춤을 고른다. 없으면 `null` 이다.
///
/// 녹음을 시작한 뒤의 실패만 고른다. 시작 전 실패(권한 거부, 첫 시작 실패, 회차
/// 실패)는 녹음 안내 화면의 안내 상자가 맡는다.
RecordingAlert? recordingAlertOf(VisitState? state) {
  if (state == null || !state.started) return null;
  return switch (state.problem) {
    VisitRecordingProblem.interrupted => RecordingAlert.interrupted,
    VisitRecordingProblem.recorderStopped => RecordingAlert.deviceStopped,
    VisitRecordingProblem.startFailed => RecordingAlert.resumeFailed,
    VisitRecordingProblem.saveFailed => RecordingAlert.saveFailed,
    _ => null,
  };
}

/// 띠의 제목. 화면 낭독기가 먼저 읽는다.
String recordingAlertTitle(RecordingAlert alert) => switch (alert) {
  RecordingAlert.interrupted || RecordingAlert.deviceStopped => '녹음이 멈췄어요',
  RecordingAlert.resumeFailed => '녹음을 이어 가지 못했어요',
  RecordingAlert.saveFailed => '녹음 파일을 저장하지 못했어요',
};

/// 띠의 한 줄 이유와 할 일.
String recordingAlertDetail(RecordingAlert alert) => switch (alert) {
  RecordingAlert.interrupted => '전화나 다른 앱의 소리 때문에 멈췄을 수 있어요',
  RecordingAlert.deviceStopped => '이어서 녹음할 수 없어요. 만남 끝내기를 누르면 지금까지 녹음한 것을 저장해요',
  RecordingAlert.resumeFailed => '잠시 후 이어서 녹음을 다시 눌러주세요',
  RecordingAlert.saveFailed => '기억나는 내용은 소감에 적어주세요',
};

/// 녹음 멈춤을 크게 알리는 띠.
///
/// [actionLabel] 과 [onAction] 이 있으면 띠 안에 큰 버튼을 둔다(`이어서 녹음`,
/// `만남 끝내기`, `소감 쓰기`). 버튼은 글자가 커지면 함께 커진다.
class RecordingStoppedAlert extends StatelessWidget {
  const RecordingStoppedAlert({
    required this.alert,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final RecordingAlert alert;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final title = recordingAlertTitle(alert);
    final detail = recordingAlertDetail(alert);
    final label = actionLabel;

    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.danger,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const ExcludeSemantics(
                  child: Icon(
                    Icons.mic_off,
                    size: 32,
                    color: AppColors.background,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: AppTypography.sectionTitle.copyWith(
                        fontSize: 22,
                        color: AppColors.background,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              detail,
              style: AppTypography.body.copyWith(color: AppColors.background),
            ),
            if (label != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.md),
              ConstrainedBox(
                // 주 버튼과 같은 높이에서 시작하고, 글자가 커지면 함께 커진다.
                constraints: const BoxConstraints(minHeight: AppSizes.control),
                child: FilledButton(
                  key: const Key('recordingAlertAction'),
                  onPressed: onAction,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.background,
                    foregroundColor: AppColors.danger,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                      vertical: AppSpacing.md,
                    ),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(
                        Radius.circular(AppRadius.button),
                      ),
                    ),
                    textStyle: AppTypography.button,
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: AppTypography.button.copyWith(
                      color: AppColors.danger,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
