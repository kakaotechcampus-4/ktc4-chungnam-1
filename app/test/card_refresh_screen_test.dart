// 받은 뒤 프로필이나 일대기를 고친 카드 묶음(API 4절 `needsRefresh`)의 카드
// 화면을 확인한다.
//
// `lib/features/cards/cards_screen.dart`. 서버 대신 `FakeCardApi` 와 목 묶음을
// 쓰고 값은 모두 합성이다.

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
import 'package:saerok/features/cards/card_generation_controller.dart';
import 'package:saerok/features/cards/cards_screen.dart';

import 'fake_card_api.dart';
import 'sample_profile.dart';

/// 목 묶음은 asset 에서 읽는다. 화면을 띄우기 전에 한 번 읽어 두고 4-3 이
/// 그대로 돌려준다. 다시 만든 뒤에 받는 묶음도 같다.
late CardSet _mockSet;

class _PreloadedCardApi extends FakeCardApi {
  _PreloadedCardApi({required super.statuses});

  @override
  Future<CardSet> current(String profileId) async {
    calls.add('current');
    return _mockSet;
  }
}

Future<void> _open(WidgetTester tester, FakeCardApi api) async {
  // 기준 화면 412 x 917 dp 다(`app/README.md`).
  tester.view.physicalSize = const Size(1236, 2751);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      withSampleProfile,
      // 프로필도 asset 에서 읽는다. 카드 API 에 보낼 ID 만 있으면 된다.
      serverProfileIdProvider.overrideWith((ref) async => 'server-profile-1'),
      cardApiProvider.overrideWithValue(api),
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

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    _mockSet = await const MockRepository().loadCardSet();
  });

  testWidgets('고친 묶음은 카드를 보여주되 고르거나 시작하지 못하게 한다', (tester) async {
    await _open(
      tester,
      _PreloadedCardApi(statuses: [CardGenerationStatus.needsRefresh]),
    );

    expect(find.textContaining('어르신 정보가 바뀌었어요'), findsOneWidget);
    expect(find.text('다음 대화 준비하기'), findsOneWidget);
    expect(find.text('대화 시작하기'), findsNothing);
    expect(find.text('아직 고르지 않았어요'), findsNothing);
    expect(find.text('눌러서 질문 보기'), findsWidgets, reason: '카드는 그대로 볼 수 있다');
  });

  testWidgets('다음 대화 준비하기를 누르면 새로 만들어 고를 수 있게 된다', (tester) async {
    final api = _PreloadedCardApi(
      statuses: [
        CardGenerationStatus.needsRefresh,
        CardGenerationStatus.running,
        CardGenerationStatus.ready,
      ],
    );
    await _open(tester, api);

    await tester.tap(find.text('다음 대화 준비하기'));
    await tester.pumpAndSettle();

    expect(api.calls, [
      'status',
      'current',
      'request',
      'status',
      'status',
      'current',
    ]);
    expect(find.text('대화 시작하기'), findsOneWidget);
    expect(find.text('아직 고르지 않았어요'), findsOneWidget);
    expect(find.textContaining('어르신 정보가 바뀌었어요'), findsNothing);
  });
}
