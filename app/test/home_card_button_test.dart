// 홈의 `오늘의 대화카드 받기` 가 카드 화면으로 가기 전에 쓸 묶음을 준비하는지
// 확인한다.
//
// 만드는 동안 카드 화면에 갇히지 않고 홈에서 기다린다. 서버 대신
// `FakeCardApi` 를 쓰고 값은 모두 합성이다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:saerok/app/router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/data/api_client.dart';
import 'package:saerok/data/card_api.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/design/tokens.dart';
import 'package:saerok/features/cards/card_generation_controller.dart';
import 'package:saerok/features/home/home_phrases.dart';
import 'package:saerok/widgets/mascot.dart';

import 'fake_card_api.dart';
import 'sample_profile.dart';

const _none = CardGenerationStatus.none;
const _running = CardGenerationStatus.running;
const _ready = CardGenerationStatus.ready;
const _failed = CardGenerationStatus.failed;
const _needsRefresh = CardGenerationStatus.needsRefresh;

const _poll = Duration(milliseconds: 50);
const _button = '오늘의 대화카드 받기';
const _making = '대화 카드를 만들고 있어요';
const _remakingNotice = '카드를 받은 뒤 어르신 정보가 바뀌어서';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 홈을 띄우고 통과 길잡이를 돌려준다.
  Future<(ProviderContainer, GoRouter)> openHome(
    WidgetTester tester,
    CardApi api,
  ) async {
    tester.view.physicalSize = const Size(1236, 2751);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        withSampleProfile,
        cardApiProvider.overrideWithValue(api),
        cardPollIntervalProvider.overrideWithValue(_poll),
        // 카드 화면에 들어가도 목 묶음을 asset 에서 다시 읽지 않게 한다.
        currentCardSetProvider.overrideWith(
          (ref) => Completer<CardSet>().future,
        ),
      ],
    );
    addTearDown(container.dispose);

    final router = buildRouter();
    router.go(AppRoutes.home);

    // 목 프로필은 asset 에서 읽으므로 실제 비동기 처리를 기다린다.
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
      await container.read(serverProfileIdProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pump();

    return (container, router);
  }

  /// 맨 위 화면의 경로. 쌓은(push) 화면도 센다.
  String location(GoRouter router) =>
      router.routerDelegate.currentConfiguration.last.matchedLocation;

  Color? buttonColor(WidgetTester tester) {
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    final states = {if (button.onPressed == null) WidgetState.disabled};
    return button.style?.backgroundColor?.resolve(states);
  }

  Finder spinnerInButton() => find.descendant(
    of: find.byType(FilledButton),
    matching: find.byType(CircularProgressIndicator),
  );

  testWidgets('쓸 묶음이 있으면 바로 카드 화면으로 간다', (tester) async {
    final api = FakeCardApi(statuses: [_ready]);
    final (_, router) = await openHome(tester, api);

    await tester.tap(find.text(_button));
    await tester.pump();
    await tester.pump();

    expect(location(router), AppRoutes.cards);
    expect(api.calls.first, 'status');
    expect(api.calls, isNot(contains('request')));
  });

  testWidgets('만들어야 하면 홈에서 버튼이 돌고 다 되면 알리기만 한다', (tester) async {
    final api = FakeCardApi(statuses: [_none, _running, _ready]);
    final (_, router) = await openHome(tester, api);

    await tester.tap(find.text(_button));
    await tester.pump();

    expect(location(router), AppRoutes.home, reason: '로딩 화면에 갇히지 않는다');
    expect(spinnerInButton(), findsOneWidget);
    expect(find.text(_making), findsOneWidget, reason: '만드는 중임을 글로도 알린다');
    expect(find.text(_button), findsNothing);
    expect(
      buttonColor(tester),
      isNot(AppColors.ink),
      reason: '만드는 동안은 면을 조금 흐리게 한다',
    );
    expect(buttonColor(tester), isNot(AppColors.line), reason: '비활성 회색과 다르다');
    expect(
      find.textContaining(_remakingNotice),
      findsNothing,
      reason: '고친 묶음이 아니다',
    );

    await tester.pump(_poll);
    await tester.pump(_poll);
    await tester.pump();

    expect(spinnerInButton(), findsNothing);
    expect(find.text(_button), findsOneWidget);
    expect(buttonColor(tester), AppColors.ink);
    expect(find.textContaining('대화 카드가 준비됐어요'), findsOneWidget);
    expect(location(router), AppRoutes.home, reason: '다른 화면에 있을 수 있다');
    expect(api.calls.where((c) => c == 'request'), hasLength(1));
  });

  testWidgets('다 만들면 말풍선이 완성을 알리고, 마스코트를 누르면 이야기로 바뀐다', (tester) async {
    final api = FakeCardApi(statuses: [_none, _running, _ready]);
    await openHome(tester, api);
    expect(find.text(cardsReadyMessage), findsNothing);

    await tester.tap(find.text(_button));
    await tester.pump();
    await tester.pump(_poll);
    await tester.pump(_poll);
    await tester.pump();
    expect(find.text(cardsReadyMessage), findsOneWidget);

    // 성공 움직임이 끝난 뒤 누른다. 축하 중에는 누름을 받지 않는다.
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.byType(Mascot));
    await tester.pump();
    expect(find.text(cardsReadyMessage), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && storyRemarks.contains(w.data),
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('상태를 묻는 짧은 동안은 버튼 모양을 바꾸지 않는다', (tester) async {
    final api = _SlowStatusCardApi();
    await openHome(tester, api);

    await tester.tap(find.text(_button));
    await tester.pump();

    expect(find.text(_button), findsOneWidget, reason: '바꾸면 곧 다시 바뀌어 깜빡인다');
    expect(find.text(_making), findsNothing);
    expect(buttonColor(tester), AppColors.ink);

    api.answer.complete(_ready);
    await tester.pump();
    await tester.pump();
  });

  testWidgets('다 된 뒤 다시 누르면 카드 화면으로 간다', (tester) async {
    final api = FakeCardApi(statuses: [_none, _ready]);
    final (_, router) = await openHome(tester, api);

    await tester.tap(find.text(_button));
    await tester.pump();
    await tester.pump(_poll);
    await tester.pump();
    await tester.tap(find.text(_button));
    await tester.pump();
    await tester.pump();

    expect(location(router), AppRoutes.cards);
  });

  testWidgets('만드는 중에 다시 눌러도 생성을 두 번 요청하지 않는다', (tester) async {
    final api = FakeCardApi(statuses: [_none, _running, _running, _ready]);
    final (_, _) = await openHome(tester, api);

    await tester.tap(find.text(_button));
    await tester.pump();
    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.pump(_poll);
    }

    expect(api.calls.where((c) => c == 'request'), hasLength(1));
  });

  testWidgets('받은 뒤 정보를 고친 묶음이면 새로 만들며 까닭을 알린다', (tester) async {
    final api = FakeCardApi(statuses: [_needsRefresh, _running, _ready]);
    final (_, router) = await openHome(tester, api);

    await tester.tap(find.text(_button));
    await tester.pump();
    await tester.pump();

    expect(location(router), AppRoutes.home, reason: '옛 카드를 보여주지 않는다');
    expect(find.textContaining(_remakingNotice), findsOneWidget);
    expect(api.calls, contains('request'));

    await tester.pump(_poll);
    await tester.pump(_poll);
    await tester.pump();

    expect(find.textContaining(_remakingNotice), findsNothing);
    expect(find.textContaining('대화 카드가 준비됐어요'), findsOneWidget);
  });

  testWidgets('만들다 실패하면 알리고 다시 누르면 새로 요청한다', (tester) async {
    final api = FakeCardApi(statuses: [_none, _failed, _failed, _ready]);
    final (_, router) = await openHome(tester, api);

    await tester.tap(find.text(_button));
    await tester.pump();
    await tester.pump(_poll);
    await tester.pump();

    expect(find.textContaining('대화 카드를 만들지 못했어요'), findsOneWidget);
    expect(location(router), AppRoutes.home);

    await tester.tap(find.text(_button));
    await tester.pump();
    await tester.pump(_poll);
    await tester.pump();

    expect(api.calls.where((c) => c == 'request'), hasLength(2));
  });

  testWidgets('서버에 닿지 못하면 연결 안내를 띄우고 홈에 남는다', (tester) async {
    final (_, router) = await openHome(tester, _OfflineCardApi());

    await tester.tap(find.text(_button));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('서버에 연결하지 못했어요'), findsOneWidget);
    expect(location(router), AppRoutes.home);
    expect(spinnerInButton(), findsNothing);
  });

  testWidgets('다 만든 것은 알림창, 실패는 버튼 아래 글로 남고 다시 누르면 지운다', (tester) async {
    final api = FakeCardApi(statuses: [_none, _failed, _none, _ready]);
    await openHome(tester, api);

    await tester.tap(find.text(_button));
    await tester.pump();
    await tester.pump(_poll);
    await tester.pump();

    expect(find.byType(SnackBar), findsNothing, reason: '알림창은 버튼을 가린다');
    expect(find.textContaining('대화 카드를 만들지 못했어요'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(
      find.textContaining('대화 카드를 만들지 못했어요'),
      findsOneWidget,
      reason: '저절로 사라지지 않는다',
    );

    await tester.tap(find.text(_button));
    await tester.pump();
    expect(find.textContaining('대화 카드를 만들지 못했어요'), findsNothing);

    await tester.pump(_poll);
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.textContaining('대화 카드가 준비됐어요'),
      ),
      findsOneWidget,
      reason: '다른 화면에 있어도 보이게 알림창으로 알린다',
    );
  });

  testWidgets('실패와 연결 끊김은 빨간 글로 알린다', (tester) async {
    await openHome(tester, _OfflineCardApi());

    await tester.tap(find.text(_button));
    await tester.pump();
    await tester.pump();

    final text = tester.widget<Text>(find.textContaining('서버에 연결하지 못했어요'));
    expect(text.style?.color, AppColors.danger);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('새로 만드는 까닭은 i 기호와 함께 회색 상자에 둔다', (tester) async {
    final api = FakeCardApi(statuses: [_needsRefresh, _running, _ready]);
    await openHome(tester, api);

    await tester.tap(find.text(_button));
    await tester.pump();
    await tester.pump();

    final box = find.ancestor(
      of: find.textContaining(_remakingNotice),
      matching: find.byType(Container),
    );
    expect(
      find.descendant(of: box.first, matching: find.byIcon(Icons.info_outline)),
      findsOneWidget,
    );
    final decoration = tester.widget<Container>(box.first).decoration;
    expect((decoration! as BoxDecoration).color, AppColors.surface);
    expect(find.textContaining('다른 화면을 봐도 괜찮아요'), findsNothing);

    await tester.pump(_poll);
    await tester.pump(_poll);
    await tester.pump();
  });
}

/// 4-2 의 응답을 테스트가 직접 보낸다.
class _SlowStatusCardApi implements CardApi {
  final answer = Completer<CardGenerationStatus>();

  @override
  Future<CardGenerationStatus> status(String profileId) => answer.future;

  @override
  Future<CardGenerationStatus> requestGeneration(String profileId) =>
      throw UnimplementedError();

  @override
  Future<CardSet> current(String profileId) => throw UnimplementedError();
}

/// 서버에 닿지 못한다.
class _OfflineCardApi implements CardApi {
  @override
  Future<CardGenerationStatus> status(String profileId) async =>
      throw const ApiNetworkFailure();

  @override
  Future<CardGenerationStatus> requestGeneration(String profileId) =>
      throw UnimplementedError();

  @override
  Future<CardSet> current(String profileId) => throw UnimplementedError();
}
