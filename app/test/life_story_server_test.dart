// 로그인한 상태에서 일대기가 서버(`api-spec.md` 2-3, 2-6, 2-7, 2-9)의 이야기를
// 읽고 저장하는지 확인한다.
//
// 서버는 `FakeProfileServer` 다. 값은 모두 합성이다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/app/router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/data/auth_api.dart';
import 'package:saerok/data/mock_repository.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/auth/auth_providers.dart';
import 'package:saerok/features/auth/auth_session.dart';
import 'package:saerok/features/life_story/life_story_providers.dart';

import 'fake_profile_server.dart';
import 'fake_report_server.dart';

AuthSession _session() => AuthSession(
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

/// 실제 비동기 처리(가짜 서버, asset 읽기)를 기다리고 화면을 맞춘다.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    if (i >= 2 && find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      break;
    }
  }
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await _settle(tester);
}

/// 로그인한 상태로 [location] 을 연다.
Future<ProviderContainer> _open(
  WidgetTester tester,
  FakeProfileServer server,
  String location,
) async {
  tester.view.physicalSize = const Size(1236, 6000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final sample = (await tester.runAsync(
    () => const MockRepository().loadProfile(),
  ))!;
  final account = (await tester.runAsync(
    () => const MockRepository().loadAccount(),
  ))!;
  final container = ProviderContainer(
    overrides: [
      server.override,
      FakeReportServer().override,
      profileSampleProvider.overrideWith((ref) async => sample),
      accountProvider.overrideWith((ref) async => account),
    ],
  );
  addTearDown(container.dispose);
  container.read(sessionProvider.notifier).restore(_session());

  final router = buildRouter();
  addTearDown(router.dispose);
  router.go(location);

  await tester.runAsync(() async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  for (var i = 0; i < 50; i++) {
    if (!container.read(careProfilesProvider).isLoading) break;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  await _settle(tester);
  return container;
}

/// 서버에 등록을 마친 분이 한 분 있고 여행 이야기 한 편을 담아 두었다.
FakeProfileServer _server() => FakeProfileServer(
  profiles: [
    FakeProfileServer.profile(
      id: 'p1',
      setupStatus: 'completed',
      occupation: '재봉 일을 오래 하셨어요.',
      lifeFacts: [
        FakeProfileServer.lifeFact(
          id: 'f1',
          profileId: 'p1',
          storyCategory: 'travel',
          title: '경주 여행',
          content: '불국사 앞에서 사진을 찍으셨대요.',
          imageNumber: 2,
        ),
      ],
    ),
  ],
);

List<Map<String, Object?>> _factsOf(FakeProfileServer server) =>
    (server.profiles.single['lifeFacts'] as List).cast<Map<String, Object?>>();

Future<void> _fill(WidgetTester tester, String title, String content) async {
  await tester.enterText(find.byType(TextField).at(0), title);
  await tester.enterText(find.byType(TextField).at(1), content);
  await tester.pump();
}

void main() {
  testWidgets('서버에 담긴 이야기를 보여주고 목 이야기는 쓰지 않는다', (tester) async {
    await _open(tester, _server(), AppRoutes.albumCategoryOf('travel'));

    expect(find.text('경주 여행'), findsOneWidget);
    expect(find.text('신혼여행은 경주로'), findsNothing, reason: '목 이야기');

    await _tap(tester, find.text('경주 여행'));

    expect(find.text('여행 · 1장'), findsOneWidget);
    expect(find.text('불국사 앞에서 사진을 찍으셨대요.'), findsOneWidget);
  });

  testWidgets('이야기를 담으면 서버에 보내고 목차에 보인다', (tester) async {
    final server = _server();
    final container = await _open(tester, server, AppRoutes.albumBook);

    await _tap(tester, find.text('이야기 추가하기'));
    await _tap(tester, find.bySemanticsLabel('친구'));
    await _fill(tester, '오래된 계모임', '한 달에 한 번 모이셨대요.');
    await _tap(tester, find.text('이야기 담기'));

    final post = server.requests.lastWhere((r) => r.method == 'POST');
    expect(post.path, '/api/v1/profiles/p1/life-facts');
    expect(post.body, {
      'storyCategory': 'friend',
      'title': '오래된 계모임',
      'content': '한 달에 한 번 모이셨대요.',
      'imageNumber': (post.body as Map)['imageNumber'],
    });
    expect((post.body as Map)['imageNumber'], inInclusiveRange(1, 5));
    expect(_factsOf(server), hasLength(2));
    expect(find.text('이야기를 담았어요.'), findsOneWidget);
    expect(
      container.read(lifeStoryEditsProvider),
      isEmpty,
      reason: '서버에 저장한 분은 앱 안에 따로 기억하지 않는다',
    );

    // 첫 장의 분류 칸이다. 최근 이야기 칸에도 같은 분류 이름이 있다.
    await _tap(tester, find.text('친구').first);
    expect(find.text('오래된 계모임'), findsOneWidget);
  });

  testWidgets('이야기를 고치면 서버에 네 항목을 보내고 바로 보여준다', (tester) async {
    final server = _server();
    await _open(tester, server, AppRoutes.albumStoryOf('travel', 'f1'));

    await _tap(tester, find.byTooltip('이야기 수정'));
    await tester.enterText(find.byType(TextField).at(0), '경주 신혼여행');
    await tester.pump();
    await _tap(tester, find.text('수정 완료'));

    final patch = server.requests.lastWhere((r) => r.method == 'PATCH');
    expect(patch.path, '/api/v1/life-facts/f1');
    expect(patch.body, {
      'storyCategory': 'travel',
      'title': '경주 신혼여행',
      'content': '불국사 앞에서 사진을 찍으셨대요.',
      'imageNumber': 2,
    });
    expect(find.text('이야기를 고쳤어요.'), findsOneWidget);
    expect(find.text('경주 신혼여행'), findsOneWidget);
  });

  testWidgets('지우기 전에 카드와 면회 기록이 남는다고 알리고 서버에서 지운다', (tester) async {
    final server = _server();
    await _open(tester, server, AppRoutes.albumCategoryOf('travel'));
    await _tap(tester, find.text('경주 여행'));

    await _tap(tester, find.byTooltip('이야기 지우기'));
    expect(
      find.text('지운 이야기는 되돌릴 수 없어요.\n이 이야기로 이미 만든 대화 카드와 리포트는\n그대로 남아요.'),
      findsOneWidget,
    );
    await _tap(tester, find.text('지우기'));

    final delete = server.requests.lastWhere((r) => r.method == 'DELETE');
    expect(delete.path, '/api/v1/life-facts/f1');
    expect(_factsOf(server), isEmpty);
    expect(find.text('이야기를 지웠어요.'), findsOneWidget);
    expect(find.text('김새록님의 여행에 대한\n이야기입니다.'), findsOneWidget);
    expect(find.text('경주 여행'), findsNothing);
  });

  testWidgets('서버에 닿지 못하면 담지 않고 쓰던 내용을 둔다', (tester) async {
    final server = _server();
    await _open(tester, server, AppRoutes.albumBook);

    await _tap(tester, find.text('이야기 추가하기'));
    await _tap(tester, find.bySemanticsLabel('친구'));
    await _fill(tester, '오래된 계모임', '한 달에 한 번 모이셨대요.');
    server.offline = true;
    await _tap(tester, find.text('이야기 담기'));

    expect(find.text('서버에 연결하지 못했어요. 인터넷 연결을 확인하고 다시 시도해주세요.'), findsOneWidget);
    expect(find.text('이야기 추가하기'), findsOneWidget, reason: '입력 화면에 남는다');
    expect(find.text('오래된 계모임'), findsOneWidget);
    expect(_factsOf(server), hasLength(1));
  });

  testWidgets('지우지 못하면 알리고 이야기에 남는다', (tester) async {
    final server = _server();
    await _open(tester, server, AppRoutes.albumCategoryOf('travel'));
    await _tap(tester, find.text('경주 여행'));

    server.failures['DELETE /api/v1/life-facts/f1'] = (
      status: 500,
      errorCode: 'INTERNAL_ERROR',
    );
    await _tap(tester, find.byTooltip('이야기 지우기'));
    await _tap(tester, find.text('지우기'));

    expect(find.text('처리하지 못했어요. 잠시 뒤 다시 시도해주세요.'), findsOneWidget);
    expect(find.text('여행 · 1장'), findsOneWidget);
    expect(_factsOf(server), hasLength(1));
  });

  testWidgets('이미 지운 이야기면 알리고 목록을 다시 읽는다', (tester) async {
    final server = _server();
    await _open(tester, server, AppRoutes.albumCategoryOf('travel'));
    await _tap(tester, find.text('경주 여행'));

    // 다른 기기에서 먼저 지웠다.
    server.profiles.single['lifeFacts'] = <Object>[];
    await _tap(tester, find.byTooltip('이야기 지우기'));
    await _tap(tester, find.text('지우기'));

    expect(find.text('이야기를 찾지 못했어요. 이미 지운 이야기일 수 있어요.'), findsOneWidget);
    expect(find.text('이야기를 찾을 수 없어요.'), findsOneWidget);
  });
}
