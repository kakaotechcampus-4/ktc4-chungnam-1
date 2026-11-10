// 앱 내 업데이트를 언제 묻고, 언제 다시 시작을 권하는지 확인한다.
//
// 플레이의 앱 내 업데이트는 플레이에서 설치한 앱에서만 동작한다. 여기서는 가짜
// 창구로 순서만 확인하고, 실제 안내 창은 내부 테스트 트랙에서 확인한다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/data/card_api.dart';
import 'package:saerok/data/mock_repository.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/design/tokens.dart';
import 'package:saerok/features/app_update/app_update.dart';
import 'package:saerok/features/app_update/app_update_watcher.dart';
import 'package:saerok/features/cards/card_generation_controller.dart';
import 'package:saerok/features/cards/cards_screen.dart';
import 'package:saerok/features/visit/visit_photos.dart';
import 'package:saerok/widgets/app_buttons.dart';
import 'package:saerok/widgets/app_scaffold.dart';

import 'fake_card_api.dart';
import 'fake_visit_photos.dart';
import 'sample_profile.dart';

/// 미리 읽어 둔 목 묶음을 돌려준다. 테스트 안에서 자산을 읽으면 끝나지 않는다.
class _PreloadedCardApi extends FakeCardApi {
  _PreloadedCardApi(this.set);

  final CardSet set;

  @override
  Future<CardSet> current(String profileId) async => set;
}

class FakeAppUpdateGateway implements AppUpdateGateway {
  FakeAppUpdateGateway({this.status = AppUpdateStatus.none});

  AppUpdateStatus status;

  /// 확인할 때 던질 예외.
  Object? checkError;

  /// [download] 가 돌려줄 결과. 테스트가 원하는 때에 끝낸다.
  Completer<bool> downloading = Completer<bool>();

  int checks = 0;
  int downloads = 0;
  int installs = 0;

  @override
  Future<AppUpdateStatus> check() async {
    checks++;
    final error = checkError;
    if (error != null) throw error;
    return status;
  }

  @override
  Future<bool> download() {
    downloads++;
    return downloading.future;
  }

  @override
  Future<void> install() async => installs++;
}

