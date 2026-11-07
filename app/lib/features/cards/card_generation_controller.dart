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
/// 보호자가 홈 버튼을 눌렀을 때 모아서 만든다([prepare], PM 기준 사실 정정과
/// 다음 면회 카드 반영).
///
/// 상태는 `null`(아직 시작하지 않음)에서 시작하고, 묻는 동안은 loading 이다.
/// 화면에 묶이지 않아서 보호자가 다른 화면에 가 있어도 다 될 때까지 묻는다.
/// 어르신(서버의 `profileId`)마다 따로 두므로 다른 분으로 바꿔도 앞의 분은
/// 이어서 묻는다. 로그아웃과 탈퇴 때 `forgetCareProfiles` 가 모두 지운다.
///
/// 기다리다 `failed` 가 되면 그대로 돌려준다. 4-2 는 실패 이유를 주지 않으므로
/// 화면은 공통 문구만 보여준다. 다시 받기도 [start] 로 한다.
///
/// 홈의 `오늘의 대화카드 받기` 는 [prepare] 를 부른다. [start] 와 같되
/// `needsRefresh` 도 4-1 로 12장을 모두 새로 만든다. 홈 버튼이 `다음 대화
/// 준비` 를 맡는다(2026-11-01 #171 에서 PM 확인). 카드 화면은 [start] 로
/// 상태만 다시 확인한다.
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
  Future<void> start() => _begin((api, run) => _check(api, run));

  /// 홈 버튼. 쓸 묶음이 생길 때까지 확인하고, 받은 뒤 정보를 고친 묶음이면
  /// 새로 만든다. 이미 묻는 중이면 그대로 둔다.
  ///
  /// 기다렸으면(4-1 을 보냈거나 `running` 이었으면) `true` 를 돌려준다. 홈은
  /// 바로 준비된 경우만 카드 화면으로 가고, 기다린 경우는 그동안 다른 화면에
  /// 있을 수 있으므로 알림만 띄운다.
  Future<bool> prepare() async {
    await _begin((api, run) => _check(api, run, remake: true));
    return ref.mounted && _stage != CardMaking.checking;
  }

  /// 녹음을 시작해 이 묶음으로 회차를 만들었다(5-1). 서버는 이제 이 묶음을
  /// `inVisit` 으로 본다. 다시 묻지 않고 그 상태로 바꾼다.
  ///
  /// 뒤에 남은 카드 화면이 고르기와 `대화 시작하기` 를 감추고 이어서 하기를
  /// 보여주게 하려는 것이다. 같은 묶음으로 5-1 을 다시 보내면
  /// `CARD_SET_ALREADY_USED` 로 거절된다. 묻는 중이던 흐름은 끊는다.
  void visitStarted() {
    _run++;
    state = const AsyncData(CardGenerationStatus.inVisit);
  }

  /// [flow] 를 새 흐름으로 돌리고 끝나면 상태에 담는다.
  Future<void> _begin(
    Future<CardGenerationStatus> Function(CardApi api, int run) flow,
  ) async {
    if (state.isLoading) return;
    final run = ++_run;
    final api = ref.read(cardApiProvider);
    _setStage(CardMaking.checking);
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() => flow(api, run));
    if (!ref.mounted || run != _run) return;
    state = result;
  }

  Future<CardGenerationStatus> _check(
    CardApi api,
    int run, {
    bool remake = false,
  }) async {
    final status = await api.status(profileId);
    if (remake && _outdated(status)) {
      _mark(run, CardMaking.remaking);
      return _generate(api, run);
    }
    return switch (status) {
      CardGenerationStatus.none ||
      CardGenerationStatus.failed => _generate(api, run),
      CardGenerationStatus.running => _wait(api, run, status),
      _ => status,
    };
  }

  /// 받은 뒤 정보를 고친 묶음인지. 4-2 가 `ready` 여도 받아 둔 묶음(4-3)이
  /// `needsRefresh` 면 그렇다. 상태를 물은 뒤 묶음을 받기 전에 고친 경우다.
  /// 이때 새로 만들지 않으면 카드 화면이 홈으로 돌려보내고 홈은 다시 카드
  /// 화면으로 보내 오가기만 한다. 묶음을 아직 받지 않았으면 받으러 가지 않는다.
  bool _outdated(CardGenerationStatus status) {
    if (status == CardGenerationStatus.needsRefresh) return true;
    if (status != CardGenerationStatus.ready) return false;
    return ref.exists(currentCardSetProvider) &&
        (ref.read(currentCardSetProvider).value?.needsRefresh ?? false);
  }

  /// 4-1 로 만들어 달라고 한 뒤 다 될 때까지 기다린다.
  Future<CardGenerationStatus> _generate(CardApi api, int run) async {
    _mark(run, CardMaking.making);
    return _wait(api, run, await api.requestGeneration(profileId));
  }

  /// `running` 이 끝날 때까지 4-2 로 다시 묻는다.
  Future<CardGenerationStatus> _wait(
    CardApi api,
    int run,
    CardGenerationStatus status,
  ) async {
    while (status == CardGenerationStatus.running) {
      _mark(run, CardMaking.making);
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

  CardMaking get _stage => ref.read(cardMakingProvider(profileId));

  void _setStage(CardMaking stage) =>
      ref.read(cardMakingProvider(profileId).notifier).set(stage);

  /// 이번 흐름이 어디까지 왔는지 남긴다. `remaking` 은 `making` 으로 낮추지
  /// 않는다. 지웠거나 다른 흐름이 시작됐으면 남기지 않는다.
  void _mark(int run, CardMaking stage) {
    if (!ref.mounted || run != _run) return;
    if (_stage == CardMaking.remaking) return;
    _setStage(stage);
  }
}

/// 자동 재시도는 끈다. 다시 시도하면 4-1 을 또 보내므로 버튼으로만 한다.
final cardGenerationProvider =
    AsyncNotifierProvider.family<
      CardGenerationController,
      CardGenerationStatus?,
      String
    >(CardGenerationController.new, retry: (_, _) => null);

/// 생성 흐름이 어디까지 왔는지. 홈 버튼의 모양과 아래 안내에 쓴다.
enum CardMaking {
  /// 4-2 로 상태를 묻는 중이다. 이미 준비됐으면 곧 끝나므로 버튼 글자를
  /// 바꾸지 않는다. 바꾸면 깜빡인다.
  checking,

  /// 4-1 을 보냈거나 `running` 을 기다린다.
  making,

  /// 받은 뒤 정보를 고친 묶음을 새로 만든다.
  remaking,
}

/// 생성이 loading 일 때만 본다. 흐름을 새로 시작할 때 [CardMaking.checking]
/// 으로 돌린다.
final cardMakingProvider =
    NotifierProvider.family<CardMakingStage, CardMaking, String>(
      CardMakingStage.new,
    );

class CardMakingStage extends Notifier<CardMaking> {
  CardMakingStage(this.profileId);

  final String profileId;

  @override
  CardMaking build() => CardMaking.checking;

  // ignore: use_setters_to_change_properties
  void set(CardMaking stage) => state = stage;
}

/// 홈 버튼 아래에 남기는 실패 안내다. 알림창은 버튼을 가려서 글로 둔다. 다 만든
/// 것은 다른 화면에서도 보이게 알림창으로 알리므로 여기 두지 않는다.
enum CardNotice {
  /// 만들다 실패했다(4-2 `failed`).
  failed,

  /// 서버에 닿지 못했다.
  offline,

  /// 서버가 거절했거나 응답을 읽지 못했다.
  error,
}

/// 어르신마다 둔다. 다른 분으로 바꾸면 그분의 안내를 보여준다. 버튼을 다시
/// 누르면 지운다.
final cardNoticeProvider =
    NotifierProvider.family<CardNoticeState, CardNotice?, String>(
      CardNoticeState.new,
    );

class CardNoticeState extends Notifier<CardNotice?> {
  CardNoticeState(this.profileId);

  final String profileId;

  @override
  CardNotice? build() => null;

  // ignore: use_setters_to_change_properties
  void set(CardNotice? notice) => state = notice;
}
