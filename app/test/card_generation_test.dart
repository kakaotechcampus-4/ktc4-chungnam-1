// 카드 화면에 들어온 뒤 쓸 묶음이 생길 때까지의 흐름을 확인한다.
//
// `lib/features/cards/card_generation_controller.dart`. 서버 대신
// `FakeCardApi` 를 쓰고 값은 모두 합성이다.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/api_client.dart';
import 'package:saerok/data/card_api.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer makeContainer(CardApi api) {
    final container = ProviderContainer(
      overrides: [
        withSampleProfile,
        cardApiProvider.overrideWithValue(api),
        cardPollIntervalProvider.overrideWithValue(Duration.zero),
      ],
    );
    addTearDown(container.dispose);
    // autoDispose 라서 보는 쪽이 있어야 살아 있다. 화면이 보는 것과 같다.
    container.listen(cardGenerationProvider, (_, _) {});
    return container;
  }

  test('작업이 없으면 생성을 요청하고 다 될 때까지 다시 묻는다', () async {
    final api = FakeCardApi(statuses: [_none, _running, _running, _ready]);
    final container = makeContainer(api);

    final status = await container.read(cardGenerationProvider.future);

    expect(status, _ready);
    expect(api.calls, ['status', 'request', 'status', 'status', 'status']);
  });

  test('이미 준비된 묶음이 있으면 새로 만들지 않는다', () async {
    final api = FakeCardApi(statuses: [_ready]);
    final container = makeContainer(api);

    expect(await container.read(cardGenerationProvider.future), _ready);
    expect(api.calls, ['status']);
  });

  test('지난 생성이 실패했으면 들어올 때 다시 요청한다', () async {
    final api = FakeCardApi(statuses: [_failed, _ready]);
    final container = makeContainer(api);

    expect(await container.read(cardGenerationProvider.future), _ready);
    expect(api.calls, ['status', 'request', 'status']);
  });

  test('만드는 중에 들어오면 요청하지 않고 기다린다', () async {
    final api = FakeCardApi(statuses: [_running, _ready]);
    final container = makeContainer(api);

    expect(await container.read(cardGenerationProvider.future), _ready);
    expect(api.calls, isNot(contains('request')));
  });

  test('기다리다 실패하면 실패를 돌려주고 다시 요청하지 않는다', () async {
    final api = FakeCardApi(statuses: [_none, _running, _failed]);
    final container = makeContainer(api);

    expect(await container.read(cardGenerationProvider.future), _failed);
    expect(api.calls.where((c) => c == 'request'), hasLength(1));
  });

  test('다시 받기를 누르면 처음부터 확인하고 다시 요청한다', () async {
    final api = FakeCardApi(statuses: [_none, _failed, _failed, _ready]);
    final container = makeContainer(api);
    expect(await container.read(cardGenerationProvider.future), _failed);

    container.read(cardGenerationProvider.notifier).retry();

    expect(await container.read(cardGenerationProvider.future), _ready);
    expect(api.calls.where((c) => c == 'request'), hasLength(2));
  });

  test('면회 중인 묶음이 있으면 그 상태로 끝낸다', () async {
    final api = FakeCardApi(statuses: [_inVisit]);
    final container = makeContainer(api);

    expect(await container.read(cardGenerationProvider.future), _inVisit);
    expect(api.calls, ['status']);
  });

  test('생성 요청이 이미 쓸 묶음이 있다고 거절되면 그 상태로 끝낸다', () async {
    final api = FakeCardApi(statuses: [_none], onRequest: _ready);
    final container = makeContainer(api);

    expect(await container.read(cardGenerationProvider.future), _ready);
    expect(api.calls, ['status', 'request']);
  });

  test('새로 만든 묶음을 받으면 앞서 받아 둔 묶음을 버린다', () async {
    final api = FakeCardApi(statuses: [_none, _ready]);
    final container = makeContainer(api);

    await container.read(currentCardSetProvider.future);
    await container.read(cardGenerationProvider.future);
    await container.read(currentCardSetProvider.future);

    expect(api.calls.where((c) => c == 'current'), hasLength(2));
  });

  test('연결 실패는 오류로 남기고 혼자 다시 시도하지 않는다', () async {
    final api = _OfflineCardApi();
    final container = makeContainer(api);

    await expectLater(
      container.read(cardGenerationProvider.future),
      throwsA(isA<ApiNetworkFailure>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(api.attempts, 1, reason: '자동 재시도로 4-1 이 반복되면 안 된다');
  });

  test('화면을 떠나면 더 묻지 않는다', () async {
    final api = FakeCardApi(statuses: [_running]);
    final container = ProviderContainer(
      overrides: [
        withSampleProfile,
        cardApiProvider.overrideWithValue(api),
        cardPollIntervalProvider.overrideWithValue(
          const Duration(milliseconds: 20),
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(cardGenerationProvider, (_, _) {});

    await Future<void>.delayed(const Duration(milliseconds: 70));
    subscription.close();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final askedWhileOpen = api.calls.length;
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(askedWhileOpen, greaterThan(1));
    expect(api.calls, hasLength(askedWhileOpen));
  });
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
