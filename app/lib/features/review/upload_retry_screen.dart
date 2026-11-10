import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/api_client.dart';
import '../../design/tokens.dart';
import '../../widgets/app_scaffold.dart';
import '../visit/recording_share.dart';
import '../visit/stop_recording_dialog.dart';
import 'status_notice.dart';
import 'upload_retry_controller.dart';

/// 보내지 못한 면회 녹음 다시 보내기.
///
/// 피그마 설계는 없다. 앱을 다시 켠 뒤 홈의 `음성 다시 보내기` 배너가
/// `/visit/upload?session=<회차 ID>` 로 연다. 들어오자마자 보내고, 결과에 따라
/// 안내와 버튼만 바꾼다.
///
/// 보내거나 다시 요청하지 못했을 때 이 기기에 그 회차의 녹음 파일이 남아
/// 있으면 `녹음 파일 공유` 를 함께 둔다(2026-11-10 PM 결정).
class UploadRetryScreen extends ConsumerWidget {
  const UploadRetryScreen({
    required this.sessionId,
    this.analysisId,
    super.key,
  });

  final String? sessionId;
  final String? analysisId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = analysisId == null
        ? uploadRetryProvider(sessionId)
        : analysisRetryProvider((
            sessionId: sessionId,
            analysisId: analysisId!,
          ));
    final result = ref.watch(provider);
    void goHome() => context.go(AppRoutes.home);
    // 공유는 실패 안내에만 두지만 녹음은 들어오자마자 찾는다. 실패한 뒤에
    // 찾으면 공유가 늦게 나타나 이미 보이던 버튼이 자리를 옮긴다. 찾는 중이거나
    // 찾지 못하면 공유를 두지 않는다.
    final share = switch (sessionId) {
      final id? => switch (ref.watch(visitRecordingPathProvider(id)).value) {
        final path? => RecordingShareButton(sessionId: id, path: path),
        null => null,
      },
      null => null,
    };

    return Scaffold(
      backgroundColor: HomeColors.background,
      appBar: const AppTopBar(backgroundColor: HomeColors.background),
      // 다시 보내기를 누르면 지난 실패 대신 보내는 중을 다시 보여준다.
      body: result.when(
        skipLoadingOnRefresh: false,
        loading: () => StatusNotice(
          loading: true,
          title: analysisId == null ? '녹음을 보내고 있어요' : '분석을 다시 요청하고 있어요',
          body: '잠시만 기다려 주세요',
        ),
        error: (error, _) => StatusNotice(
          danger: true,
          title: analysisId == null ? '녹음을 보내지 못했어요.' : '분석을 요청하지 못했어요.',
          body: error is ApiNetworkFailure
              ? '인터넷 연결을 확인한 뒤 다시 보내주세요.'
              : '잠시 후 다시 보내주세요.',
          primaryLabel: '다시 시도하기',
          onPrimary: ref.read(provider.notifier).retry,
          extraAction: share,
          onHome: goHome,
        ),
        data: (outcome) => switch (outcome) {
          UploadRetryOutcome.reportRequested => StatusNotice(
            icon: Icons.check_circle_outline,
            title: '리포트를 다시 만들고 있어요',
            body: '저장된 전사를 사용합니다. 완료되면 홈에서 확인할 수 있어요.',
            onHome: goHome,
          ),
          UploadRetryOutcome.sent => StatusNotice(
            icon: Icons.check_circle_outline,
            title: '녹음을 보냈어요',
            body: '리포트가 만들어지면 홈에서 알려드릴게요',
            onHome: goHome,
          ),
          // 서버도 녹음을 받지 못한 회차(`audioPending`)다. 다시 보내라고
          // 반복하지 않는다(PR #117 리뷰).
          UploadRetryOutcome.notFound => StatusNotice(
            icon: Icons.mic_off_outlined,
            title: noRecordingTitle,
            body: noRecordingBody,
            onHome: goHome,
          ),
          UploadRetryOutcome.alreadyClosed => StatusNotice(
            title: '이미 처리된 면회예요.',
            body: '결과는 홈에서 확인해 주세요.',
            onHome: goHome,
          ),
          UploadRetryOutcome.participantCountRequired => StatusNotice(
            title: '녹음이 기기에 남아 있어요',
            body: '함께 대화한 사람 수를 확인하면 이 녹음으로 리포트를 만들 수 있어요.',
            primaryLabel: '참여자 수 확인하기',
            onPrimary: () async {
              final count = await showRecordingParticipantDialog(context);
              if (count == null || !context.mounted) return;
              await ref.read(provider.notifier).confirmParticipantCount(count);
            },
            onHome: goHome,
          ),
        },
      ),
    );
  }
}
