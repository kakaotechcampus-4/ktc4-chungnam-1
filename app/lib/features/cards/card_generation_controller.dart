import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/card_api.dart';
import '../../data/providers.dart';

/// 카드가 만들어지기를 기다릴 때 상태를 다시 묻는 간격.
///
/// 실제 생성 시간을 재면 조정한다. 테스트는 짧게 바꾼다.
final cardPollIntervalProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 3),
);

/// 카드 화면에 들어와서 쓸 묶음이 생길 때까지의 흐름(API 4절).
///
/// 첫 카드는 온보딩 `마치기` 에서 생성을 요청한다(API 4-1, 2026-10-14 결정).
/// 서버가 카드 생성 요청이 있어야 등록을 마친 것(`completed`)으로 보기 때문이다.
/// 카드 화면은 그 요청이 실패했거나 지난 묶음을 다 쓴 경우를 위해, 들어올 때
/// 상태가
/// - `none`, `failed` 면 4-1 로 생성을 요청하고,
/// - `running` 이면 [cardPollIntervalProvider] 마다 4-2 로 다시 묻고,
/// - `ready`, `inVisit`, `needsRefresh` 면 그 상태로 끝낸다.
///
/// `needsRefresh` 는 들어올 때 다시 만들지 않는다. 고칠 때마다 만들지 않고
/// 보호자가 `다음 대화 준비하기` 를 눌렀을 때 모아서 만든다([refresh], PM 기준
/// 사실 정정과 다음 면회 카드 반영).
///
/// 묻는 동안은 loading 이다. 화면을 떠나면 provider 가 사라지므로 더 묻지
/// 않는다. 서버의 생성은 그대로 이어지고, 다시 들어오면 처음부터 확인한다.
///
/// 기다리다 `failed` 가 되면 그대로 돌려준다. 4-2 는 실패 이유를 주지 않으므로
/// 화면은 공통 문구만 보여준다. 다시 받기는 [retry] 로 한다.
class CardGenerationController extends AsyncNotifier<CardGenerationStatus> {
  @override
  Future<CardGenerationStatus> build() async {
    final profileId = await ref.watch(serverProfileIdProvider.future);
    if (profileId == null) throw StateError('고른 어르신이 없다');
    final api = ref.watch(cardApiProvider);

    final status = await api.status(profileId);
    return switch (status) {
      CardGenerationStatus.none ||
      CardGenerationStatus.failed => _generate(api, profileId),
      CardGenerationStatus.running => _wait(api, profileId, status),
      _ => status,
    };
  }

  /// 실패 화면의 다시 받기. 상태를 처음부터 다시 확인한다.
  void retry() => ref.invalidateSelf();

  /// `다음 대화 준비하기`. 받은 뒤 고친 묶음을 버리고 새로 만든다.
  ///
  /// 4-1 을 부르면 서버는 예전 묶음을 더는 주지 않는다. 만드는 동안은 loading
  /// 이고, 실패하면 `failed` 로 끝나 실패 화면의 다시 받기로 이어진다.
  Future<void> refresh() async {
    if (state.value != CardGenerationStatus.needsRefresh) return;
    final profileId = await ref.read(serverProfileIdProvider.future);
    if (profileId == null || !ref.mounted) return;
    final api = ref.read(cardApiProvider);

    state = const AsyncLoading();
    final next = await AsyncValue.guard(() => _generate(api, profileId));
    if (ref.mounted) state = next;
  }

  /// 4-1 로 만들어 달라고 한 뒤 다 될 때까지 기다린다.
  Future<CardGenerationStatus> _generate(CardApi api, String profileId) async =>
      _wait(api, profileId, await api.requestGeneration(profileId));

  /// `running` 이 끝날 때까지 4-2 로 다시 묻는다.
  Future<CardGenerationStatus> _wait(
    CardApi api,
    String profileId,
    CardGenerationStatus status,
  ) async {
    while (status == CardGenerationStatus.running) {
      await Future<void>.delayed(ref.read(cardPollIntervalProvider));
      if (!ref.mounted) return status;
      status = await api.status(profileId);
    }

    // 새로 만든 묶음이다. 앞서 받아 둔 묶음이나 실패를 버리고 다시 받는다.
    if (status == CardGenerationStatus.ready ||
        status == CardGenerationStatus.inVisit) {
      ref.invalidate(currentCardSetProvider);
    }
    return status;
  }
}

/// 자동 재시도는 끈다. 다시 시도하면 4-1 을 또 보내므로 버튼으로만 한다.
final cardGenerationProvider =
    AsyncNotifierProvider.autoDispose<
      CardGenerationController,
      CardGenerationStatus
    >(CardGenerationController.new, retry: (_, _) => null);
