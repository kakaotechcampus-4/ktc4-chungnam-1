import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/api_client.dart';
import '../../widgets/app_scaffold.dart';
import 'status_notice.dart';
import 'upload_retry_controller.dart';

/// 보내지 못한 면회 녹음 다시 보내기.
///
/// 피그마 설계는 없다. 앱을 다시 켠 뒤 홈의 `음성 다시 보내기` 배너가
/// `/visit/upload?session=<회차 ID>` 로 연다. 들어오자마자 보내고, 결과에 따라
/// 안내와 버튼만 바꾼다.
class UploadRetryScreen extends ConsumerWidget {
  const UploadRetryScreen({required this.sessionId, super.key});

  final String? sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = uploadRetryProvider(sessionId);
    final result = ref.watch(provider);
    void goHome() => context.go(AppRoutes.home);

    return Scaffold(
      appBar: const AppTopBar(),
      // 다시 보내기를 누르면 지난 실패 대신 보내는 중을 다시 보여준다.
      body: result.when(
        skipLoadingOnRefresh: false,
        loading: () => const StatusNotice(
          loading: true,
          title: '녹음을 보내고 있어요',
          body: '잠시만 기다려 주세요',
        ),
        error: (error, _) => StatusNotice(
          danger: true,
          title: '녹음을 보내지 못했어요.',
          body: error is ApiNetworkFailure
              ? '인터넷 연결을 확인한 뒤 다시 보내주세요.'
              : '잠시 후 다시 보내주세요.',
          primaryLabel: '다시 보내기',
          onPrimary: ref.read(provider.notifier).retry,
          onHome: goHome,
        ),
        data: (outcome) => switch (outcome) {
          UploadRetryOutcome.sent => StatusNotice(
            icon: Icons.check_circle_outline,
            title: '녹음을 보냈어요',
            body: '리포트가 만들어지면 홈에서 알려드릴게요',
            onHome: goHome,
          ),
          UploadRetryOutcome.notFound => StatusNotice(
            title: '이 휴대전화에서 녹음 파일을 찾을 수 없어요.',
            body: '녹음한 휴대전화에서 다시 보내주세요.',
            onHome: goHome,
          ),
          UploadRetryOutcome.alreadyClosed => StatusNotice(
            title: '이미 처리된 면회예요.',
            body: '결과는 홈에서 확인해 주세요.',
            onHome: goHome,
          ),
        },
      ),
    );
  }
}
