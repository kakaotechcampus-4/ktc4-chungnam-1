// 대화 카드 화면에서 카드를 더 보는 버튼과 당기기, 선택 표시 자리와 펼침
// 단서를 확인한다.
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
import 'package:saerok/features/cards/cards_controller.dart';
import 'package:saerok/features/cards/cards_screen.dart';
import 'package:saerok/features/visit/add_cards_screen.dart';
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

/// 기준 화면은 412 x 917 dp 다(`app/README.md`).
Future<void> _open(
  WidgetTester tester, {
  Size size = const Size(412, 917),
  String location = AppRoutes.cards,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      withSampleProfile,
      serverProfileIdProvider.overrideWith((ref) async => 'server-profile-1'),
      cardApiProvider.overrideWithValue(_ReadyCardApi()),
      cardPollIntervalProvider.overrideWithValue(Duration.zero),
      currentCardSetProvider.overrideWith((ref) async => _mockSet),
    ],
  );
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
      child: MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

/// 펼치지 않은 카드 수.
int _cards() => find.text('질문 보기').evaluate().length;

/// 목록 끝의 `카드 3장 더 보기` 버튼.
Finder _moreButton() => find.widgetWithText(OutlinedButton, '카드 3장 더 보기');

/// 목록 끝까지 내려 `카드 3장 더 보기` 를 누른다.
Future<void> _tapMore(WidgetTester tester) async {
  await tester.ensureVisible(_moreButton());
  await tester.pumpAndSettle();
  await tester.tap(_moreButton());
  await tester.pump();
}

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

  testWidgets('처음 3장을 보이고 끝에 고리를 담은 더 보기 버튼을 둔다', (tester) async {
    await _open(tester);

    expect(_cards(), 3);
    expect(_moreButton(), findsOneWidget);
    expect(
      find.descendant(
        of: _moreButton(),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
      reason: '당기면 차는 고리는 버튼 안에 그대로 둔다',
    );
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
    expect(_moreButton(), findsOneWidget);
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

  group('카드 3장 더 보기 버튼 (UX 점검 5)', () {
    testWidgets('누르는 자리의 높이가 48 이상이다', (tester) async {
      await _open(tester);

      expect(
        tester.getSize(_moreButton()).height,
        greaterThanOrEqualTo(AppSizes.minTouch),
      );
    });

    testWidgets('360 x 640 에서도 높이가 48 이상이다', (tester) async {
      await _open(tester, size: const Size(360, 640));
      await tester.ensureVisible(_moreButton());
      await tester.pumpAndSettle();

      expect(
        tester.getSize(_moreButton()).height,
        greaterThanOrEqualTo(AppSizes.minTouch),
      );
    });

    testWidgets('누르면 당길 때처럼 잠깐 불러온 뒤 3장이 더 나온다', (tester) async {
      await _open(tester);

      await _tapMore(tester);
      expect(find.text('카드를 불러오고 있어요'), findsOneWidget);
      expect(_cards(), 3, reason: '불러오는 동안에는 아직 그대로다');

      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(_cards(), 6);
    });

    testWidgets('불러오는 동안 다시 눌러도 한 번만 늘어난다', (tester) async {
      await _open(tester);

      await _tapMore(tester);
      await tester.tap(
        find.widgetWithText(OutlinedButton, '카드를 불러오고 있어요'),
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      expect(_cards(), 6);
    });

    testWidgets('불러오는 동안에는 누를 수 없는 버튼으로 읽는다', (tester) async {
      final handle = tester.ensureSemantics();
      await _open(tester);

      await _tapMore(tester);
      final loading = find.widgetWithText(OutlinedButton, '카드를 불러오고 있어요');
      expect(tester.widget<OutlinedButton>(loading).onPressed, isNull);
      // 누를 수 없는 버튼을 누를 수 있는 버튼으로 읽지 않는다(`app/DESIGN.md`).
      expect(
        find.semantics.byLabel('카드를 불러오고 있어요').evaluate().single,
        isSemantics(
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          hasTapAction: false,
        ),
      );

      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(
        find.semantics.byLabel('대화 카드 3장 더 보기').evaluate().single,
        isSemantics(isButton: true, isEnabled: true, hasTapAction: true),
        reason: '다 불러오면 다시 누를 수 있다',
      );
      handle.dispose();
    });

    testWidgets('두 번 누르면 9장이 되고 버튼이 사라진다', (tester) async {
      await _open(tester);

      for (var i = 0; i < 2; i++) {
        await _tapMore(tester);
        await tester.pump(const Duration(milliseconds: 700));
        await tester.pumpAndSettle();
      }

      expect(_cards(), CardRules.selectableCount);
      expect(_moreButton(), findsNothing, reason: '고르는 화면은 앞 9장까지다');
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('움직임 줄이기를 켜면 돌지 않고 바로 나온다', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await _open(tester);

      await _tapMore(tester);
      // 0.6초를 기다리지 않는다.
      await tester.pump(Duration.zero);

      expect(_cards(), 6);
    });
  });

  group('고르는 자리와 펼침 단서 (UX 점검 19)', () {
    for (final size in const [Size(360, 640), Size(390, 844), Size(412, 917)]) {
      final tag = '${size.width.toInt()}dp';

      testWidgets('$tag 에서 설명 글자는 고르는 자리에 들어가지 않는다', (tester) async {
        await _open(tester, size: size);
        final description = tester.getRect(
          find.text(_mockSet.cards.first.description),
        );
        final toggle = tester.getRect(find.byType(SelectionToggle).first);

        expect(toggle.left, greaterThanOrEqualTo(description.right));
      });
    }

    testWidgets('설명의 오른쪽 끝을 누르면 고르지 않고 질문을 펼친다', (tester) async {
      await _open(tester, size: const Size(360, 640));
      final card = _mockSet.cards.first;
      final description = tester.getRect(find.text(card.description));

      await tester.tapAt(Offset(description.right - 4, description.center.dy));
      await tester.pumpAndSettle();

      expect(find.text('아직 고르지 않았어요'), findsOneWidget);
      expect(find.text(card.primaryQuestion), findsOneWidget);
    });

    testWidgets('고르는 자리는 원 둘레의 정해진 폭이고 카드 높이 전체에 걸친다', (tester) async {
      await _open(tester);
      final card = tester.getRect(find.byType(SelectableCard).first);
      final toggle = tester.getRect(find.byType(SelectionToggle).first);
      final mark = tester.getRect(find.byType(SelectionMark).first);

      // 글자 오른쪽 여백(24 + 48 + 12)과 같은 폭이다. 화면 폭에 따라 바뀌지 않는다.
      expect(toggle.width, 84);
      expect(toggle.right, card.right);
      expect(toggle.height, card.height);
      expect(toggle.contains(mark.center), isTrue);

      // 원이 아니라 자리의 위쪽 끝을 눌러도 고른다.
      await tester.tapAt(Offset(toggle.center.dx, toggle.top + 8));
      await tester.pumpAndSettle();

      expect(find.text('1개 선택함'), findsOneWidget);
      expect(
        find.text(_mockSet.cards.first.primaryQuestion),
        findsNothing,
        reason: '고를 때는 펼치지 않는다',
      );
    });

    testWidgets('360dp 에서도 고르는 자리 폭은 같다', (tester) async {
      await _open(tester, size: const Size(360, 640));

      expect(tester.getSize(find.byType(SelectionToggle).first).width, 84);
    });

    testWidgets('접힌 카드는 아래 화살표와 질문 보기를, 펼친 카드는 위 화살표와 질문 접기를 보인다', (
      tester,
    ) async {
      await _open(tester);

      expect(find.text('질문 보기'), findsNWidgets(3));
      expect(find.byIcon(Icons.keyboard_arrow_down), findsNWidgets(3));
      // 예전 13 회색 캡션보다 크고 초록으로 둔다.
      final style = tester.widget<Text>(find.text('질문 보기').first).style!;
      expect(style.fontSize, greaterThanOrEqualTo(15));
      expect(style.color, HomeColors.accent);

      await tester.tap(find.byIcon(Icons.keyboard_arrow_down).first);
      await tester.pumpAndSettle();

      final card = _mockSet.cards.first;
      expect(find.text(card.primaryQuestion), findsOneWidget);
      expect(find.text('질문 접기'), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
      expect(find.text('질문 보기'), findsNWidgets(2));
      expect(find.text('아직 고르지 않았어요'), findsOneWidget);

      await tester.ensureVisible(find.text('질문 접기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('질문 접기'));
      await tester.pumpAndSettle();
      expect(find.text(card.primaryQuestion), findsNothing);
    });

    testWidgets('화면 낭독기는 펼침 단서를 이름에 넣지 않고 두 번 탭 안내로 알린다', (tester) async {
      final handle = tester.ensureSemantics();
      await _open(tester);
      final title = _mockSet.cards.first.cardTitle;
      final node = tester.getSemantics(find.text(title));

      expect(node.label, isNot(contains('질문 보기')));
      expect(node.hintOverrides?.onTapHint, '질문 펼치기');
      handle.dispose();
    });

    testWidgets('면회 중 카드 추가 화면도 같은 펼침 단서와 고르는 자리를 쓴다', (tester) async {
      await _open(tester, location: AppRoutes.visitAddCards);

      expect(find.text('질문 보기'), findsWidgets);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsWidgets);
      expect(tester.getSize(find.byType(SelectionToggle).first).width, 84);
    });
  });
}
