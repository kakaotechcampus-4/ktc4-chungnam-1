// 녹음 전 안내(E-1)에서 `네, 좋아요` 를 누른 뒤 회차를 만들기까지를 확인한다.
//
// - 권한, 회차 만들기(5-1)와 장치 열기를 기다리는 동안 버튼이 돌고
//   `녹음을 준비하고 있어요` 를 보이며, 다시 눌러도 5-1 은 한 번만 나간다.
// - 실패 안내는 버튼 바로 위에 두어 360x640 에서도 보인다.
// - 5-1 실패는 연결 실패, 서버 오류, 다시 눌러도 같은 거절로 나눠 알린다.
// - `CARD_SET_ALREADY_USED` 면 지금 묶음(4-3)을 다시 읽어, 이번 면회에서 만든
//   회차는 이어서 녹음하고 아니면 그 회차의 평가로 보낸다.
//
// 서버, 녹음 장치와 기기 기록은 대역을 쓰고 값은 모두 합성이다.

import 'dart:async';

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
import 'package:saerok/features/visit/pending_uploads.dart';
import 'package:saerok/features/visit/record_screen.dart';
import 'package:saerok/features/visit/visit_camera.dart';
import 'package:saerok/features/visit/visit_controller.dart';
import 'package:saerok/features/visit/visit_photos.dart';
import 'package:saerok/features/visit/visit_recorder.dart';
import 'package:saerok/widgets/app_scaffold.dart';

import 'fake_card_api.dart';
import 'fake_pending_uploads.dart';
import 'fake_screen_awake.dart';
import 'fake_visit_api.dart';
import 'fake_visit_camera.dart';
import 'fake_visit_photos.dart';
import 'fake_visit_recorder.dart';
import 'sample_profile.dart';

const _serverProfileId = 'server-profile-1';

/// 첫 5-1 이 서버에 닿았지만 응답이 늦어 앱은 받지 못한 회차.
const _lateSessionId = 'session_late_001';

/// 앱을 다시 켜기 전이나 다른 기기에서 같은 묶음으로 시작한 회차.
const _otherSessionId = 'session_other_001';

const _alreadyUsed = ApiServerFailure(
  statusCode: 409,
  errorCode: 'CARD_SET_ALREADY_USED',
);

const _photo = '/fake/visit-photo.jpg';

const _networkText = '인터넷 연결을 확인한 뒤';
const _startingText = '녹음을 준비하고 있어요';

/// 목 묶음은 asset 에서 읽는다. 화면을 띄우기 전에 한 번 읽어 둔다.
late CardSet _mockSet;

/// 녹음 화면을 열 때 받아 둔 묶음. 회차를 만들기 전이라 쓰는 회차가 없다.
CardSet get _setBeforeVisit => CardSet(
  setId: _mockSet.setId,
  usedBySessionId: null,
  cards: _mockSet.cards,
);

/// 4-3 을 다시 물었을 때의 답을 정해 둔다.
class _CardApi extends FakeCardApi {
  /// 이 묶음을 쓰는 평가 전 회차.
  String? usedBy;

  /// 있으면 4-3 이 이 실패로 끝난다.
  Object? failure;

  @override
  Future<CardSet> current(String profileId) async {
    calls.add('current');
    if (failure case final failure?) throw failure;
    return CardSet(
      setId: _mockSet.setId,
      usedBySessionId: usedBy,
      cards: _mockSet.cards,
    );
  }
}

class _Fixture {
  _Fixture() {
    container = ProviderContainer(
      overrides: [
        withSampleProfile,
        serverProfileIdProvider.overrideWith((ref) async => _serverProfileId),
        cardApiProvider.overrideWithValue(cards),
        currentCardSetProvider.overrideWith((ref) async => _setBeforeVisit),
        cardPollIntervalProvider.overrideWithValue(Duration.zero),
        visitApiProvider.overrideWithValue(visits),
        visitRecorderProvider.overrideWithValue(recorder),
        visitCameraProvider.overrideWithValue(FakeVisitCamera()),
        pendingUploadsProvider.overrideWithValue(FakePendingUploads()),
        visitPhotosProvider.overrideWithValue(FakeVisitPhotos()),
        FakeScreenAwakePlatform().asOverride,
      ],
    );
    addTearDown(container.dispose);
  }