void main() {
  group('AppUpdateController', () {
    late FakeAppUpdateGateway gateway;
    late ProviderContainer container;

    setUp(() {
      gateway = FakeAppUpdateGateway();
      container = ProviderContainer(
        overrides: [appUpdateGatewayProvider.overrideWithValue(gateway)],
      );
    });

    tearDown(() => container.dispose());

    AppUpdateController controller() =>
        container.read(appUpdateControllerProvider.notifier);

    AppUpdateState update() => container.read(appUpdateControllerProvider);

    test('새 버전이 있으면 한 번만 묻고, 다 받으면 준비됨이 된다', () async {
      gateway.status = AppUpdateStatus.available;

      await controller().check();
      await controller().check();
      expect(gateway.downloads, 1, reason: '한 번 실행에 안내 창은 한 번만 띄운다');
      expect(update().downloaded, isFalse);

      gateway.downloading.complete(true);
      await pumpEventQueue();
      expect(update().downloaded, isTrue);
    });

    test('보호자가 거절하면 이번 실행에서는 다시 묻지 않는다', () async {
      gateway.status = AppUpdateStatus.available;

      await controller().check();
      gateway.downloading.complete(false);
      await pumpEventQueue();
      await controller().check();

      expect(gateway.downloads, 1);
      expect(update().downloaded, isFalse);
    });

    test('받다가 실패하면 다음 확인 때 다시 묻는다', () async {
      gateway.status = AppUpdateStatus.available;

      await controller().check();
      gateway.downloading.completeError(Exception('network'));
      await pumpEventQueue();

      gateway.downloading = Completer<bool>();
      await controller().check();
      expect(gateway.downloads, 2);
    });

    test('묻지 말라고 하면 미뤘다가 다음 확인 때 묻는다', () async {
      gateway.status = AppUpdateStatus.available;

      await controller().check(mayAsk: false);
      expect(gateway.downloads, 0);

      await controller().check();
      expect(gateway.downloads, 1);
    });

    test('이미 받아 둔 새 버전이 있으면 묻지 않고 바로 준비됨이 된다', () async {
      gateway.status = AppUpdateStatus.downloaded;

      await controller().check();

      expect(gateway.downloads, 0);
      expect(update().downloaded, isTrue);
    });

    test('새 버전이 없거나 확인하지 못하면 아무것도 하지 않는다', () async {
      await controller().check();
      gateway.checkError = Exception('not installed from Play');
      await controller().check();

      expect(gateway.checks, 2);
      expect(gateway.downloads, 0);
      expect(update().downloaded, isFalse);
    });

    test('서버와 맞지 않는 실패가 나면 새 버전을 다시 확인하고, 있으면 업데이트가 필요해진다', () async {
      // 앱을 켤 때는 새 버전이 없었다.
      await controller().check();
      gateway.status = AppUpdateStatus.available;

      await controller().suspectOutdated();

      expect(gateway.checks, 2);
      expect(update().needed, isTrue);
      expect(update().newerVersion, isTrue);
      expect(gateway.downloads, 0, reason: '안내 창은 보호자가 업데이트를 누를 때 띄운다');
    });

    test('새 버전이 없으면 실패가 나도 업데이트가 필요하다고 하지 않는다', () async {
      await controller().suspectOutdated();
      gateway.checkError = Exception('not installed from Play');
      await controller().suspectOutdated();

      expect(update().needed, isFalse);
    });

    test('서버가 업데이트를 요구하면 새 버전을 찾지 못해도 필요해진다', () async {
      await controller().suspectOutdated(certain: true);

      expect(update().needed, isTrue);
      expect(update().newerVersion, isFalse);
    });

    test('업데이트를 누르면 앞서 거절했어도 다시 묻는다', () async {
      gateway.status = AppUpdateStatus.available;
      await controller().check();
      gateway.downloading.complete(false);
      await pumpEventQueue();

      gateway.downloading = Completer<bool>();
      final requesting = controller().requestUpdate();
      await pumpEventQueue();
      expect(gateway.downloads, 2);

      gateway.downloading.complete(true);
      await requesting;
      expect(update().downloaded, isTrue);
    });
  });

  group('AppUpdateWatcher', () {
    late GoRouter router;

    Future<FakeAppUpdateGateway> pumpApp(
      WidgetTester tester, {
      required AppUpdateStatus status,
      String initialLocation = AppRoutes.home,
    }) async {
      final gateway = FakeAppUpdateGateway(status: status);
      router = GoRouter(
        initialLocation: initialLocation,
        routes: [
          for (final path in [
            AppRoutes.home,
            AppRoutes.cards,
            AppRoutes.visitPhoto,
            AppRoutes.visitRecord,
            AppRoutes.visitReview,
            AppRoutes.visitReviewDone,
          ])
            GoRoute(
              path: path,
              builder: (context, state) =>
                  Scaffold(body: Center(child: Text(path))),
            ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appUpdateGatewayProvider.overrideWithValue(gateway)],
          child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) =>
                AppUpdateWatcher(router: router, child: child!),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return gateway;
    }

    /// 면회 흐름을 실제 앱처럼 쌓아 올린다.
    Future<void> startVisit(WidgetTester tester) async {
      router.go(AppRoutes.cards);
      await tester.pumpAndSettle();
      for (final path in [
        AppRoutes.visitPhoto,
        AppRoutes.visitRecord,
        AppRoutes.visitReview,
      ]) {
        router.push(path);
        await tester.pumpAndSettle();
      }
    }

    Future<void> finishVisit(WidgetTester tester) async {
      router.go(AppRoutes.visitReviewDone);
      await tester.pumpAndSettle();
      router.go(AppRoutes.home);
      await tester.pumpAndSettle();
    }

    testWidgets('앱을 켤 때 받아 둔 새 버전이 있으면 다시 시작을 권한다', (tester) async {
      final gateway = await pumpApp(tester, status: AppUpdateStatus.downloaded);

      expect(gateway.checks, 1);
      expect(find.text(AppUpdateMessages.ready), findsOneWidget);

      await tester.tap(find.text(AppUpdateMessages.restart));
      await tester.pumpAndSettle();
      expect(gateway.installs, 1);
    });

    testWidgets('뒤에서 다 받으면 그때 알린다', (tester) async {
      final gateway = await pumpApp(tester, status: AppUpdateStatus.available);
      expect(gateway.downloads, 1);
      expect(find.text(AppUpdateMessages.ready), findsNothing);

      gateway.downloading.complete(true);
      await tester.pumpAndSettle();
      expect(find.text(AppUpdateMessages.ready), findsOneWidget);
    });

    testWidgets('알림을 닫으면 앱에 다시 돌아올 때 다시 권한다', (tester) async {
      final gateway = await pumpApp(tester, status: AppUpdateStatus.downloaded);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text(AppUpdateMessages.ready), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(gateway.checks, 2);
      expect(find.text(AppUpdateMessages.ready), findsOneWidget);
      expect(gateway.installs, 0, reason: '다시 시작은 보호자가 누를 때만 한다');
    });

    testWidgets('면회 중에 다 받으면 미뤘다가 홈에 돌아왔을 때 알린다', (tester) async {
      final gateway = await pumpApp(tester, status: AppUpdateStatus.available);
      await startVisit(tester);

      gateway.downloading.complete(true);
      await tester.pumpAndSettle();
      expect(find.text(AppUpdateMessages.ready), findsNothing);

      router.go(AppRoutes.visitReviewDone);
      await tester.pumpAndSettle();
      expect(
        find.text(AppUpdateMessages.ready),
        findsNothing,
        reason: '위로 화면도 면회 흐름이다',
      );

      router.go(AppRoutes.home);
      await tester.pumpAndSettle();
      expect(find.text(AppUpdateMessages.ready), findsOneWidget);
      expect(gateway.installs, 0);
    });

    testWidgets('알림을 띄운 채 면회를 시작하면 닫고 홈에서 다시 권한다', (tester) async {
      await pumpApp(tester, status: AppUpdateStatus.downloaded);
      expect(find.text(AppUpdateMessages.ready), findsOneWidget);

      await startVisit(tester);
      expect(find.text(AppUpdateMessages.ready), findsNothing);

      await finishVisit(tester);
      expect(find.text(AppUpdateMessages.ready), findsOneWidget);
    });

    testWidgets('면회 중에 앱에 돌아오면 안내 창을 띄우지 않고 홈에서 묻는다', (tester) async {
      final gateway = await pumpApp(tester, status: AppUpdateStatus.none);
      await startVisit(tester);

      gateway.status = AppUpdateStatus.available;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(gateway.downloads, 0, reason: '녹음 화면을 플레이 안내 창이 가리지 않는다');

      await finishVisit(tester);
      expect(gateway.downloads, 1);
    });

    testWidgets('면회 흐름 밖의 화면에서는 홈이 아니어도 바로 알린다', (tester) async {
      await pumpApp(
        tester,
        status: AppUpdateStatus.downloaded,
        initialLocation: AppRoutes.cards,
      );

      expect(find.text(AppUpdateMessages.ready), findsOneWidget);
    });

    AppUpdateController controllerOf(WidgetTester tester) =>
        ProviderScope.containerOf(
          tester.element(find.byType(AppUpdateWatcher)),
        ).read(appUpdateControllerProvider.notifier);

    testWidgets('업데이트가 필요해 보이면 알리고, 누르면 받은 뒤 다시 시작을 권한다', (tester) async {
      final gateway = await pumpApp(tester, status: AppUpdateStatus.none);
      gateway.status = AppUpdateStatus.available;

      await controllerOf(tester).suspectOutdated();
      await tester.pumpAndSettle();
      expect(find.text(AppUpdateMessages.needed), findsOneWidget);

      await tester.tap(find.text(AppUpdateMessages.update));
      await tester.pumpAndSettle();
      expect(gateway.downloads, 1);

      gateway.downloading.complete(true);
      await tester.pumpAndSettle();
      expect(find.text(AppUpdateMessages.neededReady), findsOneWidget);

      await tester.tap(find.text(AppUpdateMessages.restart));
      await tester.pumpAndSettle();
      expect(gateway.installs, 1);
    });

    testWidgets('면회 중에 업데이트가 필요해 보여도 띄우지 않고 홈에서 업데이트를 권한다', (tester) async {
      final gateway = await pumpApp(tester, status: AppUpdateStatus.none);
      await startVisit(tester);
      gateway.status = AppUpdateStatus.available;

      await controllerOf(tester).suspectOutdated();
      await tester.pumpAndSettle();
      expect(
        find.byIcon(Icons.close),
        findsNothing,
        reason: '면회 화면에는 알림을 띄우지 않는다',
      );
      expect(find.textContaining('새 버전'), findsNothing);
      expect(gateway.downloads, 0);

      await finishVisit(tester);
      expect(find.text(AppUpdateMessages.needed), findsOneWidget);
      expect(find.text(AppUpdateMessages.update), findsOneWidget);
    });

    testWidgets('서버가 업데이트를 요구해도 면회 중에는 띄우지 않고 홈에서 스토어를 안내한다', (tester) async {
      await pumpApp(tester, status: AppUpdateStatus.none);
      await startVisit(tester);

      await controllerOf(tester).suspectOutdated(certain: true);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.textContaining('새 버전'), findsNothing);

      await finishVisit(tester);
      expect(find.text(AppUpdateMessages.neededFromStore), findsOneWidget);
    });

    testWidgets('버튼 없는 알림을 띄운 채 면회를 시작해도 닫고 홈에서 다시 알린다', (tester) async {
      await pumpApp(tester, status: AppUpdateStatus.none);
      await controllerOf(tester).suspectOutdated(certain: true);
      await tester.pumpAndSettle();
      expect(find.text(AppUpdateMessages.neededFromStore), findsOneWidget);

      await startVisit(tester);
      expect(find.text(AppUpdateMessages.neededFromStore), findsNothing);

      await finishVisit(tester);
      expect(find.text(AppUpdateMessages.neededFromStore), findsOneWidget);
    });

    testWidgets('다른 화면이 아래 알림창을 띄워도 업데이트 알림은 닫히지 않는다', (tester) async {
      await pumpApp(tester, status: AppUpdateStatus.downloaded);
      expect(find.text(AppUpdateMessages.ready), findsOneWidget);

      // 화면들은 알림창을 띄우기 전에 떠 있던 알림창을 닫는다.
      ScaffoldMessenger.of(tester.element(find.text(AppRoutes.home)))
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('이야기를 담았어요.')));
      await tester.pumpAndSettle();

      expect(find.text('이야기를 담았어요.'), findsOneWidget);
      expect(find.text(AppUpdateMessages.ready), findsOneWidget);
    });

    testWidgets('화면 낭독기는 알림이 뜨면 읽고 닫기 버튼 이름을 읽는다', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, status: AppUpdateStatus.downloaded);

      expect(
        tester.getSemantics(find.text(AppUpdateMessages.ready)),
        isSemantics(isLiveRegion: true),
      );
      // 화면 맨 위에 있으므로 화면 내용보다 먼저 읽는다.
      final labels = [
        for (final node in tester.semantics.simulatedAccessibilityTraversal())
          if (node.label.isNotEmpty) node.label,
      ];
      expect(
        labels.indexWhere((l) => l.contains(AppUpdateMessages.ready)),
        allOf(
          greaterThanOrEqualTo(0),
          lessThan(labels.indexOf(AppRoutes.home)),
        ),
      );
      final close = find.bySemanticsLabel('알림 닫기');
      expect(close, findsOneWidget);
      expect(
        tester.getSemantics(close),
        isSemantics(isButton: true, hasTapAction: true),
      );

      tester.semantics.tap(find.semantics.byLabel('알림 닫기'));
      await tester.pumpAndSettle();
      expect(find.text(AppUpdateMessages.ready), findsNothing);
      handle.dispose();
    });

    testWidgets('서버가 업데이트를 요구했는데 받을 새 버전이 없으면 스토어를 안내한다', (tester) async {
      await pumpApp(tester, status: AppUpdateStatus.none);

      await controllerOf(tester).suspectOutdated(certain: true);
      await tester.pumpAndSettle();

      expect(find.text(AppUpdateMessages.neededFromStore), findsOneWidget);
      expect(find.text(AppUpdateMessages.update), findsNothing);
    });

    testWidgets('새 버전이 없으면 실패가 나도 아무것도 띄우지 않는다', (tester) async {
      await pumpApp(tester, status: AppUpdateStatus.none);

      await controllerOf(tester).suspectOutdated();
      await tester.pumpAndSettle();

      expect(find.byType(AppUpdateBanner), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  // 카드 고르기의 `대화 시작하기` 는 화면 아래에 있다. 예전 알림 줄은 아래에 떠서
  // 이 버튼을 덮었다(UX 점검 2026-11-10, 10번). 글자 1.3배는 이 화면의 `최대
  // 9개까지` 줄이 이 변경 전부터 넘쳐(UX 점검 12번) 아래 그룹에서 같은 모양의
  // 화면으로 본다.
  group('카드 화면의 업데이트 알림', () {
    late CardSet mockSet;

    setUpAll(() async {
      mockSet = await const MockRepository().loadCardSet();
    });

    Future<void> openCards(
      WidgetTester tester, {
      required Size size,
      FakeAppUpdateGateway? gateway,
    }) async {
      tester.view.physicalSize = size * 3;
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
            path: AppRoutes.visitPhoto,
            builder: (context, state) =>
                const Scaffold(body: Center(child: Text(AppRoutes.visitPhoto))),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            withSampleProfile,
            cardApiProvider.overrideWithValue(_PreloadedCardApi(mockSet)),
            visitPhotosProvider.overrideWith((ref) => FakeVisitPhotos()),
            serverProfileIdProvider.overrideWith(
              (ref) async => 'server-profile-1',
            ),
            cardPollIntervalProvider.overrideWithValue(Duration.zero),
            appUpdateGatewayProvider.overrideWithValue(
              gateway ??
                  FakeAppUpdateGateway(status: AppUpdateStatus.downloaded),
            ),
          ],
          child: MaterialApp.router(
            theme: buildAppTheme(),
            routerConfig: router,
            builder: (context, child) =>
                AppUpdateWatcher(router: router, child: child!),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final size in const [Size(360, 640), Size(390, 844)]) {
      final tag = '${size.width.toInt()}x${size.height.toInt()}';

      testWidgets('알림이 떠도 대화 시작하기를 가리지 않고, 면회를 시작하면 닫는다 ($tag)', (
        tester,
      ) async {
        await openCards(tester, size: size);
        final toggle = find.bySemanticsLabel(
          cardSelectLabel(mockSet.cards.first.cardTitle),
        );
        await tester.ensureVisible(toggle);
        await tester.pumpAndSettle();
        await tester.tap(toggle);
        await tester.pumpAndSettle();

        final notice = find.text(AppUpdateMessages.ready);
        final start = find.text('대화 시작하기');
        expect(notice, findsOneWidget);
        expect(start.hitTestable(), findsOneWidget, reason: '알림이 버튼을 덮지 않는다');
        expect(
          tester.getRect(notice).bottom,
          lessThanOrEqualTo(tester.getRect(find.byType(AppBar)).top),
          reason: '알림은 상단바 위, 화면 맨 위에 둔다',
        );

        await tester.tap(start);
        await tester.pumpAndSettle();
        expect(find.text(AppRoutes.visitPhoto), findsOneWidget);
        expect(notice, findsNothing, reason: '면회 화면에는 띄우지 않는다');
      });
    }

    testWidgets('카드를 고른 뒤 알림이 떠도 고른 카드가 남는다', (tester) async {
      final gateway = FakeAppUpdateGateway(status: AppUpdateStatus.available);
      await openCards(tester, size: const Size(360, 640), gateway: gateway);
      expect(find.text(AppUpdateMessages.ready), findsNothing);
      await tester.tap(
        find.bySemanticsLabel(cardSelectLabel(mockSet.cards.first.cardTitle)),
      );
      await tester.pumpAndSettle();
      expect(find.text('1개 선택함'), findsOneWidget);

      gateway.downloading.complete(true);
      await tester.pumpAndSettle();

      expect(find.text(AppUpdateMessages.ready), findsOneWidget);
      expect(find.text('1개 선택함'), findsOneWidget, reason: '화면을 새로 만들지 않는다');

      await tester.tap(find.bySemanticsLabel('알림 닫기'));
      await tester.pumpAndSettle();
      expect(find.text(AppUpdateMessages.ready), findsNothing);
      expect(find.text('1개 선택함'), findsOneWidget);
    });
  });

  // 가장 긴 문구와 버튼이 함께 뜨는 경우다. 카드 고르기처럼 위에 상단바, 아래에
  // 주 버튼이 있는 화면에 띄운다.
  group('글자를 키운 화면의 업데이트 알림', () {
    for (final size in const [Size(360, 640), Size(390, 844)]) {
      final tag = '${size.width.toInt()}x${size.height.toInt()}';

      testWidgets('글자 1.3배에서도 알림이 넘치지 않고 아래 주 버튼을 가리지 않는다 ($tag)', (
        tester,
      ) async {
        tester.view.physicalSize = size * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        var started = 0;
        final gateway = FakeAppUpdateGateway();
        final router = GoRouter(
          initialLocation: AppRoutes.cards,
          routes: [
            GoRoute(
              path: AppRoutes.cards,
              builder: (context, state) => Scaffold(
                appBar: const AppTopBar(title: '오늘의 대화 카드'),
                body: ScreenBody(
                  scrollable: true,
                  bottom: PrimaryButton(
                    label: '대화 시작하기',
                    onPressed: () => started++,
                  ),
                  child: const Text('카드 목록', style: AppTypography.body),
                ),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [appUpdateGatewayProvider.overrideWithValue(gateway)],
            child: MaterialApp.router(
              theme: buildAppTheme(),
              routerConfig: router,
              builder: (context, child) =>
                  AppUpdateWatcher(router: router, child: child!),
            ),
          ),
        );
        await tester.pumpAndSettle();

        gateway.status = AppUpdateStatus.available;
        await ProviderScope.containerOf(
          tester.element(find.byType(AppUpdateWatcher)),
        ).read(appUpdateControllerProvider.notifier).suspectOutdated();
        await tester.pumpAndSettle();

        expect(find.text(AppUpdateMessages.needed), findsOneWidget);
        expect(
          find.text(AppUpdateMessages.update).hitTestable(),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel('알림 닫기').hitTestable(), findsOneWidget);
        expect(
          tester.getRect(find.byType(AppBar)).top,
          greaterThanOrEqualTo(
            tester.getRect(find.text(AppUpdateMessages.needed)).bottom,
          ),
        );

        await tester.tap(find.text('대화 시작하기'));
        await tester.pump();
        expect(started, 1, reason: '알림이 버튼을 덮지 않는다');
      });
    }
  });
}
