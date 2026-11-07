// 한 어르신의 쓸 묶음이 생길 때까지의 흐름을 확인한다.
//
// `lib/features/cards/card_generation_controller.dart`. 서버 대신
// `FakeCardApi` 를 쓰고 값은 모두 합성이다.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/api_client.dart';
import 'package:saerok/data/card_api.dart';
import 'package:saerok/data/mock_repository.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/features/cards/card_generation_controller.dart';

import 'fake_card_api.dart';
import 'sample_profile.dart';

const _none = CardGenerationStatus.none;
const _running = CardGenerationStatus.running;
const _ready = CardGenerationStatus.ready;
const _inVisit = CardGenerationStatus.inVisit;
const _failed = CardGenerationStatus.failed;
const _needsRefresh = CardGenerationStatus.needsRefresh;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final generation = cardGenerationProvider(sampleProfileId);

  ProviderContainer makeContainer(
    CardApi api, {
    Duration poll = Duration.zero,
  }) {
    final container = ProviderContainer(
      overrides: [
        withSampleProfile,
        cardApiProvider.overrideWithValue(api),
        cardPollIntervalProvider.overrideWithValue(poll),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// 처음부터 확인하고 끝난 상태를 돌려준다.
  Future<CardGenerationStatus?> run(ProviderContainer container) async {
    await container.read(generation.notifier).start();
    return container.read(generation).value;
  }

  test('시작하기 전에는 묻지 않는다', () {
    final api = FakeCardApi();
    final container = makeContainer(api);

    expect(container.read(generation).value, isNull);
    expect(api.calls, isEmpty);
  });

  test('작업이 없으면 생성을 요청하고 다 될 때까지 다시 묻는다', () async {
    final api = FakeCardApi(statuses: [_none, _running, _running, _ready]);
    final container = makeContainer(api);

    expect(await run(container), _ready);
    expect(api.calls, ['status', 'request', 'status', 'status', 'status']);
  });

  test('이미 준비된 묶음이 있으면 새로 만들지 않는다', () async {
    final api = FakeCardApi(statuses: [_ready]);
    final container = makeContainer(api);

    expect(await run(container), _ready);
    expect(api.calls, ['status']);
  });

  test('지난 생성이 실패했으면 다시 요청한다', () async {
    final api = FakeCardApi(statuses: [_failed, _ready]);
    final container = makeContainer(api);

    expect(await run(container), _ready);
    expect(api.calls, ['status', 'request', 'status']);
  });

  test('만드는 중이면 요청하지 않고 기다린다', () async {
    final api = FakeCardApi(statuses: [_running, _ready]);
    final container = makeContainer(api);

    expect(await run(container), _ready);
    expect(api.calls, isNot(contains('request')));
  });

  test('기다리다 실패하면 실패를 돌려주고 다시 요청하지 않는다', () async {
    final api = FakeCardApi(statuses: [_none, _running, _failed]);
    final container = makeContainer(api);

    expect(await run(container), _failed);
    expect(api.calls.where((c) => c == 'request'), hasLength(1));
  });

  test('다시 시작하면 처음부터 확인하고 다시 요청한다', () async {
    final api = FakeCardApi(statuses: [_none, _failed, _failed, _ready]);
    final container = makeContainer(api);
    expect(await run(container), _failed);

    expect(await run(container), _ready);
    expect(api.calls.where((c) => c == 'request'), hasLength(2));
  });

  test('묻는 중에 다시 시작해도 생성을 두 번 요청하지 않는다', () async {
    final api = FakeCardApi(statuses: [_none, _running, _ready]);
    final container = makeContainer(
      api,
      poll: const Duration(milliseconds: 20),
    );
    final notifier = container.read(generation.notifier);

    final first = notifier.start();
    await notifier.start();
    await first;

    expect(container.read(generation).value, _ready);
    expect(api.calls.where((c) => c == 'request'), hasLength(1));
  });

  test('면회 중인 묶음이 있으면 그 상태로 끝낸다', () async {
    final api = FakeCardApi(statuses: [_inVisit]);
    final container = makeContainer(api);

    expect(await run(container), _inVisit);
    expect(api.calls, ['status']);
  });

  test('받은 뒤 정보를 고친 묶음이면 시작할 때 다시 만들지 않는다', () async {
    final api = FakeCardApi(statuses: [_needsRefresh]);
    final container = makeContainer(api);

    expect(await run(container), _needsRefresh);
    expect(api.calls, ['status'], reason: '보호자가 홈 버튼을 누를 때 만든다');
  });

  group('홈 버튼(prepare)', () {
    test('쓸 묶음이 있으면 기다리지 않았다고 알린다', () async {
      final api = FakeCardApi(statuses: [_ready]);
      final container = makeContainer(api);

      expect(await container.read(generation.notifier).prepare(), isFalse);
      expect(container.read(generation).value, _ready);
      expect(api.calls, ['status']);
    });

    test('만들어야 하면 기다렸다고 알린다', () async {
      final api = FakeCardApi(statuses: [_none, _running, _ready]);
      final container = makeContainer(api);

      expect(await container.read(generation.notifier).prepare(), isTrue);
      expect(container.read(generation).value, _ready);
    });

    test('만드는 중이었어도 기다렸다고 알린다', () async {
      final api = FakeCardApi(statuses: [_running, _ready]);
      final container = makeContainer(api);

      expect(await container.read(generation.notifier).prepare(), isTrue);
      expect(api.calls, isNot(contains('request')));
    });

    test('받은 뒤 정보를 고친 묶음이면 새로 만들고 받아 둔 묶음을 버린다', () async {
      final api = FakeCardApi(statuses: [_needsRefresh, _running, _ready]);
      final container = makeContainer(api);
      await container.read(currentCardSetProvider.future);

      expect(await container.read(generation.notifier).prepare(), isTrue);

      expect(container.read(generation).value, _ready);
      expect(api.calls.where((c) => c == 'request'), hasLength(1));
      await container.read(currentCardSetProvider.future);
      expect(api.calls.where((c) => c == 'current'), hasLength(2));
    });

    test('상태는 ready 여도 받아 둔 묶음이 고친 묶음이면 새로 만든다', () async {
      // 카드 화면이 홈으로 돌려보낸 경우다. 다시 만들지 않으면 오가기만 한다.
      final api = _OutdatedSetCardApi(statuses: [_ready, _running, _ready]);
      final container = makeContainer(api);
      await container.read(currentCardSetProvider.future);

      await container.read(generation.notifier).prepare();

      expect(api.calls.where((c) => c == 'request'), hasLength(1));
      expect(container.read(generation).value, _ready);
    });

    test('묶음을 아직 받지 않았으면 받으러 가지 않는다', () async {
      final api = FakeCardApi(statuses: [_ready]);
      final container = makeContainer(api);

      await container.read(generation.notifier).prepare();

      expect(api.calls, ['status']);
    });

    test('다시 만들다 실패하면 실패로 끝난다', () async {
      final api = FakeCardApi(statuses: [_needsRefresh, _failed]);
      final container = makeContainer(api);

      await container.read(generation.notifier).prepare();

      expect(container.read(generation).value, _failed);
    });

    test('어디까지 왔는지 남긴다', () async {
      final making = cardMakingProvider(sampleProfileId);
      final seen = <CardMaking>[];

      Future<void> watch(List<CardGenerationStatus> statuses) async {
        final container = makeContainer(FakeCardApi(statuses: statuses));
        container.listen(making, (_, next) => seen.add(next));
        await container.read(generation.notifier).prepare();
        seen.add(container.read(making));
      }

      await watch([_ready]);
      expect(seen.last, CardMaking.checking, reason: '묻기만 했다');

      await watch([_none, _ready]);
      expect(seen.last, CardMaking.making);

      await watch([_needsRefresh, _running, _ready]);
      expect(seen.last, CardMaking.remaking, reason: '만드는 중으로 낮추지 않는다');
    });
  });

  test('생성 요청이 이미 쓸 묶음이 있다고 거절되면 그 상태로 끝낸다', () async {
    final api = FakeCardApi(statuses: [_none], onRequest: _ready);
    final container = makeContainer(api);

    expect(await run(container), _ready);
    expect(api.calls, ['status', 'request']);
  });

  test('새로 만든 묶음을 받으면 앞서 받아 둔 묶음을 버린다', () async {
    final api = FakeCardApi(statuses: [_none, _ready]);
    final container = makeContainer(api);

    await container.read(currentCardSetProvider.future);
    await run(container);
    await container.read(currentCardSetProvider.future);

    expect(api.calls.where((c) => c == 'current'), hasLength(2));
  });

  test('연결 실패는 오류로 남기고 혼자 다시 시도하지 않는다', () async {
    final api = _OfflineCardApi();
    final container = makeContainer(api);

    await run(container);
    expect(container.read(generation).error, isA<ApiNetworkFailure>());
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(api.attempts, 1, reason: '자동 재시도로 4-1 이 반복되면 안 된다');
  });

  test('보는 화면이 없어도 다 될 때까지 묻는다', () async {
    // 홈에서 시작하고 일대기로 가도 이어진다. 아무도 듣지 않는 상태다.
    final api = FakeCardApi(statuses: [_running, _running, _running, _ready]);
    final container = makeContainer(
      api,
      poll: const Duration(milliseconds: 20),
    );

    unawaited(container.read(generation.notifier).start());
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(container.read(generation).value, _ready);
    expect(api.calls, hasLength(4));
  });

  test('로그아웃처럼 지우면 더 묻지 않는다', () async {
    final api = FakeCardApi(statuses: [_running]);
    final container = makeContainer(
      api,
      poll: const Duration(milliseconds: 20),
    );

    unawaited(container.read(generation.notifier).start());
    await Future<void>.delayed(const Duration(milliseconds: 70));
    container.invalidate(cardGenerationProvider);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final askedBefore = api.calls.length;
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(askedBefore, greaterThan(1));
    expect(api.calls, hasLength(askedBefore));
    expect(container.read(generation).value, isNull);
  });

  test('어르신마다 따로 기다린다', () async {
    final api = FakeCardApi(statuses: [_ready]);
    final container = makeContainer(api);

    await run(container);

    expect(container.read(generation).value, _ready);
    expect(container.read(cardGenerationProvider('other')).value, isNull);
    expect(api.profileIds, everyElement(sampleProfileId));
  });

  test('카드 묶음은 앱 안의 ID 가 아니라 프로필의 profileId 로 받는다', () async {
    // 이번 실행에서 새로 등록한 분은 앱 안의 ID 와 서버가 준 ID 가 다르다.
    // 카드 화면은 serverProfileIdProvider 의 값으로 생성을 시작한다.
    final api = FakeCardApi(statuses: [_ready]);
    final container = ProviderContainer(
      overrides: [
        withSampleProfile,
        cardApiProvider.overrideWithValue(api),
        profileProvider.overrideWith((ref) async {
          final bundle = await const MockRepository().loadProfile();
          final p = bundle.profile;
          return ProfileBundle(
            profile: Profile(
              profileId: 'server-profile-1',
              name: p.name,
              gender: p.gender,
              birthDate: p.birthDate,
              ageRange: p.ageRange,
              stage: p.stage,
              lifeFactIds: p.lifeFactIds,
              photoIds: p.photoIds,
            ),
            lifeFacts: bundle.lifeFacts,
            collectionStates: bundle.collectionStates,
            photos: bundle.photos,
          );
        }),
      ],
    );
    addTearDown(container.dispose);

    final id = await container.read(serverProfileIdProvider.future);
    await container.read(cardGenerationProvider(id!).notifier).start();
    await container.read(currentCardSetProvider.future);

    expect(id, 'server-profile-1');
    expect(api.profileIds, everyElement('server-profile-1'));
    expect(api.profileIds, isNot(contains(sampleProfileId)));
  });
}

/// 받아 둔 묶음(4-3)이 받은 뒤 정보를 고친 묶음이다. 다시 만든 뒤에는
/// 고치지 않은 묶음을 준다.
class _OutdatedSetCardApi extends FakeCardApi {
  _OutdatedSetCardApi({required super.statuses});

  var _first = true;

  @override
  Future<CardSet> current(String profileId) async {
    final set = await super.current(profileId);
    if (!_first) return set;
    _first = false;
    return CardSet(
      setId: set.setId,
      usedBySessionId: set.usedBySessionId,
      cards: set.cards,
      needsRefresh: true,
    );
  }
}

/// 서버에 닿지 못한다.
class _OfflineCardApi implements CardApi {
  var attempts = 0;

  @override
  Future<CardGenerationStatus> status(String profileId) async {
    attempts++;
    throw const ApiNetworkFailure();
  }

  @override
  Future<CardGenerationStatus> requestGeneration(String profileId) =>
      throw UnimplementedError();

  @override
  Future<CardSet> current(String profileId) => throw UnimplementedError();
}