  final cards = _CardApi();
  final visits = FakeVisitApi();
  final recorder = FakeVisitRecorder();
  late final ProviderContainer container;

  VisitController get controller =>
      container.read(visitControllerProvider.notifier);

  VisitState get state => container.read(visitControllerProvider).value!;

  int get creates => visits.calls.where((c) => c == 'create').length;

  CardGenerationStatus? get generation =>
      container.read(cardGenerationProvider(_serverProfileId)).value;

  /// 카드 한 장을 고르고 면회 상태를 만든다. [photo] 면 사진도 찍어 둔다.
  Future<void> select({bool photo = false}) async {
    final picked = await container.read(cardsControllerProvider.future);
    container
        .read(cardsControllerProvider.notifier)
        .toggleSelected(picked.cards.first.cardId);
    if (photo) {
      await container
          .read(visitPhotoProvider.notifier)
          .replace(_photo, inGallery: true);
    }
    await container.read(visitControllerProvider.future);
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    _mockSet = await const MockRepository().loadCardSet();
  });

  group('5-1 실패 안내', () {
    for (final (name, failure, problem) in <(String, Object, Object)>[
      ('연결 실패', const ApiNetworkFailure(), VisitRecordingProblem.sessionFailed),
      (
        '서버 오류(500)',
        const ApiServerFailure(statusCode: 500),
        VisitRecordingProblem.sessionServerError,
      ),
      (
        '다시 시도해도 되는 거절(503 retryable)',
        const ApiServerFailure(
          statusCode: 503,
          errorCode: 'DATABASE_NOT_CONFIGURED',
          retryable: true,
        ),
        VisitRecordingProblem.sessionServerError,
      ),
      (
        '읽지 못한 응답',
        const ApiUnexpectedResponseFailure('회차 응답 모양이 다르다'),
        VisitRecordingProblem.sessionServerError,
      ),
      (
        '고른 카드 거절(422)',
        const ApiServerFailure(
          statusCode: 422,
          errorCode: 'INVALID_CARD_SELECTION',
        ),
        VisitRecordingProblem.sessionRefused,
      ),
      (
        '묶음 없음(404)',
        const ApiServerFailure(
          statusCode: 404,
          errorCode: 'CARD_GENERATION_NOT_FOUND',
        ),
        VisitRecordingProblem.sessionRefused,
      ),
    ]) {
      test('$name 은 그에 맞는 안내로 알리고 녹음하지 않는다', () async {
        final f = _Fixture();
        await f.select();
        f.visits.createFailure = failure;

        await f.controller.startRecording();

        expect(f.state.problem, problem);
        expect(f.state.started, isFalse);
        expect(f.state.starting, isFalse);
        expect(f.recorder.calls, isNot(contains('start')));
      });
    }
  });

  group('이미 회차에 쓴 묶음(CARD_SET_ALREADY_USED)', () {
    test('첫 5-1 이 응답 없이 끝났으면 그 회차를 이어 받아 녹음한다', () async {
      final f = _Fixture();
      await f.select(photo: true);

      // 첫 요청은 서버에 닿아 회차를 만들었지만 응답이 15초를 넘겼다.
      f.visits.failCreate = true;
      await f.controller.startRecording();
      expect(f.state.problem, VisitRecordingProblem.sessionFailed);

      // 다시 누르면 서버는 같은 묶음이라 거절하고, 4-3 은 그 회차를 알려준다.
      f.visits
        ..failCreate = false
        ..createFailure = _alreadyUsed;
      f.cards.usedBy = _lateSessionId;
      await f.controller.startRecording();
      await pumpEventQueue();

      expect(f.state.sessionId, _lateSessionId);
      expect(f.state.recording, isTrue);
      expect(f.state.problem, isNull);
      expect(f.recorder.calls.where((c) => c == 'start'), hasLength(1));
      expect(f.cards.calls, contains('current'));
      expect(f.visits.photos.map((p) => p.sessionId), [
        _lateSessionId,
      ], reason: '찍어 둔 사진은 이어 받은 회차에 올린다');
      expect(f.generation, CardGenerationStatus.inVisit);
    });

    test('회차를 받은 뒤 5-3 이 실패했어도 다시 누르면 같은 회차로 잇는다', () async {
      final f = _Fixture();
      await f.select();
      final supplements = await f.container.read(
        supplementCardsProvider.future,
      );
      await f.controller.addCards(supplements.take(1));

      f.visits.failAdd = true;
      await f.controller.startRecording();
      expect(f.state.sessionId, isNull);
      expect(f.state.problem, VisitRecordingProblem.sessionFailed);

      f.visits
        ..failAdd = false
        ..createFailure = _alreadyUsed;
      f.cards.usedBy = FakeVisitApi.sessionId;
      await f.controller.startRecording();

      expect(f.state.sessionId, FakeVisitApi.sessionId);
      expect(f.state.recording, isTrue);
      expect(f.visits.added, [supplements.first.cardId]);
    });

    test('이번 면회에서 만든 회차가 아니면 녹음하지 않고 그 회차의 평가로 보낸다', () async {
      final f = _Fixture();
      await f.select();
      f.visits.createFailure = _alreadyUsed;
      f.cards.usedBy = _otherSessionId;

      await f.controller.startRecording();

      expect(f.state.problem, VisitRecordingProblem.visitAlreadyStarted);
      expect(f.state.existingSessionId, _otherSessionId);
      expect(f.state.sessionId, isNull);
      expect(f.state.started, isFalse);
      expect(f.recorder.calls, isNot(contains('start')));
      expect(
        f.generation,
        CardGenerationStatus.inVisit,
        reason: '뒤의 카드 화면이 대화 시작하기 대신 평가 이어서 하기를 보여준다',
      );
    });

    for (final (name, usedBy, failure) in <(String, String?, Object?)>[
      ('4-3 이 쓸 묶음이 없다고 하면', null, const ApiServerFailure(statusCode: 404)),
      ('묶음을 쓰는 평가 전 회차가 없으면', null, null),
    ]) {
      test('$name 평가까지 마친 묶음이라 홈에서 새로 받게 한다', () async {
        final f = _Fixture();
        await f.select();
        f.visits.createFailure = _alreadyUsed;
        f.cards
          ..usedBy = usedBy
          ..failure = failure;

        await f.controller.startRecording();

        expect(f.state.problem, VisitRecordingProblem.sessionRefused);
        expect(f.state.existingSessionId, isNull);
        expect(f.recorder.calls, isNot(contains('start')));
      });
    }

    test('회차를 찾다 연결이 끊기면 연결 안내를 보이고, 다음에 남의 회차를 이어 받지 않는다', () async {
      final f = _Fixture();
      await f.select();
      f.visits.createFailure = _alreadyUsed;
      f.cards.failure = const ApiNetworkFailure();

      await f.controller.startRecording();
      expect(f.state.problem, VisitRecordingProblem.sessionFailed);

      f.cards
        ..failure = null
        ..usedBy = _otherSessionId;
      await f.controller.startRecording();

      expect(
        f.state.problem,
        VisitRecordingProblem.visitAlreadyStarted,
        reason: '4-3 실패는 5-1 이 회차를 만들었다는 근거가 아니다',
      );
      expect(f.recorder.calls, isNot(contains('start')));
    });
  });

  group('시작하는 중', () {
    test('기다리는 동안 다시 불러도 5-1 은 한 번만 보낸다', () async {
      final f = _Fixture();
      await f.select();
      final gate = f.visits.createGate = Completer<void>();

      // 두 번 빠르게 누른 것과 같다. 첫 호출이 권한을 기다리는 사이 두 번째가 온다.
      final first = f.controller.startRecording();
      final second = f.controller.startRecording();
      await pumpEventQueue();
      expect(f.state.starting, isTrue);

      gate.complete();
      await Future.wait([first, second]);

      expect(f.creates, 1);
      expect(f.recorder.calls.where((c) => c == 'start'), hasLength(1));
      expect(f.state.starting, isFalse);
      expect(f.state.recording, isTrue);
    });

    test('기다리는 사이 녹음 화면을 떠나면 장치를 열지 않는다', () async {
      final f = _Fixture();
      await f.select();
      final gate = f.visits.createGate = Completer<void>();

      final start = f.controller.startRecording();
      await pumpEventQueue();
      unawaited(f.controller.stopRecordingOnLeave());
      gate.complete();
      await start;
      await pumpEventQueue();

      expect(f.recorder.calls, isNot(contains('start')));
      expect(f.state.recording, isFalse);
      expect(f.state.starting, isFalse);
      expect(
        f.state.sessionId,
        FakeVisitApi.sessionId,
        reason: '만든 회차는 남겨 카드 화면과 홈이 평가 이어서 하기로 잇는다',
      );
    });

    test('장치를 여는 사이 녹음 화면을 떠나면 열린 장치를 바로 닫는다', () async {
      final f = _Fixture();
      await f.select();
      final gate = f.recorder.startGate = Completer<void>();

      final start = f.controller.startRecording();
      await pumpEventQueue();
      expect(f.recorder.calls, contains('start'));
      unawaited(f.controller.stopRecordingOnLeave());
      await pumpEventQueue();
      gate.complete();
      await start;
      await pumpEventQueue();

      expect(
        f.recorder.calls.last,
        'stop',
        reason: '화면이 없는 곳에서 마이크가 켜져 있으면 안 된다',
      );
      expect(f.state.recording, isFalse);
      expect(f.state.started, isFalse);
      expect(f.state.starting, isFalse);
      expect(f.state.sessionId, FakeVisitApi.sessionId);

      // 같은 회차로 다시 누르면 새 파일로 녹음한다.
      await f.controller.startRecording();
      expect(f.creates, 1);
      expect(f.state.recording, isTrue);
    });
  });

  group('녹음 전 안내 화면', () {
    /// 녹음 전 안내를 띄운다. [router] 면 평가 화면으로 가는 길도 둔다.
    Future<_Fixture> open(
      WidgetTester tester, {
      Size size = const Size(412, 917),
      double textScale = 1.0,
      bool router = false,
      void Function(_Fixture f)? arrange,
    }) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final f = _Fixture();
      arrange?.call(f);
      await f.select();

      Widget scaled(BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      );

      final Widget app;
      if (router) {
        final routes = GoRouter(
          initialLocation: AppRoutes.visitRecord,
          routes: [
            GoRoute(
              path: AppRoutes.visitRecord,
              builder: (context, state) => const RecordScreen(),
            ),
            GoRoute(
              path: AppRoutes.visitReview,
              builder: (context, state) => Scaffold(
                body: Text('평가 ${state.uri.queryParameters['session']}'),
              ),
            ),
          ],
        );
        addTearDown(routes.dispose);
        app = MaterialApp.router(
          theme: buildAppTheme(),
          routerConfig: routes,
          builder: scaled,
        );
      } else {
        app = MaterialApp(
          theme: buildAppTheme(),
          builder: scaled,
          home: const RecordScreen(),
        );
      }

      await tester.pumpWidget(
        UncontrolledProviderScope(container: f.container, child: app),
      );
      await tester.pumpAndSettle();
      return f;
    }

    FilledButton primary(WidgetTester tester) => tester.widget<FilledButton>(
      find.descendant(
        of: find.byType(ScreenBody),
        matching: find.byType(FilledButton),
      ),
    );

    testWidgets('누르면 버튼이 돌고 녹음을 준비하고 있어요를 보이며 다시 눌러도 한 번만 시작한다', (
      tester,
    ) async {
      late Completer<void> gate;
      final f = await open(
        tester,
        arrange: (f) => gate = f.visits.createGate = Completer<void>(),
      );

      await tester.tap(find.text('네, 좋아요'));
      await tester.pump();

      expect(find.text(_startingText), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(FilledButton),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(primary(tester).onPressed, isNull, reason: '도는 동안은 받지 않는다');

      await tester.tap(find.text('네, 좋아요'), warnIfMissed: false);
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();

      expect(f.creates, 1);
      expect(find.text(_startingText), findsNothing);
      expect(find.text('녹음 중이에요'), findsOneWidget);
    });

    for (final (size, scale) in const [
      (Size(360, 640), 1.0),
      (Size(360, 640), 1.3),
      (Size(390, 844), 1.0),
    ]) {
      final tag = '${size.width.toInt()}x${size.height.toInt()} 글자 $scale배';
      testWidgets('$tag 에서 실패 안내가 버튼 바로 위에 보인다', (tester) async {
        await open(
          tester,
          size: size,
          textScale: scale,
          arrange: (f) => f.visits.failCreate = true,
        );

        await tester.tap(find.text('네, 좋아요'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final notice = find.textContaining(_networkText);
        expect(notice.hitTestable(), findsOneWidget);
        final noticeRect = tester.getRect(notice);
        final buttonRect = tester.getRect(find.text('네, 좋아요'));
        expect(noticeRect.top, greaterThanOrEqualTo(0));
        expect(noticeRect.bottom, lessThan(buttonRect.top));
        expect(
          buttonRect.top - noticeRect.bottom,
          lessThan(80),
          reason: '안내가 버튼에 붙어 있다',
        );
        expect(find.text('네, 좋아요').hitTestable(), findsOneWidget);
      });
    }

    testWidgets('연결 실패, 서버 오류, 다시 눌러도 같은 거절을 다른 문구로 알린다', (tester) async {
      final f = await open(tester, arrange: (f) => f.visits.failCreate = true);
      await tester.tap(find.text('네, 좋아요'));
      await tester.pumpAndSettle();
      expect(find.textContaining(_networkText), findsOneWidget);

      f.visits
        ..failCreate = false
        ..createFailure = const ApiServerFailure(statusCode: 500);
      await tester.tap(find.text('네, 좋아요'));
      await tester.pumpAndSettle();
      expect(find.textContaining(_networkText), findsNothing);
      expect(find.textContaining('잠시 후 다시 눌러주세요'), findsOneWidget);

      f.visits.createFailure = const ApiServerFailure(
        statusCode: 422,
        errorCode: 'INVALID_CARD_SELECTION',
      );
      await tester.tap(find.text('네, 좋아요'));
      await tester.pumpAndSettle();
      expect(find.textContaining(_networkText), findsNothing);
      expect(find.textContaining('홈에서 오늘의 대화카드 받기를'), findsOneWidget);
    });

    testWidgets('응답이 늦어 연결 실패가 난 뒤 다시 누르면 같은 회차로 녹음을 시작한다', (tester) async {
      final f = await open(tester, arrange: (f) => f.visits.failCreate = true);
      await tester.tap(find.text('네, 좋아요'));
      await tester.pumpAndSettle();
      expect(find.textContaining(_networkText), findsOneWidget);

      f.visits
        ..failCreate = false
        ..createFailure = _alreadyUsed;
      f.cards.usedBy = _lateSessionId;
      await tester.tap(find.text('네, 좋아요'));
      await tester.pumpAndSettle();

      expect(find.textContaining(_networkText), findsNothing);
      expect(find.text('녹음 중이에요'), findsOneWidget);
      expect(f.state.sessionId, _lateSessionId);
    });

    testWidgets('이미 시작한 면회가 있으면 평가 이어서 하기로 그 회차의 평가를 연다', (tester) async {
      final f = await open(
        tester,
        router: true,
        arrange: (f) {
          f.visits.createFailure = _alreadyUsed;
          f.cards.usedBy = _otherSessionId;
        },
      );

      await tester.tap(find.text('네, 좋아요'));
      await tester.pumpAndSettle();

      expect(find.textContaining('이 카드로 시작한 면회가 있어요'), findsOneWidget);
      // 다른 기기에서 시작했거나 녹음 전에 멈춘 회차는 이 휴대폰에 녹음이 없어
      // 평가해도 리포트를 만들지 못한다. 리포트를 약속하지 않는다.
      expect(find.textContaining('평가를 마치면 새 대화 카드를 받을 수 있어요'), findsOneWidget);
      expect(find.textContaining('리포트를 만들어요'), findsNothing);
      expect(find.text('네, 좋아요'), findsNothing);
      expect(f.recorder.calls, isNot(contains('start')));

      await tester.tap(find.text('평가 이어서 하기'));
      await tester.pumpAndSettle();

      expect(find.text('평가 $_otherSessionId'), findsOneWidget);
    });
  });
}
