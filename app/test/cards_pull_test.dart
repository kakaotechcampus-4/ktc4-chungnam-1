// 대화 카드 화면에서 끝을 당겨 카드를 더 보는 동작과 선택 표시 자리를 확인한다.
//
// `lib/features/cards/cards_screen.dart`. 서버 대신 `FakeCardApi` 와 목 묶음을
// 쓰고 값은 모두 합성이다.

import 'package:flutter/gestures.dart';
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
import 'package:saerok/features/cards/card_generation_controller.dart';
import 'package:saerok/features/cards/cards_screen.dart';
import 'package:saerok/widgets/app_surfaces.dart';

import 'fake_card_api.dart';
import 'sample_profile.dart';

late CardSet _mockSet;

class _ReadyCardApi extends FakeCardApi {
  _ReadyCardApi() : super(statuses: [CardGenerationStatus.ready]);

  @override
  Future<CardSet> current(String profileId) async {
    calls.add('current');
    return _mockSet;
  }
}

Future<void> _open(WidgetTester tester) async {
  // 기준 화면 412 x 917 dp 다(`app/README.md`).
  tester.view.physicalSize = const Size(1236, 2751);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      withSampleProfile,
      serverProfileIdProvider.overrideWith((ref) async => 'server-profile-1'),
      cardApiProvider.overrideWithValue(_ReadyCardApi()),
      cardPollIntervalProvider.overrideWithValue(Duration.zero),
    ],
  );
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: AppRoutes.cards,
    routes: [
      GoRoute(
        path: AppRoutes.cards,
        builder: (context, state) => const CardsScreen(),
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

/// 펼치지 않은 카드 수.
int _cards() => find.text('눌러서 질문 보기').evaluate().length;

/// 목록을 손가락으로 [distance] 만큼 위로 끌고, 놓지 않은 채 돌려준다.
Future<TestGesture> _drag(WidgetTester tester, double distance) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(SingleChildScrollView)),
  );
  const step = 20.0;
  for (var moved = 0.0; moved < distance; moved += step) {
    await gesture.moveBy(const Offset(0, -step));
    await tester.pump(const Duration(milliseconds: 16));
  }
  return gesture;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    _mockSet = await const MockRepository().loadCardSet();
  });

  testWidgets('처음 3장을 보이고 끝에 당기면 더 나온다는 고리를 둔다', (tester) async {
    await _open(tester);

    expect(_cards(), 3);
    expect(find.text('끝까지 당기면 3장 더 나와요'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
  });

  testWidgets('살짝 당겼다 놓으면 카드가 늘지 않는다', (tester) async {
    await _open(tester);

    final gesture = await _drag(tester, 200);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_cards(), 3, reason: '고리가 다 차기 전에 놓았다');
  });

  testWidgets('고리가 다 찰 때까지 당기면 잠깐 불러온 뒤 3장이 더 나온다', (tester) async {
    await _open(tester);

    // 고리가 다 차 불러오기 시작할 때까지만 끈다.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SingleChildScrollView)),
    );
    for (var i = 0; i < 200; i++) {
      if (find.text('카드를 불러오고 있어요').evaluate().isNotEmpty) break;
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(find.text('카드를 불러오고 있어요'), findsOneWidget);
    expect(_cards(), 3, reason: '불러오는 동안에는 아직 그대로다');

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(_cards(), 6);
    expect(find.text('끝까지 당기면 3장 더 나와요'), findsOneWidget);
  });

  testWidgets('웹에서 마우스로 끌어도 다 차면 3장이 더 나온다', (tester) async {
    await _open(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SingleChildScrollView)),
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 0; i < 200; i++) {
      if (find.text('카드를 불러오고 있어요').evaluate().isNotEmpty) break;
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump(const Duration(milliseconds: 1));
    }
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(_cards(), 6);
  });

  testWidgets('고리와 문구는 한 줄에 있다', (tester) async {
    await _open(tester);

    final ring = tester.getRect(find.byType(CircularProgressIndicator));
    final text = tester.getRect(find.text('끝까지 당기면 3장 더 나와요'));
    expect(ring.width, lessThan(24));
    expect(ring.center.dy, closeTo(text.center.dy, 1));
    expect(ring.right, lessThan(text.left));
  });

  testWidgets('화면 낭독기는 고리를 눌러 바로 더 볼 수 있다', (tester) async {
    final handle = tester.ensureSemantics();
    await _open(tester);

    final node = find.semantics.byLabel('대화 카드 3장 더 보기');
    expect(node, findsOne);
    tester.semantics.tap(node);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(_cards(), 6);
    handle.dispose();
  });

  testWidgets('선택 표시는 카드 높이의 가운데에 있고 고르지 않으면 연한 테두리다', (tester) async {
    await _open(tester);

    final card = tester.getRect(find.byType(AppCard).first);
    final mark = tester.getRect(find.byType(SelectionMark).first);
    expect(mark.center.dy, closeTo(card.center.dy, 1));

    final ring = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(SelectionMark).first,
            matching: find.byType(Container),
          )
          .first,
    );
    final border = (ring.decoration! as BoxDecoration).border! as Border;
    expect(border.top.color, AppColors.selectionRing);
  });
}
