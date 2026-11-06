// 등록을 마친 어르신의 사진을 프로필 설정 갤러리에서 더 올리는지 확인한다
// (`lib/features/profile/profile_photo_add_screen.dart`, api-spec 3-1, 2-3).
//
// 서버는 `FakeProfileServer`, 앨범은 대역이다. 사진 파일과 값은 모두 합성이다.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:saerok/app/router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/data/auth_api.dart';
import 'package:saerok/data/mock_repository.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/auth/auth_providers.dart';
import 'package:saerok/features/auth/auth_session.dart';
import 'package:saerok/features/profile_setup/photo_picker.dart';

import 'fake_profile_server.dart';

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

/// 앨범을 열 때마다 합성 PNG [count] 장을 돌려준다.
class _FakePicker implements PhotoPicker {
  _FakePicker(this._dir);

  final Directory _dir;

  /// 화면이 앨범에 넘긴 최대 장수.
  final limits = <int>[];

  int count = 1;
  int _next = 1;

  @override
  Future<List<PickedPhoto>> pick({required int limit}) async {
    limits.add(limit);
    return [
      for (var i = 0; i < count; i++)
        PickedPhoto(
          (File(
            '${_dir.path}/synthetic_${_next++}.png',
          )..writeAsBytesSync([0x89, 0x50, 0x4E, 0x47])).path,
        ),
    ];
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

/// 사진 [photos] 장을 올린 분 p1 이 있는 서버로 프로필 설정을 연다.
Future<({FakeProfileServer server, _FakePicker picker, GoRouter router})>
_openProfile(WidgetTester tester, {int photos = 2}) async {
  tester.view.physicalSize = const Size(1236, 6000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final dir = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('saerok_photo_add'),
  ))!;
  addTearDown(() => dir.delete(recursive: true));
  final picker = _FakePicker(dir);

  final server = FakeProfileServer(
    profiles: [
      FakeProfileServer.profile(
        id: 'p1',
        setupStatus: 'completed',
        photos: [
          for (var i = 1; i <= photos; i++)
            FakeProfileServer.photo(id: 'photo-$i'),
        ],
      ),
    ],
  );
  final sample = (await tester.runAsync(
    () => const MockRepository().loadProfile(),
  ))!;
  final account = (await tester.runAsync(
    () => const MockRepository().loadAccount(),
  ))!;
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      server.override,
      photoPickerProvider.overrideWithValue(picker),
      profileSampleProvider.overrideWith((ref) async => sample),
      accountProvider.overrideWith((ref) async => account),
      photoAnalysisPollIntervalProvider.overrideWithValue(
        const Duration(milliseconds: 10),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.read(sessionProvider.notifier).restore(_session());

  final router = buildRouter();
  addTearDown(router.dispose);
  router.go(AppRoutes.home);
  await tester.runAsync(() async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
      ),
    );
  });
  await _settle(tester);
  router.push(AppRoutes.profile);
  await _settle(tester);
  return (server: server, picker: picker, router: router);
}

final _addButton = find.widgetWithText(OutlinedButton, '사진 추가하기');

int _uploads(FakeProfileServer server) => server.requests
    .where((r) => r.method == 'POST' && r.path.endsWith('/photos'))
    .length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('갤러리에서 사진을 더 골라 올리면 갤러리가 새 사진을 보여준다', (tester) async {
    final (:server, :picker, :router) = await _openProfile(tester);
    expect(find.bySemanticsLabel(RegExp('^사진 [0-9]')), findsNWidgets(2));

    await tester.tap(_addButton);
    await _settle(tester);
    expect(find.text('2장을 올렸어요. 3장 더 올릴 수 있어요.'), findsOneWidget);

    await tester.tap(find.text('사진 추가하기'));
    await _settle(tester);
    expect(picker.limits, [3], reason: '이미 올린 두 장을 빼고 고르게 한다');
    expect(find.text('3/5'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '마치기'));
    await _settle(tester);

    expect(_uploads(server), 1);
    expect(server.uploads.single, contains('name="image"'));
    expect(find.text('사진 1장을 모두 올렸어요.'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '갤러리로 돌아가기'));
    await _settle(tester);

    expect(find.text('갤러리'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^사진 [0-9]')), findsNWidgets(3));

    // 갤러리를 떠나 분석 상태를 묻는 폴링을 멈춘다.
    router.go(AppRoutes.home);
    await _settle(tester);
  });

  testWidgets('다섯 장을 채웠으면 더 올리지 못하게 막고 이유를 알린다', (tester) async {
    await _openProfile(tester, photos: 5);

    final button = tester.widget<OutlinedButton>(_addButton);
    expect(button.onPressed, isNull);
    expect(find.text('사진은 5장까지 올릴 수 있어요.'), findsOneWidget);
  });

  testWidgets('서버에 닿지 못하면 다시 올릴 수 있다', (tester) async {
    final (:server, picker: _, router: _) = await _openProfile(tester);
    server.offline = true;
    await tester.tap(_addButton);
    await _settle(tester);
    await tester.tap(find.text('사진 추가하기'));
    await _settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, '마치기'));
    await _settle(tester);

    expect(find.text('실패'), findsOneWidget);
    server.offline = false;
    await tester.tap(find.widgetWithText(FilledButton, '다시 올리기'));
    await _settle(tester);

    expect(find.text('완료'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '갤러리로 돌아가기'), findsOneWidget);
  });

  testWidgets('서버가 다섯 장을 넘었다고 거절하면 알리고 빼고 마치게 한다', (tester) async {
    final (:server, picker: _, router: _) = await _openProfile(tester);
    server.failures['POST /api/v1/profiles/p1/photos'] = (
      status: 409,
      errorCode: 'PHOTO_LIMIT_EXCEEDED',
    );
    await tester.tap(_addButton);
    await _settle(tester);
    await tester.tap(find.text('사진 추가하기'));
    await _settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, '마치기'));
    await _settle(tester);

    expect(find.textContaining('사진은 5장까지만 올릴 수 있어요.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '다시 올리기'), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, '올리지 못한 사진은 빼고 마치기'));
    await _settle(tester);
    expect(find.text('갤러리'), findsOneWidget, reason: '프로필 설정으로 돌아온다');
  });
}
