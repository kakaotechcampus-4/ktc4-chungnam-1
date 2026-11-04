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
import 'package:saerok/features/app_update/app_update.dart';
import 'package:saerok/features/app_update/app_update_watcher.dart';

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

    testWidgets('면회 중에 업데이트가 필요해 보이면 알리기만 하고 홈에서 업데이트를 권한다', (tester) async {
      final gateway = await pumpApp(tester, status: AppUpdateStatus.none);
      await startVisit(tester);
      gateway.status = AppUpdateStatus.available;

      await controllerOf(tester).suspectOutdated();
      await tester.pumpAndSettle();
      expect(find.text(AppUpdateMessages.neededInVisit), findsOneWidget);
      expect(find.text(AppUpdateMessages.update), findsNothing);
      expect(gateway.downloads, 0);

      await finishVisit(tester);
      expect(find.text(AppUpdateMessages.neededInVisit), findsNothing);
      expect(find.text(AppUpdateMessages.needed), findsOneWidget);
      expect(find.text(AppUpdateMessages.update), findsOneWidget);
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

      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
