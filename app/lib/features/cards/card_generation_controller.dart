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
/// 홈의 `오늘의 대화카드 받기` 를 눌러야 생성을 시작한다(BE 리더 확인,
/// 2026-10-13). 그래서 화면에 들어올 때 상태가
/// - `none`, `failed` 면 4-1 로 생성을 요청하고,
/// - `running` 이면 [cardPollIntervalProvider] 마다 4-2 로 다시 묻고,
/// - `ready`, `inVisit` 이면 그 상태로 끝낸다.
///
/// 묻는 동안은 loading 이다. 화면을 떠나면 provider 가 사라지므로 더 묻지
/// 않는다. 서버의 생성은 그대로 이어지고, 다시 들어오면 처음부터 확인한다.
///
/// 기다리다 `failed` 가 되면 그대로 돌려준다. 4-2 는 실패 이유를 주지 않으므로
/// 화면은 공통 문구만 보여준다. 다시 받기는 [retry] 로 한다.
class CardGenerationController extends AsyncNotifier<CardGenerationStatus> {
  @override
  Future<CardGenerationStatus> build() async {
    final profileId = ref.watch(
      careProfilesProvider.select((p) => p.selected?.id),
    );
    if (profileId == null) throw StateError('고른 어르신이 없다');
    final api = ref.watch(cardApiProvider);

    var status = await api.status(profileId);
    var waited = false;

    if (status == CardGenerationStatus.none ||
        status == CardGenerationStatus.failed) {
      status = await api.requestGeneration(profileId);
      waited = true;
    }

    while (status == CardGenerationStatus.running) {
      waited = true;
      await Future<void>.delayed(ref.read(cardPollIntervalProvider));
      if (!ref.mounted) return status;
      status = await api.status(profileId);
    }

    // 새로 만든 묶음이다. 앞서 받아 둔 묶음이나 실패를 버리고 다시 받는다.
    if (waited &&
        (status == CardGenerationStatus.ready ||
            status == CardGenerationStatus.inVisit)) {
      ref.invalidate(currentCardSetProvider);
    }
    return status;
  }

  /// 실패 화면의 다시 받기. 상태를 처음부터 다시 확인한다.
  void retry() => ref.invalidateSelf();
}

/// 자동 재시도는 끈다. 다시 시도하면 4-1 을 또 보내므로 버튼으로만 한다.
final cardGenerationProvider =
    AsyncNotifierProvider.autoDispose<
      CardGenerationController,
      CardGenerationStatus
    >(CardGenerationController.new, retry: (_, _) => null);
