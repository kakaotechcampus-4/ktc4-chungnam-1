// 홈 화면의 리포트 알림 자리를 확인한다.
//
// 로딩 화면을 없앤 뒤로 리포트를 만드는 중임을 알리는 자리가 여기뿐이다.
// 같은 자리에서 만드는 중이 도착으로 바뀐다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/app/router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/data/mock_repository.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/design/theme.dart';

/// 리포트 도착 시점을 테스트가 직접 정하는 저장소다.
///
/// 시간을 재는 대신 [ready] 를 완료시켜 도착을 알린다. 서버를 붙일 때도 같은
/// 자리를 갈아 끼운다(`ADR-005`).
class _WaitingRepository extends MockRepository {
  _WaitingRepository();

  final ready = Completer<void>();

  @override
  Future<void> awaitReportReady() => ready.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 홈을 띄우고 알림 상태와 도착 시점을 다룰 수 있는 통을 돌려준다.
  Future<(ProviderContainer, _WaitingRepository)> openHome(
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1236, 2751);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final repository = _WaitingRepository();
    final container = ProviderContainer(
      overrides: [mockRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final router = buildRouter();
    router.go(AppRoutes.home);

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

    return (container, repository);
  }

  group('만드는 중 알림', () {
    testWidgets('알릴 것이 없으면 자리도 없다', (tester) async {
      await openHome(tester);

      expect(find.textContaining('만들고 있어요'), findsNothing);
      expect(find.textContaining('도착했어요'), findsNothing);
    });

    testWidgets('캐릭터와 날짜, 로딩을 함께 보여준다', (tester) async {
      final (container, repository) = await openHome(tester);

      container.read(reportNoticeProvider.notifier).startGenerating();
      await tester.pump();

      expect(find.text('8월 21일 만남'), findsOneWidget);
      expect(find.text('리포트를 만들고 있어요'), findsOneWidget);
      expect(find.text('조금만 기다려 주세요'), findsOneWidget);
      expect(
        find.byType(CircularProgressIndicator),
        findsOneWidget,
        reason: '만드는 중이라는 것을 움직임으로도 알린다',
      );

      final character = tester.widget<Image>(
        find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is AssetImage &&
              (w.image as AssetImage).assetName.endsWith('logo.webp'),
        ),
      );
      expect(character.width, 64);
    });

    testWidgets('아직 들어갈 곳이 없으므로 누르는 자리가 아니다', (tester) async {
      final (container, repository) = await openHome(tester);

      container.read(reportNoticeProvider.notifier).startGenerating();
      await tester.pump();

      expect(find.text('눌러서 확인하기'), findsNothing);
    });
  });

  group('줄바꿈', () {
    /// 배너 안의 글이 모두 한 줄인지 본다.
    void expectSingleLine(WidgetTester tester, List<String> texts) {
      for (final text in texts) {
        expect(
          tester.getRect(find.text(text)).height,
          lessThan(30),
          reason: '$text 가 줄바꿈되었다',
        );
      }
    }

    testWidgets('만드는 중 배너의 글이 모두 한 줄이다', (tester) async {
      final (container, repository) = await openHome(tester);

      container.read(reportNoticeProvider.notifier).startGenerating();
      await tester.pump();

      expectSingleLine(tester, ['8월 21일 만남', '리포트를 만들고 있어요', '조금만 기다려 주세요']);

      await tester.pump(const Duration(milliseconds: 80));
    });

    testWidgets('도착 배너의 글도 모두 한 줄이다', (tester) async {
      final (container, repository) = await openHome(tester);

      container.read(reportNoticeProvider.notifier).arrive();
      await tester.pump();

      expectSingleLine(tester, ['8월 21일 만남', '리포트가 도착했어요', '눌러서 확인하기']);
    });
  });

  group('도착으로 바뀌기', () {
    testWidgets('저장소가 알리면 같은 자리가 도착 알림이 된다', (tester) async {
      final (container, repository) = await openHome(tester);

      container.read(reportNoticeProvider.notifier).startGenerating();
      await tester.pump();

      expect(find.textContaining('만들고 있어요'), findsOneWidget);

      // 저장소가 도착을 알린다. 실제로는 서버가 이 자리를 맡는다.
      repository.ready.complete();
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('만들고 있어요'), findsNothing);
      expect(find.text('8월 21일 만남'), findsOneWidget);
      expect(find.text('리포트가 도착했어요'), findsOneWidget);
      expect(find.text('눌러서 확인하기'), findsOneWidget);
    });
  });
}
