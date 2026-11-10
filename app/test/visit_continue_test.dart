// 녹음을 시작한 뒤 녹음 화면을 떠났을 때 같은 회차를 이어 가는지 확인한다
// (#234). 녹음을 시작하면(5-1) 서버가 카드 묶음을 `inVisit` 으로 본다.
//
// - 카드 화면은 고르기와 `대화 시작하기` 대신 `평가 이어서 하기` 를 보여준다.
// - 홈은 앱을 다시 켜지 않아도 `평가 이어서 하기` 배너를 띄운다.
// - 이어서 하기는 그 회차의 평가(`/visit/review?session=<회차 ID>`)로 간다.
//
// 서버, 녹음 장치와 기기 기록은 대역을 쓰고 값은 모두 합성이다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/data/api_client.dart';
import 'package:saerok/data/card_api.dart';
import 'package:saerok/data/mock_repository.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/data/visit_api.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/cards/card_generation_controller.dart';
import 'package:saerok/features/cards/cards_controller.dart';
import 'package:saerok/features/cards/cards_screen.dart';
import 'package:saerok/features/review/review_controller.dart';
import 'package:saerok/features/visit/pending_uploads.dart';
import 'package:saerok/features/visit/visit_controller.dart';
import 'package:saerok/features/visit/visit_photos.dart';
import 'package:saerok/features/visit/visit_recorder.dart';

import 'fake_card_api.dart';
import 'fake_pending_uploads.dart';
import 'fake_visit_api.dart';
import 'fake_visit_photos.dart';
import 'fake_visit_recorder.dart';
import 'sample_profile.dart';

const _serverProfileId = 'server-profile-1';

/// 목 묶음(`conversation-cards.json`)을 쓰는 회차. 앱을 다시 켠 뒤 4-3 이 주는
/// `usedBySessionId` 다.
const _restoredSessionId = 'session_demo_001';

/// 목 묶음은 asset 에서 읽는다. 화면을 띄우기 전에 한 번 읽어 둔다.
late CardSet _mockSet;

/// 4-2 는 정해 둔 상태를, 4-3 은 읽어 둔 목 묶음을 돌려준다.
class _PreloadedCardApi extends FakeCardApi {
  _PreloadedCardApi({required super.statuses});

  /// 있으면 4-3 이 이 실패로 끝난다.
  Object? currentFailure;

  @override
  Future<CardSet> current(String profileId) async {
    calls.add('current');
    if (currentFailure case final failure?) throw failure;
    return _mockSet;
  }
}

