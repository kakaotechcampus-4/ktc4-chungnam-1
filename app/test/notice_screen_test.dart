// 알림 화면과 홈의 알림 아이콘 연결을 확인한다.
//
// 지금은 홈의 리포트 알림 상태(`ReportNotice`) 한 건만 다시 보여주는
// 화면이다. `home_notice_test.dart` 가 홈 배너 자체를 다루므로 여기서는
// 화면 이동과 이 화면의 상태 표시만 본다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/app/router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/data/mock_repository.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/design/theme.dart';

/// 리포트 도착 시점을 테스트가 직접 정하는 저장소다. `home_notice_test.dart` 와
/// 같은 방법이다. 그대로 두면 `startGenerating` 이 실제 5초 뒤 도착을 기다려
/// 테스트가 끝난 뒤에도 타이머가 남는다.
class _WaitingRepository extends MockRepository {
  _WaitingRepository();

  final ready = Completer<void>();

  @override
  Future<void> awaitReportReady() => ready.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 화면 하나를 그 경로로 띄우고 provider 를 만질 수 있는 통을 돌려준다.
  Future<ProviderContainer> openAt(
    WidgetTester tester,
    String location, {
    MockRepository? repository,
  }) async {
    tester.view.physicalSize = const Size(1236, 2751);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        if (repository != null)
          mockRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final router = buildRouter();
    router.go(location);

    // 목 데이터는 asset 에서 읽으므로 실제 비동기 처리를 기다린다.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: buildAppTheme(),
            routerConfig: router,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pump();

    return container;
  }

  group('알림 화면', () {
    testWidgets('알릴 것이 없으면 빈 상태를 보여준다', (tester) async {
      await openAt(tester, AppRoutes.notifications);

      expect(find.text('알림'), findsOneWidget);
      expect(find.text('아직 새 알림이 없어요.'), findsOneWidget);
    });

    testWidgets('만드는 중이면 홈과 같은 문구를 보여준다', (tester) async {
      final repository = _WaitingRepository();
      final container = await openAt(
        tester,
        AppRoutes.notifications,
        repository: repository,
      );

      container.read(reportNoticeProvider.notifier).startGenerating();
      await tester.pump();

      expect(find.text('8월 21일 만남'), findsOneWidget);
      expect(find.text('리포트를 만들고 있어요'), findsOneWidget);
      expect(find.text('조금만 기다려 주세요'), findsOneWidget);
    });

    testWidgets('도착했으면 눌러서 리포트로 들어간다', (tester) async {
      final container = await openAt(tester, AppRoutes.notifications);

      container.read(reportNoticeProvider.notifier).arrive();
      await tester.pump();

      expect(find.text('리포트가 도착했어요'), findsOneWidget);

      await tester.tap(find.text('리포트가 도착했어요'));
      await tester.pumpAndSettle();

      // 화면 이동은 리포트 화면에만 있는 문구로 확인한다(router_test.dart 와 같은 방법).
      expect(find.text('오늘의 만남'), findsOneWidget);
    });
  });

  group('홈의 알림 아이콘', () {
    testWidgets('누르면 알림 화면으로 이동한다', (tester) async {
      await openAt(tester, AppRoutes.home);

      await tester.tap(find.byIcon(Icons.notifications_none));
      await tester.pumpAndSettle();

      expect(find.text('아직 새 알림이 없어요.'), findsOneWidget);
    });
  });
}
