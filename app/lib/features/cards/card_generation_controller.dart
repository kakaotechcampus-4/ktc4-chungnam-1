import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/card_api.dart';
import '../../data/providers.dart';

/// 카드가 만들어지기를 기다릴 때 상태를 다시 묻는 간격.
///
/// 실제 생성 시간을 재면 조정한다. 테스트는 짧게 바꾼다.
final cardPollIntervalProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 3),
);

/// 한 어르신의 쓸 묶음이 생길 때까지의 흐름(API 4절).
///
/// 첫 카드는 온보딩 `마치기` 에서 생성을 요청한다(API 4-1, 2026-10-14 결정).
/// 서버가 카드 생성 요청이 있어야 등록을 마친 것(`completed`)으로 보기 때문이다.
/// 그 요청이 실패했거나 지난 묶음을 다 쓴 경우를 위해, [start] 하면 상태가
/// - `none`, `failed` 면 4-1 로 생성을 요청하고,
/// - `running` 이면 [cardPollIntervalProvider] 마다 4-2 로 다시 묻고,
/// - `ready`, `inVisit`, `needsRefresh` 면 그 상태로 끝낸다.
///
/// `needsRefresh` 는 [start] 에서 다시 만들지 않는다. 고칠 때마다 만들지 않고
/// 보호자가 `다음 대화 준비하기` 를 눌렀을 때 모아서 만든다([refresh], PM 기준
/// 사실 정정과 다음 면회 카드 반영).
///
/// 상태는 `null`(아직 시작하지 않음)에서 시작하고, 묻는 동안은 loading 이다.
/// 화면에 묶이지 않아서 보호자가 다른 화면에 가 있어도 다 될 때까지 묻는다.
/// 어르신(서버의 `profileId`)마다 따로 두므로 다른 분으로 바꿔도 앞의 분은
/// 이어서 묻는다. 로그아웃과 탈퇴 때 `forgetCareProfiles` 가 모두 지운다.
///
/// 기다리다 `failed` 가 되면 그대로 돌려준다. 4-2 는 실패 이유를 주지 않으므로
/// 화면은 공통 문구만 보여준다. 다시 받기도 [start] 로 한다.
class CardGenerationController extends AsyncNotifier<CardGenerationStatus?> {
  CardGenerationController(this.profileId);

  final String profileId;

  /// 지운 뒤 끝난 앞 흐름이 결과를 덮어쓰지 않게 흐름마다 번호를 매긴다.
  var _run = 0;

  @override
  CardGenerationStatus? build() {
    // 지우면 다시 읽기 전까지 build 가 돌지 않으므로 지우는 순간 끊는다.
    ref.onDispose(() => _run++);
    return null;
  }

  /// 상태를 처음부터 확인한다. 이미 묻는 중이면 그대로 둔다. 4-1 을 두 번
  /// 보내지 않기 위해서다.
  Future<void> start() => _begin(_check);

  /// `다음 대화 준비하기`. 받은 뒤 고친 묶음을 버리고 새로 만든다.
  ///
  /// 4-2 가 `ready` 였어도 이어서 받은 묶음(4-3)이 `needsRefresh` 면 다시
  /// 만든다. 상태를 물은 뒤 묶음을 받기 전에 정보를 고친 경우다. 화면도 두 값
  /// 중 하나라도 `needsRefresh` 면 이 버튼을 보여준다.
  ///
  /// 4-1 을 부르면 서버는 예전 묶음을 더는 주지 않는다. 만드는 동안은 loading
  /// 이고, 실패하면 `failed` 로 끝나 실패 화면의 다시 받기로 이어진다. 만드는
  /// 중에 다시 누르면 무시한다.
  Future<void> refresh() async {
    if (state.isLoading) return;
    // 묶음을 아직 받지 않았으면 여기서 받으러 가지 않는다.
    final setOutdated =
        ref.exists(currentCardSetProvider) &&
        (ref.read(currentCardSetProvider).value?.needsRefresh ?? false);
    final outdated =
        state.value == CardGenerationStatus.needsRefresh ||
        (state.value == CardGenerationStatus.ready && setOutdated);
    if (!outdated) return;
    await _begin(_generate);
  }

  /// [flow] 를 새 흐름으로 돌리고 끝나면 상태에 담는다.
  Future<void> _begin(
    Future<CardGenerationStatus> Function(CardApi api, int run) flow,
  ) async {
    if (state.isLoading) return;
    final run = ++_run;
    final api = ref.read(cardApiProvider);
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() => flow(api, run));
    if (!ref.mounted || run != _run) return;
    state = result;
  }

  Future<CardGenerationStatus> _check(CardApi api, int run) async {
    final status = await api.status(profileId);
    return switch (status) {
      CardGenerationStatus.none ||
      CardGenerationStatus.failed => _generate(api, run),
      CardGenerationStatus.running => _wait(api, run, status),
      _ => status,
    };
  }

  /// 4-1 로 만들어 달라고 한 뒤 다 될 때까지 기다린다.
  Future<CardGenerationStatus> _generate(CardApi api, int run) async =>
      _wait(api, run, await api.requestGeneration(profileId));

  /// `running` 이 끝날 때까지 4-2 로 다시 묻는다.
  Future<CardGenerationStatus> _wait(
    CardApi api,
    int run,
    CardGenerationStatus status,
  ) async {
    while (status == CardGenerationStatus.running) {
      await Future<void>.delayed(ref.read(cardPollIntervalProvider));
      if (!ref.mounted || run != _run) return status;
      status = await api.status(profileId);
    }

    // 새로 만든 묶음이다. 앞서 받아 둔 묶음이나 실패를 버리고 다시 받는다.
    if (ref.mounted &&
        run == _run &&
        (status == CardGenerationStatus.ready ||
            status == CardGenerationStatus.inVisit)) {
      ref.invalidate(currentCardSetProvider);
    }
    return status;
  }
}

/// 자동 재시도는 끈다. 다시 시도하면 4-1 을 또 보내므로 버튼으로만 한다.
final cardGenerationProvider =
    AsyncNotifierProvider.family<
      CardGenerationController,
      CardGenerationStatus?,
      String
    >(CardGenerationController.new, retry: (_, _) => null);
