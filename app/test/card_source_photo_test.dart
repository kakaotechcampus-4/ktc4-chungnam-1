// 사진에서 나온 카드(`evidenceSource: photo`)에 그 사진을 붙이는지 확인한다.
//
// 2026-11-10 E2E 에서 `이 사진은 어디서 찍으셨어요?` 카드가 카드 목록, 질문 면,
// 면회 중 카드 시트 어디에도 사진 없이 나왔다. 카드 고르기(C), 면회 중 카드
// 추가(E-5), 면회 중 카드 시트(E-3) 세 곳을 본다. 사진은 앱에 든 합성 그림이고
// 값은 모두 합성이다.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/data/auth_api.dart';
import 'package:saerok/data/card_api.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/data/visit_api.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/auth/auth_providers.dart';
import 'package:saerok/features/auth/auth_session.dart';
import 'package:saerok/features/cards/card_generation_controller.dart';
import 'package:saerok/features/cards/card_source_photo.dart';
import 'package:saerok/features/cards/cards_controller.dart';
import 'package:saerok/features/cards/cards_screen.dart';
import 'package:saerok/features/visit/add_cards_screen.dart';
import 'package:saerok/features/visit/pending_uploads.dart';
import 'package:saerok/features/visit/visit_cards_sheet.dart';
import 'package:saerok/features/visit/visit_controller.dart';
import 'package:saerok/features/visit/visit_photos.dart';
import 'package:saerok/features/visit/visit_recorder.dart';

import 'fake_card_api.dart';
import 'fake_pending_uploads.dart';
import 'fake_profile_server.dart';
import 'fake_visit_api.dart';
import 'fake_visit_photos.dart';
import 'fake_visit_recorder.dart';
import 'sample_profile.dart';

const _asset = 'assets/images/family.webp';

/// 12장 묶음. [photo] 에 든 순서의 카드는 사진 `photo_test_<순서>` 에서 나왔다.
CardSet _set({
  Set<int> photo = const {},
  String question = '이 사진은 어디서 찍으셨어요?',
}) => CardSet(
  setId: 'set_test_001',
  usedBySessionId: null,
  cards: [
    for (var p = 1; p <= 12; p++)
      ConversationCard(
        cardId: 'card_test_$p',
        position: p,
        topic: CardTopic(
          topicId: 'topic_test_$p',
          title: '합성 주제 $p',
          description: '합성 주제 설명',
        ),
        cardTitle: '합성 카드 $p',
        description: '합성 카드 설명 $p',
        primaryQuestion: question,
        followUpQuestions: const ['합성 꼬리 질문'],
        evidenceSource: photo.contains(p) ? 'photo' : 'none',
        evidence: photo.contains(p)
            ? [
                {'photoId': 'photo_test_$p'},
              ]
            : const [],
        selected: false,
      ),
  ],
);

class _ReadyCardApi extends FakeCardApi {
  _ReadyCardApi(this.set) : super(statuses: [CardGenerationStatus.ready]);

  final CardSet set;

  @override
  Future<CardSet> current(String profileId) async => set;
}

List<Override> _overrides(CardSet set, Map<String, String> urls) => [
  withSampleProfile,
  serverProfileIdProvider.overrideWith((ref) async => 'server-profile-1'),
  cardApiProvider.overrideWithValue(_ReadyCardApi(set)),
  cardPollIntervalProvider.overrideWithValue(Duration.zero),
  currentCardSetProvider.overrideWith((ref) async => set),
  // 새 Map 으로 돌려줘야 다시 읽었을 때 화면이 바뀐 값을 받는다.
  cardPhotoUrlsProvider.overrideWithBuild((ref, notifier) async => {...urls}),
];

/// 화면의 그림을 실제로 읽어 그린다. 그림 읽기는 테스트의 가짜 시간 밖에서 돈다.
Future<void> _loadImages(WidgetTester tester) async {
  // 경로 전환 뒤 최종 화면 크기로 사진을 푼다. 로딩 표시가 도는 동안 settle하지 않는다.
  await tester.pump(const Duration(milliseconds: 500));
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      final image = element.widget as Image;
      await precacheImage(image.image, element, onError: (error, stack) {});
    }
    // 주소가 열리지 않는 경우의 실패도 이 사이에 도착한다.
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  await tester.pumpAndSettle();
}