ProviderContainer _container(_PreloadedCardApi cards, FakeVisitApi visits) {
  final container = ProviderContainer(
    overrides: [
      withSampleProfile,
      serverProfileIdProvider.overrideWith((ref) async => _serverProfileId),
      cardApiProvider.overrideWithValue(cards),
      cardPollIntervalProvider.overrideWithValue(Duration.zero),
      visitApiProvider.overrideWithValue(visits),
      visitRecorderProvider.overrideWithValue(FakeVisitRecorder()),
      pendingUploadsProvider.overrideWithValue(FakePendingUploads()),
      visitPhotosProvider.overrideWithValue(FakeVisitPhotos()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// 카드 한 장을 고르고 녹음을 시작한 뒤, 끝내기를 누르지 않고 녹음 화면을
/// 떠난다. 녹음 화면의 `dispose` 처럼 참여자 수 없이 파일만 닫는다.
Future<void> _startThenLeave(ProviderContainer container) async {
  final cards = await container.read(cardsControllerProvider.future);
  container
      .read(cardsControllerProvider.notifier)
      .toggleSelected(cards.cards.first.cardId);
  await container.read(visitControllerProvider.future);
  final visit = container.read(visitControllerProvider.notifier);
  await visit.startRecording();
  await visit.stopRecording();
}

Future<void> _openCards(
  WidgetTester tester,
  ProviderContainer container,
) async {
  // 기준 화면 412 x 917 dp 다(`app/README.md`).
  tester.view.physicalSize = const Size(1236, 2751);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: AppRoutes.cards,
    routes: [
      GoRoute(
        path: AppRoutes.cards,
        builder: (context, state) => const CardsScreen(),
      ),
      GoRoute(
        path: AppRoutes.visitReview,
        builder: (context, state) =>
            Scaffold(body: Text('평가 ${state.uri.queryParameters['session']}')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    _mockSet = await const MockRepository().loadCardSet();
  });

  group('녹음을 시작하면', () {
    test('카드 생성 상태를 면회 중으로 바꾼다', () async {
      final cards = _PreloadedCardApi(statuses: [CardGenerationStatus.ready]);
      final container = _container(cards, FakeVisitApi());
      final generation = cardGenerationProvider(_serverProfileId);
      await container.read(generation.notifier).start();
      expect(container.read(generation).value, CardGenerationStatus.ready);

      await _startThenLeave(container);

      expect(
        container.read(generation).value,
        CardGenerationStatus.inVisit,
        reason: '뒤에 남은 카드 화면이 대화 시작하기를 다시 보여주지 않게 한다',
      );
      expect(
        cards.calls.where((c) => c == 'status'),
        hasLength(1),
        reason: '서버에 다시 묻지 않는다',
      );
    });

    test('앱을 다시 켜지 않아도 홈에 평가 이어서 하기를 띄운다', () async {
      final container = _container(
        _PreloadedCardApi(statuses: [CardGenerationStatus.ready]),
        FakeVisitApi(),
      );
      expect(container.read(reportNoticeInfoProvider), isNull);

      await _startThenLeave(container);

      final info = container.read(reportNoticeInfoProvider);
      expect(info?.notice, ReportNotice.evaluationPending);
      expect(info?.reportId, FakeVisitApi.sessionId);
      // FakeVisitApi 의 `startedAt` 은 2026-10-13T14:00:00+09:00 이다.
      expect(info?.visitDate, '2026-10-13');
    });

    test('회차를 만들지 못하면 상태를 바꾸지 않는다', () async {
      final container = _container(
        _PreloadedCardApi(statuses: [CardGenerationStatus.ready]),
        FakeVisitApi(failCreate: true),
      );
      final generation = cardGenerationProvider(_serverProfileId);
      await container.read(generation.notifier).start();

      await _startThenLeave(container);

      expect(container.read(generation).value, CardGenerationStatus.ready);
      expect(container.read(reportNoticeInfoProvider), isNull);
    });
  });

  test('같은 실행에서 이어서 하면 면회 상태의 카드와 녹음을 쓴다', () async {
    final container = _container(
      _PreloadedCardApi(statuses: [CardGenerationStatus.ready]),
      FakeVisitApi(),
    );
    await _startThenLeave(container);
    final visit = container.read(visitControllerProvider).value!;

    final target = await container.read(
      reviewTargetProvider(FakeVisitApi.sessionId).future,
    );

    // 받아 둔 묶음은 회차를 만들기 전 것이라 이 회차를 모른다. 그래도
    // 이어서 할 수 있어야 한다.
    expect(target, isNotNull);
    expect(target?.sessionId, FakeVisitApi.sessionId);
    expect(
      target?.cards.map((c) => c.cardId),
      visit.cards.map((c) => c.cardId),
    );
    expect(target?.audioPath, visit.recordingPath);
    expect(target?.audioPath, isNotNull);
    expect(
      target?.participantCount,
      isNull,
      reason: '끝내기 창을 거치지 않았다. 확인받지 않은 수를 지어내지 않는다',
    );
  });

  group('카드 화면의 면회 중', () {
    testWidgets('고르기 대신 평가 이어서 하기를 보여준다', (tester) async {
      final container = _container(
        _PreloadedCardApi(statuses: [CardGenerationStatus.inVisit]),
        FakeVisitApi(),
      );
      await _openCards(tester, container);

      expect(find.textContaining('아직 마치지 않은 면회가 있어요'), findsOneWidget);
      expect(find.text('평가 이어서 하기'), findsOneWidget);
      expect(find.text('대화 시작하기'), findsNothing);
      expect(find.text('질문 보기'), findsNothing);
    });

    testWidgets('앱을 다시 켰으면 4-3 의 회차로 평가를 이어서 한다', (tester) async {
      final container = _container(
        _PreloadedCardApi(statuses: [CardGenerationStatus.inVisit]),
        FakeVisitApi(),
      );
      await _openCards(tester, container);

      await tester.tap(find.text('평가 이어서 하기'));
      await tester.pumpAndSettle();

      expect(find.text('평가 $_restoredSessionId'), findsOneWidget);
    });

    testWidgets('녹음 화면에서 뒤로 나오면 대화 시작하기 대신 이어서 하기를 보여준다', (tester) async {
      final visits = FakeVisitApi();
      final container = _container(
        _PreloadedCardApi(statuses: [CardGenerationStatus.ready]),
        visits,
      );
      await _openCards(tester, container);
      expect(find.text('대화 시작하기'), findsOneWidget);

      // 카드 화면 위에서 녹음을 시작했다가 끝내지 않고 돌아온 경우다.
      await _startThenLeave(container);
      await tester.pumpAndSettle();

      expect(find.text('대화 시작하기'), findsNothing);
      await tester.tap(find.text('평가 이어서 하기'));
      await tester.pumpAndSettle();

      expect(find.text('평가 ${FakeVisitApi.sessionId}'), findsOneWidget);
      expect(
        visits.calls.where((c) => c == 'create'),
        hasLength(1),
        reason: '같은 묶음으로 회차를 다시 만들지 않는다',
      );
    });

    testWidgets('쓸 묶음이 없으면 상태를 다시 묻는다', (tester) async {
      final cards =
          _PreloadedCardApi(
              statuses: [
                CardGenerationStatus.inVisit,
                CardGenerationStatus.ready,
              ],
            )
            ..currentFailure = const ApiServerFailure(
              statusCode: 404,
              errorCode: 'CARD_GENERATION_NOT_FOUND',
            );
      final container = _container(cards, FakeVisitApi());
      await _openCards(tester, container);

      await tester.tap(find.text('평가 이어서 하기'));
      await tester.pumpAndSettle();

      expect(cards.calls.where((c) => c == 'status'), hasLength(2));
      expect(find.textContaining('평가 session'), findsNothing);
      expect(find.text('평가 이어서 하기'), findsNothing);
    });

    testWidgets('묶음을 받지 못하면 다시 시도하게 한다', (tester) async {
      final cards = _PreloadedCardApi(statuses: [CardGenerationStatus.inVisit])
        ..currentFailure = const ApiNetworkFailure();
      final container = _container(cards, FakeVisitApi());
      await _openCards(tester, container);

      await tester.tap(find.text('평가 이어서 하기'));
      await tester.pumpAndSettle();
      expect(find.textContaining('서버에 연결하지 못했어요'), findsOneWidget);

      cards.currentFailure = null;
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(find.text('평가 $_restoredSessionId'), findsOneWidget);
    });
  });
}
