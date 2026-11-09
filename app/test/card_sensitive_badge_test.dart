// 아픈 경험을 다루는 카드(`sensitive`)에 `조심스러운 이야기` 표시를 다는지
// 확인한다(2026-11-09 PM 결정).
//
// 카드 고르기(C)와 면회 중 카드 추가(E-5) 두 화면이다. 서버 대신
// `FakeCardApi` 를 쓰고 값은 모두 합성이다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/data/card_api.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/cards/card_generation_controller.dart';
import 'package:saerok/features/cards/cards_screen.dart';
import 'package:saerok/features/cards/sensitive_card_badge.dart';
import 'package:saerok/features/visit/add_cards_screen.dart';

import 'fake_card_api.dart';
import 'sample_profile.dart';

/// 12장 묶음. [sensitive] 에 든 순서의 카드만 조심스러운 카드다.
CardSet _set({Set<int> sensitive = const {}}) => CardSet(
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
        primaryQuestion: '합성 질문 $p',
        followUpQuestions: const ['합성 꼬리 질문'],
        evidenceSource: 'none',
        evidence: const [],
        selected: false,
        sensitive: sensitive.contains(p),
      ),
  ],
);

class _ReadyCardApi extends FakeCardApi {
  _ReadyCardApi(this.set) : super(statuses: [CardGenerationStatus.ready]);

  final CardSet set;

  @override
  Future<CardSet> current(String profileId) async {
    calls.add('current');
    return set;
  }
}

Future<void> _open(
  WidgetTester tester,
  CardSet set, {
  String location = AppRoutes.cards,
}) async {
  // 기준 화면 412 x 917 dp 다(`app/README.md`).
  tester.view.physicalSize = const Size(1236, 2751);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      withSampleProfile,
      serverProfileIdProvider.overrideWith((ref) async => 'server-profile-1'),
      cardApiProvider.overrideWithValue(_ReadyCardApi(set)),
      cardPollIntervalProvider.overrideWithValue(Duration.zero),
      currentCardSetProvider.overrideWith((ref) async => set),
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

/// [title] 카드 안에 있는지.
Finder _inCard(String title, Finder finder) => find.descendant(
  of: find.ancestor(of: find.text(title), matching: find.byType(Column)).first,
  matching: finder,
);

void main() {
  group('카드 고르기', () {
    testWidgets('조심스러운 카드에만 표시를 단다', (tester) async {
      await _open(tester, _set(sensitive: {2}));

      expect(find.text('조심스러운 이야기'), findsOneWidget);
      expect(_inCard('합성 카드 2', find.text('조심스러운 이야기')), findsOneWidget);
      expect(_inCard('합성 카드 1', find.text('조심스러운 이야기')), findsNothing);

      // 제목 위에 두어 고르기 전에 보인다.
      final badge = tester.getRect(find.text('조심스러운 이야기'));
      final title = tester.getRect(find.text('합성 카드 2'));
      expect(badge.bottom, lessThanOrEqualTo(title.top));
    });

    testWidgets('조심스러운 카드가 없으면 표시도 없다', (tester) async {
      await _open(tester, _set());

      expect(find.text('조심스러운 이야기'), findsNothing);
    });

    testWidgets('표시가 있어도 다른 카드처럼 고를 수 있다', (tester) async {
      await _open(tester, _set(sensitive: {1}));

      await tester.tap(find.bySemanticsLabel(cardSelectLabel('합성 카드 1')));
      await tester.pumpAndSettle();

      expect(find.text('1개 선택함'), findsOneWidget);
    });

    // 화면 전체가 아니라 표시만 본다. 카드 고르기 위의 `○개 선택함` 줄은 글자
    // 1.5배부터 넘친다(이 변경 전부터, 412dp).
    testWidgets('글자를 두 배로 키워도 표시가 좁은 칸에서 넘치지 않는다', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: SizedBox(
              width: 120,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [SensitiveCardBadge()],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(SensitiveCardBadge)).width,
        lessThanOrEqualTo(120),
      );
    });
  });

  group('면회 중 카드 추가', () {
    testWidgets('보충용 카드 중 조심스러운 카드에만 표시를 단다', (tester) async {
      await _open(
        tester,
        _set(sensitive: {2, 11}),
        location: AppRoutes.visitAddCards,
      );

      // 10~12번이 보충용이다. 고르기 화면의 2번은 여기에 없다.
      expect(find.text('조심스러운 이야기'), findsOneWidget);
      expect(_inCard('합성 카드 11', find.text('조심스러운 이야기')), findsOneWidget);
      expect(_inCard('합성 카드 10', find.text('조심스러운 이야기')), findsNothing);
    });
  });
}
