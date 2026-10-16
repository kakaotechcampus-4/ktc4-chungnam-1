import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import 'app_scaffold.dart';
import 'app_states.dart';

/// 서버에서 어르신 목록을 불러오는 동안과 실패했을 때 보여준다.
///
/// 이때는 목록이 비어 있어도 등록한 분이 없다는 뜻이 아니다. 등록부터 안내하면
/// 이미 등록한 보호자가 다시 등록하게 된다. 불러오기가 끝나면 [child] 를 그대로
/// 보여준다.
class CareProfilesLoading extends ConsumerWidget {
  const CareProfilesLoading({
    required this.child,
    this.withTopBar = false,
    super.key,
  });

  final Widget child;

  /// 뒤로 갈 수 있는 화면이면 위쪽 막대를 함께 둔다.
  final bool withTopBar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final load = ref.watch(careProfilesProvider.select((p) => p.load));
    final Widget body = switch (load) {
      CareProfilesLoad.loading => const LoadingView(
        message: '어르신 정보를 불러오고 있어요',
      ),
      CareProfilesLoad.failed => ErrorStateView(
        message: '어르신 정보를 불러오지 못했어요.\n인터넷 연결을 확인하고 다시 시도해주세요.',
        onRetry: () => ref.read(careProfilesProvider.notifier).reload(),
      ),
      _ => child,
    };
    if (identical(body, child)) return child;
    return Scaffold(appBar: withTopBar ? const AppTopBar() : null, body: body);
  }
}