Future<void> _openCards(
  WidgetTester tester,
  CardSet set, {
  Map<String, String> urls = const {},
  String location = AppRoutes.cards,
  double textScale = 1,
}) async {
  // 기준 화면 412 x 917 dp 다(`app/README.md`).
  tester.view.physicalSize = const Size(1236, 2751);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  final container = ProviderContainer(overrides: _overrides(set, urls));
  addTearDown(container.dispose);
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: AppRoutes.cards,
        builder: (context, state) => const CardsScreen(),
      ),
      GoRoute(
        path: AppRoutes.visitAddCards,
        builder: (context, state) => const AddCardsScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await _loadImages(tester);
}

/// [title] 카드 안에서 찾는다.
Finder _inCard(String title, Finder finder) => find.descendant(
  of: find.ancestor(of: find.text(title), matching: find.byType(Column)).first,
  matching: finder,
);

Finder get _photo => find.bySemanticsLabel(CardSourcePhoto.semanticLabel);

/// 합성 그림만 저장한다. 지정하지 않으면 파일을 만들지 않는다.
Future<void> _capture(WidgetTester tester, String name) async {
  final output = Platform.environment['SAEROK_SYNTHETIC_CAPTURE_DIR'];
  if (output == null) return;
  final root = tester.binding.renderViews.first;
  final layer = root.debugLayer! as OffsetLayer;
  await tester.runAsync(() async {
    final ratio = tester.view.devicePixelRatio;
    final image = await layer.toImage(
      Offset.zero & (root.size * ratio),
      pixelRatio: 1 / ratio,
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(output).create(recursive: true);
    await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    final font = Platform.environment['SAEROK_CAPTURE_FONT'];
    if (font != null) {
      TestWidgetsFlutterBinding.ensureInitialized();
      final bytes = await File(font).readAsBytes();
      final boldFont = Platform.environment['SAEROK_CAPTURE_BOLD_FONT'];
      for (final family in ['Roboto', 'Ahem']) {
        final loader = FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(bytes)));
        if (boldFont != null) {
          loader.addFont(
            File(boldFont).readAsBytes().then(ByteData.sublistView),
          );
        }
        await loader.load();
      }
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });
  group('카드 고르기', () {
    testWidgets('사진 카드는 제목 위에 그 사진을 보여준다', (tester) async {
      await _openCards(
        tester,
        _set(photo: {2}),
        urls: {'photo_test_2': 'asset:$_asset'},
      );

      expect(_inCard('합성 카드 2', find.byType(Image)), findsOneWidget);
      expect(_inCard('합성 카드 1', find.byType(Image)), findsNothing);
      final image = tester.widget<Image>(find.byType(Image));
      final resized = image.image as ResizeImage;
      expect((resized.imageProvider as AssetImage).assetName, _asset);
      // 원본을 그대로 풀지 않고 그리는 가장 큰 높이(120 x 기기 배율 3)로 푼다.
      expect(resized.height, 360);
      expect(resized.width, isNull);

      final photo = tester.getRect(find.byType(RawImage));
      final title = tester.getRect(find.text('합성 카드 2'));
      expect(photo.bottom, lessThanOrEqualTo(title.top));
      expect(photo.height, greaterThan(0));
      expect(photo.height, lessThanOrEqualTo(120));
      expect(_photo, findsOneWidget);
    });

    testWidgets('사진을 찾지 못하면 안내와 사진 화면으로 가는 버튼을 둔다', (tester) async {
      await _openCards(
        tester,
        _set(photo: {2}),
        urls: {'photo_test_9': 'asset:$_asset'},
      );

      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
      expect(find.text('합성 카드 2'), findsOneWidget);
      expect(find.text('이 카드의 사진을 찾을 수 없어요'), findsOneWidget);
    });

    testWidgets('주소가 열리지 않으면 상태 안내를 누를 수 있다', (tester) async {
      await _openCards(
        tester,
        _set(photo: {2}),
        urls: {'photo_test_2': 'https://example.invalid/expired.jpg'},
      );

      expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
      expect(_photo, findsNothing);
      expect(find.text('사진을 열지 못했어요'), findsOneWidget);
      expect(
        tester.getSize(find.byType(Image)).height,
        greaterThanOrEqualTo(48),
      );
    });

    testWidgets('사진을 크게 열고 닫아도 카드 선택은 바뀌지 않는다', (tester) async {
      await _openCards(
        tester,
        _set(photo: {2}),
        urls: {'photo_test_2': 'asset:$_asset'},
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CardsScreen)),
      );
      final before = container.read(cardsControllerProvider);
      await tester.tap(find.byTooltip('사진 크게 보기'));
      await tester.pump();
      await _loadImages(tester);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      final image = tester.widget<Image>(find.byType(Image).last);
      final resized = image.image as ResizeImage;
      expect(resized.height, greaterThan(360));
      expect(resized.width, lessThanOrEqualTo(3072));
      expect(resized.policy, ResizeImagePolicy.fit);
      await tester.tap(find.text('닫기'));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(container.read(cardsControllerProvider), before);
    });

    testWidgets('사진 로딩 실패 뒤 다시 불러오면 새 주소로 표시한다', (tester) async {
      final urls = {'photo_test_2': 'https://example.invalid/expired.jpg'};
      await _openCards(tester, _set(photo: {2}), urls: urls);
      await tester.tap(find.text('사진을 열지 못했어요'));
      await tester.pump();
      await _loadImages(tester);
      expect(find.text('사진 다시 불러오기'), findsOneWidget);
      urls['photo_test_2'] = 'asset:$_asset';
      await tester.tap(find.text('사진 다시 불러오기'));
      await tester.pump();
      await _loadImages(tester);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.text('사진 다시 불러오기'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('사진 확대 후 시스템 뒤로가기로 카드 화면에 돌아온다', (tester) async {
      await _openCards(
        tester,
        _set(photo: {2}),
        urls: {'photo_test_2': 'asset:$_asset'},
      );
      await tester.tap(find.byTooltip('사진 크게 보기'));
      await tester.pump();
      await _loadImages(tester);
      final center = tester.getCenter(find.byType(InteractiveViewer));
      final left = await tester.startGesture(
        center - const Offset(30, 0),
        pointer: 1,
      );
      final right = await tester.startGesture(
        center + const Offset(30, 0),
        pointer: 2,
      );
      await left.moveTo(center - const Offset(90, 0));
      await right.moveTo(center + const Offset(90, 0));
      await tester.pump();
      final transform = tester.widget<Transform>(
        find
            .descendant(
              of: find.byType(InteractiveViewer),
              matching: find.byType(Transform),
            )
            .first,
      );
      expect(transform.transform.getMaxScaleOnAxis(), greaterThan(1));
      await left.up();
      await right.up();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(find.byType(CardsScreen), findsOneWidget);
    });

    testWidgets('사진을 연 동안 로그아웃하면 확대 사진을 가린다', (tester) async {
      final container = ProviderContainer(
        overrides: [
          ..._overrides(_set(photo: {1}), {'photo_test_1': 'asset:$_asset'}),
          sessionProvider.overrideWith(_SignedIn.new),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: CardSourcePhoto(card: _set(photo: {1}).cards.first),
            ),
          ),
        ),
      );
      await _loadImages(tester);
      await tester.tap(find.byTooltip('사진 크게 보기'));
      await tester.pump();
      await _loadImages(tester);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      (container.read(sessionProvider.notifier) as _SignedIn).clearForTest();
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(find.text('계정이나 어르신이 바뀌어 사진을 닫아주세요.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('사진 목록을 기다리는 동안 진행 안내 뒤 사진을 표시한다', (tester) async {
      final ready = Completer<Map<String, String>>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cardPhotoUrlsProvider.overrideWithBuild(
              (ref, notifier) => ready.future,
            ),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: CardSourcePhoto(card: _set(photo: {1}).cards.first),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('사진을 불러오고 있어요'), findsOneWidget);
      ready.complete({'photo_test_1': 'asset:$_asset'});
      await tester.pump();
      await _loadImages(tester);
      expect(find.byTooltip('사진 크게 보기'), findsOneWidget);
    });

    testWidgets('확대 중 어르신을 바꾸면 이전 사진을 가린다', (tester) async {
      final container = ProviderContainer(
        overrides: [
          careProfilesProvider.overrideWith(_ServerProfiles.new),
          cardPhotoUrlsProvider.overrideWithBuild(
            (ref, notifier) async => {'photo_test_1': 'asset:$_asset'},
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: CardSourcePhoto(card: _set(photo: {1}).cards.first),
            ),
          ),
        ),
      );
      await _loadImages(tester);
      await tester.tap(find.byTooltip('사진 크게 보기'));
      await tester.pump();
      await _loadImages(tester);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      container.read(careProfilesProvider.notifier).select('p2');
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(find.text('계정이나 어르신이 바뀌어 사진을 닫아주세요.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // 서버 주소는 다시 읽을 때마다 바뀐다(서명한 임시 주소). 주소로 그림을
    // 기억하면 주소를 새로 받을 때마다 원본을 다시 내려받는다.
    testWidgets('주소가 바뀌어도 같은 사진이면 같은 그림으로 기억한다', (tester) async {
      final urls = {
        'photo_test_2': 'https://example.invalid/a.jpg?sig=1',
        'photo_test_3': 'https://example.invalid/b.jpg?sig=1',
      };
      await _openCards(tester, _set(photo: {2, 3}), urls: urls);
      Image imageOf(String title) =>
          tester.widget<Image>(_inCard(title, find.byType(Image)));
      Future<Object> keyOf(String title) =>
          imageOf(title).image.obtainKey(ImageConfiguration.empty);
      final before = imageOf('합성 카드 2').image;
      final keyBefore = await keyOf('합성 카드 2');
      expect(keyBefore, isNot(await keyOf('합성 카드 3')));

      urls['photo_test_2'] = 'https://example.invalid/a.jpg?sig=2';
      ProviderScope.containerOf(
        tester.element(find.byType(CardsScreen)),
      ).invalidate(cardPhotoUrlsProvider);
      await tester.pumpAndSettle();

      // 새 주소로 다시 열 수 있게 다른 provider 지만, 그림은 같은 것으로 친다.
      expect(imageOf('합성 카드 2').image, isNot(before));
      expect(await keyOf('합성 카드 2'), keyBefore);
    });

    // 카드 고르기 위의 `○개 선택함` 줄은 글자 1.5배부터 넘친다(이 변경 전부터,
    // 412dp, card_sensitive_badge_test.dart). 그래서 같은 카드 틀을 쓰는 카드
    // 추가 화면에서 본다.
  });

  group('면회 중 카드 추가', () {
    testWidgets('글자를 1.5배로 키워도 사진 카드가 넘치지 않는다', (tester) async {
      await _openCards(
        tester,
        _set(photo: {10, 11}),
        urls: {
          'photo_test_10': 'asset:$_asset',
          'photo_test_11': 'asset:$_asset',
        },
        location: AppRoutes.visitAddCards,
        textScale: 1.5,
      );

      expect(tester.takeException(), isNull);
      final photo = tester.getRect(find.byType(RawImage).first);
      final title = tester.getRect(find.text('합성 카드 10'));
      expect(photo.height, greaterThan(0));
      expect(photo.bottom, lessThanOrEqualTo(title.top));
    });

    testWidgets('보충용 사진 카드에도 그 사진을 보여준다', (tester) async {
      await _openCards(
        tester,
        _set(photo: {11}),
        urls: {'photo_test_11': 'asset:$_asset'},
        location: AppRoutes.visitAddCards,
      );

      expect(_inCard('합성 카드 11', find.byType(Image)), findsOneWidget);
      expect(_inCard('합성 카드 10', find.byType(Image)), findsNothing);
    });
  });

  group('면회 중 카드 시트', () {
    /// 고른 카드로 면회 상태를 만들고 카드 시트를 그린다.
    Future<ProviderContainer> openSheet(
      WidgetTester tester, {
      required CardSet set,
      required Map<String, String> urls,
      List<int> cards = const [1],
      Size size = const Size(412, 917),
      double textScale = 1,
    }) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final container = ProviderContainer(
        overrides: [
          ..._overrides(set, urls),
          visitApiProvider.overrideWith((ref) => FakeVisitApi()),
          pendingUploadsProvider.overrideWith((ref) => FakePendingUploads()),
          visitPhotosProvider.overrideWith((ref) => FakeVisitPhotos()),
          visitRecorderProvider.overrideWithValue(FakeVisitRecorder()),
        ],
      );
      addTearDown(container.dispose);
      await tester.runAsync(() async {
        await container.read(cardsControllerProvider.future);
        for (final p in cards) {
          container
              .read(cardsControllerProvider.notifier)
              .toggleSelected('card_test_$p');
        }
        await container.read(visitControllerProvider.future);
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: visitCardsSheetHeightFactor,
                  child: const VisitCardsSheetPreview(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _loadImages(tester);
      return container;
    }

    testWidgets('사진 카드는 질문 밖의 고정 사진 보기 버튼으로 연다', (tester) async {
      await openSheet(
        tester,
        set: _set(photo: {1}),
        urls: {'photo_test_1': 'asset:$_asset'},
      );

      expect(find.text('[ 합성 카드 1 ]'), findsOneWidget);
      final photo = tester.getRect(find.text('사진 보기'));
      final title = tester.getRect(find.text('[ 합성 카드 1 ]'));
      expect(photo.height, greaterThan(0));
      expect(photo.bottom, lessThanOrEqualTo(title.top));
      expect(find.text('사진 보기').hitTestable(), findsOneWidget);
      expect(find.byType(RawImage), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('사진 카드가 아니면 사진을 두지 않는다', (tester) async {
      await openSheet(
        tester,
        set: _set(photo: {2}),
        urls: {'photo_test_2': 'asset:$_asset'},
      );

      expect(find.text('[ 합성 카드 1 ]'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.text('사진 보기'), findsNothing);
    });

    testWidgets('확대 화면은 녹음 상태를 갱신하고 열고 닫기로 녹음기를 조작하지 않는다', (tester) async {
      final container = await openSheet(
        tester,
        set: _set(photo: {1}),
        urls: {'photo_test_1': 'asset:$_asset'},
      );
      final controller = container.read(visitControllerProvider.notifier);
      await tester.runAsync(controller.startRecording);
      await tester.pumpAndSettle();
      final recorder =
          container.read(visitRecorderProvider) as FakeVisitRecorder;
      final callsBefore = List<String>.of(recorder.calls);
      await tester.tap(find.text('사진 보기'));
      await tester.pump();
      await _loadImages(tester);
      expect(find.text('녹음 중'), findsOneWidget);
      expect(find.text('이 사진은 어디서 찍으셨어요?'), findsOneWidget);
      expect(recorder.calls, callsBefore);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1100)),
      );
      await tester.pump();
      expect(
        container.read(visitControllerProvider).requireValue.elapsed.inSeconds,
        greaterThanOrEqualTo(1),
      );
      expect(
        find.text(
          container.read(visitControllerProvider).requireValue.elapsedLabel,
        ),
        findsOneWidget,
      );
      await _capture(tester, 'viewer-recording');
      await controller.pauseRecording();
      await tester.pump();
      expect(find.text('녹음 중 아님'), findsOneWidget);
      expect(find.text('녹음 중'), findsNothing);
      final callsBeforeClose = List<String>.of(recorder.calls);
      await tester.tap(find.text('닫기'));
      await tester.pumpAndSettle();
      expect(recorder.calls, callsBeforeClose);
      expect(tester.takeException(), isNull);
    });

    testWidgets('녹음 시작 실패와 사진 누락도 질문과 함께 알린다', (tester) async {
      final container = await openSheet(
        tester,
        set: _set(photo: {1}),
        urls: {},
      );
      (container.read(visitRecorderProvider) as FakeVisitRecorder).failOnStart =
          true;
      await tester.runAsync(
        container.read(visitControllerProvider.notifier).startRecording,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('사진 보기'));
      await tester.pumpAndSettle();
      expect(find.text('녹음 상태를 확인해 주세요'), findsOneWidget);
      expect(find.text('녹음 중'), findsNothing);
      expect(find.text('이 카드의 사진을 찾을 수 없어요'), findsOneWidget);
      expect(find.text('사진 다시 불러오기').hitTestable(), findsOneWidget);
      expect(find.text('이 사진은 어디서 찍으셨어요?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // 사진 카드를 표시해도 질문 글자를 축소하지 않는다.
    for (final textScale in [1.0, 1.5, 2.0]) {
      testWidgets('글자 $textScale배에서 사진이 메인 질문을 줄이지 않는다', (tester) async {
        // 1번은 사진 카드, 2번은 같은 질문의 사진 없는 카드다.
        final container = await openSheet(
          tester,
          set: _set(photo: {1}),
          urls: {'photo_test_1': 'asset:$_asset'},
          cards: const [1, 2],
          textScale: textScale,
        );
        expect(tester.takeException(), isNull);
        final question = find.text('이 사진은 어디서 찍으셨어요?');
        final withPhoto = tester.getRect(question);
        expect(find.byType(RawImage), findsNothing);
        expect(find.text('사진 보기').hitTestable(), findsOneWidget);

        container.read(visitControllerProvider.notifier).nextCard();
        await tester.pumpAndSettle();
        expect(find.text('[ 합성 카드 2 ]'), findsOneWidget);
        final plain = tester.getRect(question);

        expect(withPhoto.height, closeTo(plain.height, 0.5));
        expect(withPhoto.width, closeTo(plain.width, 0.5));
      });
    }

    testWidgets('긴 질문을 스크롤해도 사진 버튼과 확대 화면 닫기는 남는다', (tester) async {
      const question =
          '사진 속 풍경을 함께 보면서 그곳에서 보내셨던 하루에 대해 편하게 이야기해 주세요. 어떤 일을 하며 시간을 보내셨는지도 궁금해요.';
      await openSheet(
        tester,
        set: _set(photo: {1}, question: question),
        urls: {'photo_test_1': 'asset:$_asset'},
        size: const Size(360, 640),
        textScale: 2,
      );
      await tester.drag(find.text(question), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(find.text('사진 보기').hitTestable(), findsOneWidget);
      await tester.tap(find.text('사진 보기'));
      await tester.pump();
      await _loadImages(tester);
      final scrollable = find
          .ancestor(of: find.text(question), matching: find.byType(Scrollable))
          .first;
      final state = tester.state<ScrollableState>(scrollable);
      expect(state.position.maxScrollExtent, greaterThan(0));
      state.position.jumpTo(state.position.maxScrollExtent);
      await tester.pump();
      expect(state.position.pixels, state.position.maxScrollExtent);
      expect(find.text('닫기').hitTestable(), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await _capture(tester, 'viewer-long-question-360-2.0');
      expect(tester.takeException(), isNull);
    });

    // 가로 화면의 카드 시트는 이 변경 전부터 위아래 칸이 모두 넘친다. 그래서 낮은
    // 세로 화면으로 본다.
    testWidgets('칸이 낮으면 사진 대신 사진 보기 버튼을 둔다', (tester) async {
      await openSheet(
        tester,
        set: _set(photo: {1}),
        urls: {'photo_test_1': 'asset:$_asset'},
        size: const Size(412, 560),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(Image), findsNothing);
      expect(find.text('이 사진은 어디서 찍으셨어요?'), findsOneWidget);
      expect(find.text('사진 보기'), findsOneWidget);
    });

    for (final size in [
      const Size(360, 640),
      const Size(390, 844),
      const Size(412, 917),
    ]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        testWidgets('사진 보기와 복귀 ${size.width}x${size.height} 글자 $scale', (
          tester,
        ) async {
          final container = await openSheet(
            tester,
            set: _set(photo: {1}),
            urls: {'photo_test_1': 'asset:$_asset'},
            size: size,
            textScale: scale,
          );
          final before = container.read(visitControllerProvider);
          expect(tester.takeException(), isNull);
          await _capture(tester, 'sheet-${size.width.toInt()}-$scale');
          final open = find.text('사진 보기');
          expect(open.hitTestable(), findsOneWidget);
          await tester.tap(open);
          await tester.pump();
          await _loadImages(tester);
          expect(find.byType(InteractiveViewer), findsOneWidget);
          expect(find.text('이 사진은 어디서 찍으셨어요?'), findsOneWidget);
          expect(find.text('녹음 전'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _capture(tester, 'viewer-${size.width.toInt()}-$scale');
          await tester.tap(find.text('닫기'));
          await tester.pumpAndSettle();
          expect(container.read(visitControllerProvider), before);
          expect(find.text('[ 합성 카드 1 ]'), findsOneWidget);
        });
      }
    }
  });

  // 카드 화면은 녹음 화면 아래에 열린 채 남아 면회(60~90분) 내내 사진 주소를
  // 들고 있다. 서버 주소는 15분이면 만료된다.
  group('사진 주소 다시 읽기', () {
    /// 서버의 분 p1 을 고르고 로그인한 컨테이너. 사진 주소를 보는 화면이 있다.
    ProviderContainer signedIn(FakeProfileServer server, {Duration? margin}) {
      final container = ProviderContainer(
        overrides: [
          server.override,
          sessionProvider.overrideWith(_SignedIn.new),
          careProfilesProvider.overrideWith(_ServerProfiles.new),
          if (margin != null)
            cardPhotoUrlMarginProvider.overrideWithValue(margin),
        ],
      );
      addTearDown(container.dispose);
      container.listen(cardPhotoUrlsProvider, (_, _) {});
      return container;
    }

    int reads(FakeProfileServer server) => server.requests
        .where((r) => r.method == 'GET' && r.path == '/api/v1/profiles/p1')
        .length;

    /// 지금부터 [after] 뒤에 만료되는 사진 [id]. [after] 가 없으면 만료 시각이
    /// 없다.
    Map<String, Object?> photo(String id, Duration? after) => {
      ...FakeProfileServer.photo(id: id),
      'imageUrlExpiresAt': after == null
          ? null
          : DateTime.now().add(after).toUtc().toIso8601String(),
    };

    FakeProfileServer serverWith(List<Map<String, Object?>> photos) =>
        FakeProfileServer(
          profiles: [FakeProfileServer.profile(id: 'p1', photos: photos)],
        );

    testWidgets('가장 먼저 만료되는 주소보다 1분 먼저 다시 읽는다', (tester) async {
      final server = serverWith([
        photo('photo_a', const Duration(minutes: 20)),
        photo('photo_b', const Duration(minutes: 15)),
      ]);
      final container = signedIn(server);
      await tester.pump();
      expect(container.read(cardPhotoUrlsProvider).value, {
        'photo_a': 'https://example.test/photo_a.jpg',
        'photo_b': 'https://example.test/photo_b.jpg',
      });
      expect(reads(server), 1);

      await tester.pump(const Duration(minutes: 13, seconds: 50));
      expect(reads(server), 1);
      await tester.pump(const Duration(seconds: 20));
      expect(reads(server), 2);
      expect(container.read(cardPhotoUrlsProvider).value, hasLength(2));
      container.dispose();
    });

    testWidgets('휴대폰 시계가 어긋나 이미 만료됐다고 나와도 1분보다 자주 읽지 않는다', (tester) async {
      final server = serverWith([
        photo('photo_a', const Duration(minutes: -30)),
      ]);
      final container = signedIn(server);
      await tester.pump();
      await tester.pump(const Duration(seconds: 50));
      expect(reads(server), 1);
      await tester.pump(const Duration(seconds: 20));
      expect(reads(server), 2);
      container.dispose();
    });

    testWidgets('연결이 끊겨 읽지 못하면 1분 뒤에 다시 읽는다', (tester) async {
      final server = serverWith([photo('photo_a', const Duration(minutes: 15))])
        ..offline = true;
      final container = signedIn(server);
      await tester.pump();
      expect(container.read(cardPhotoUrlsProvider).hasError, isTrue);

      server.offline = false;
      await tester.pump(const Duration(seconds: 50));
      expect(reads(server), 1);
      await tester.pump(const Duration(seconds: 20));
      expect(reads(server), 2);
      expect(container.read(cardPhotoUrlsProvider).value, {
        'photo_a': 'https://example.test/photo_a.jpg',
      });
      container.dispose();
    });

    testWidgets('그림을 열지 못하면 받은 지 오래된 주소일 때만 한 번 다시 읽는다', (tester) async {
      final server = serverWith([
        photo('photo_a', null),
        photo('photo_b', null),
      ]);
      final container = signedIn(
        server,
        margin: const Duration(milliseconds: 50),
      );
      await tester.pump();
      final notifier = container.read(cardPhotoUrlsProvider.notifier);
      const a = 'https://example.test/photo_a.jpg';
      const b = 'https://example.test/photo_b.jpg';

      // 갓 받은 주소로 열지 못했으면 다시 읽어도 같다.
      // 다시 읽기는 다음 차례에 시작하므로 Duration.zero 로 넘긴다.
      notifier.imageFailed(a);
      await tester.pump(Duration.zero);
      expect(reads(server), 1);

      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      // 이미 알린 주소는 화면이 다시 그려져 또 알려도 보지 않는다.
      notifier.imageFailed(a);
      await tester.pump(Duration.zero);
      expect(reads(server), 1);

      notifier.imageFailed(b);
      await tester.pump(Duration.zero);
      expect(reads(server), 2);
      container.dispose();
    });

    testWidgets('카드의 사진을 열지 못하면 주소를 한 번 다시 읽는다', (tester) async {
      final server = serverWith([photo('photo_test_1', null)]);
      // 받은 지 얼마 안 된 주소도 다시 읽게 해 화면에서 알리는지만 본다.
      final container = signedIn(server, margin: Duration.zero);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: CardSourcePhoto(card: _set(photo: {1}).cards.first),
            ),
          ),
        ),
      );
      await tester.pump(Duration.zero);
      expect(find.byType(Image), findsOneWidget);
      expect(reads(server), 1);

      // 테스트의 주소는 열리지 않는다. 같은 주소가 다시 와 다시 그려도 또
      // 읽지 않는다.
      await _loadImages(tester);
      expect(reads(server), 2);
      expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
      expect(_photo, findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

class _SignedIn extends SessionNotifier {
  void clearForTest() => state = null;

  @override
  AuthSession? build() => AuthSession(
    accessToken: 'token',
    tokenType: 'Bearer',
    expiresAt: DateTime(2100),
    account: const AuthAccount(
      accountId: 'account-a',
      authProvider: 'google',
      displayName: '테스트 보호자',
      email: null,
      consentVersion: null,
      createdAt: null,
    ),
  );
}

class _ServerProfiles extends CareProfilesNotifier {
  @override
  CareProfiles build() => const CareProfiles(
    entries: [
      CareProfileEntry(id: 'p1', basicInfo: sampleBasicInfo, remoteId: 'p1'),
      CareProfileEntry(id: 'p2', basicInfo: sampleBasicInfo, remoteId: 'p2'),
    ],
    selectedId: 'p1',
  );
}
