// AI 사진 분석에 동의하지 않은 계정이 사진을 올리기 직전에 동의를 한 번 묻는지
// 확인한다(`lib/features/profile/photo_consent_prompt.dart`, api-spec 1-6, 3-1).
//
// 계정 서버는 `MockClient`, 프로필 서버는 `FakeProfileServer`, 앨범은 대역이다.
// 값과 사진 파일은 모두 합성이다.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saerok/app/router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/data/account_api.dart';
import 'package:saerok/data/api_client.dart';
import 'package:saerok/data/auth_api.dart';
import 'package:saerok/data/mock_repository.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/auth/auth_providers.dart';
import 'package:saerok/features/auth/auth_session.dart';
import 'package:saerok/features/profile/photo_consent_prompt.dart';
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

/// 1-3 과 1-6 만 답하는 계정 서버.
class _AccountServer {
  _AccountServer({required bool photoAnalysis})
    : consent = {
        'serviceData': true,
        'sensitiveData': true,
        'serviceImprovement': false,
        'pushNotification': true,
        'photoAnalysis': photoAnalysis,
      };

  final Map<String, bool> consent;
  final requests = <({String method, String path, Object? body})>[];

  /// 연결이 끊긴 것처럼 1-6 을 실패시킨다.
  bool patchOffline = false;

  List<Object?> get patches => [
    for (final r in requests)
      if (r.method == 'PATCH') r.body,
  ];

  AccountApi get api => AccountApi(
    ApiClient(
      authorization: () => 'Bearer fake-token',
      baseUrl: 'http://api.test',
      client: MockClient((request) async {
        final body = request.body.isEmpty ? null : jsonDecode(request.body);
        requests.add((
          method: request.method,
          path: request.url.path,
          body: body,
        ));
        if (request.method == 'PATCH') {
          if (patchOffline) throw http.ClientException('오프라인');
          consent.addAll((body as Map).cast<String, bool>());
        }
        return http.Response.bytes(
          utf8.encode(jsonEncode(_account())),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    ),
  );

  Map<String, Object?> _account() => {
    'schemaVersion': 1,
    'accountId': 'account-a',
    'authProvider': 'google',
    'displayName': '테스트 보호자',
    'email': null,
    'consent': {
      'consentVersion': '2026-09-06',
      for (final entry in consent.entries)
        entry.key: {
          'granted': entry.value,
          'grantedAt': entry.value ? '2026-10-18T10:00:00+09:00' : null,
        },
    },
    'createdAt': '2026-10-18T10:00:00+09:00',
  };
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

/// 다시 띄우지 않기를 메모리에만 기억하는 대역. 실제 보안 저장소는 플랫폼
/// 채널이 필요해 위젯 테스트에서 끝나지 않는다.
class _FakePromptStore implements PhotoConsentPromptStore {
  final mutedAccounts = <String>{};

  @override
  Future<bool> muted(String accountId) async =>
      mutedAccounts.contains(accountId);

  @override
  Future<void> mute(String accountId) async => mutedAccounts.add(accountId);
}

/// 버튼을 누르면 묻기 함수를 부르고, 끝나서 올리기로 넘어가면 [results] 에 쌓는다.
class _Host extends ConsumerWidget {
  const _Host(this.results);

  final List<bool> results;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () async {
          await askPhotoAnalysisBeforeUpload(context, ref);
          results.add(true);
        },
        child: const Text('사진 올리기'),
      ),
    ),
  );
}

Future<({ProviderContainer container, List<bool> results})> _openHost(
  WidgetTester tester,
  _AccountServer server, {
  bool loggedIn = true,
  _FakePromptStore? store,
}) async {
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      accountApiProvider.overrideWithValue(server.api),
      photoConsentPromptStoreProvider.overrideWithValue(
        store ?? _FakePromptStore(),
      ),
    ],
  );
  addTearDown(container.dispose);
  if (loggedIn) container.read(sessionProvider.notifier).restore(_session());
  final results = <bool>[];
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildAppTheme(), home: _Host(results)),
    ),
  );
  await _settle(tester);
  return (container: container, results: results);
}

Future<void> _tapUpload(WidgetTester tester) async {
  await tester.tap(find.text('사진 올리기'));
  await _settle(tester);
}

final _sheetTitle = find.text('AI 사진 분석 동의');
final _agree = find.text('동의하고 올리기');
final _decline = find.text('동의하지 않고 올리기');
final _mute = find.text('다시 띄우지 않기');

/// 앨범을 열 때마다 합성 PNG 한 장을 돌려준다.
class _FakePicker implements PhotoPicker {
  _FakePicker(this._dir);

  final Directory _dir;
  int _next = 1;

  @override
  Future<List<PickedPhoto>> pick({required int limit}) async => [
    PickedPhoto(
      (File(
        '${_dir.path}/synthetic_${_next++}.png',
      )..writeAsBytesSync([0x89, 0x50, 0x4E, 0x47])).path,
    ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('올리기 전에 묻기', () {
    testWidgets('동의하지 않은 계정은 가입 화면과 같은 동의문을 보고, 동의하면 1-6 으로 저장한다', (
      tester,
    ) async {
      final server = _AccountServer(photoAnalysis: false);
      final (:container, :results) = await _openHost(tester, server);

      await _tapUpload(tester);
      expect(_sheetTitle, findsOneWidget);
      expect(
        find.textContaining('사진 설명과 대화 소재 후보를 만드는 데 동의합니다'),
        findsOneWidget,
      );
      expect(find.textContaining('등록한 사진은 분석 없이 저장됩니다'), findsOneWidget);

      await tester.tap(_agree);
      await _settle(tester);

      expect(server.patches, [
        {'photoAnalysis': true},
      ]);
      expect(results, [true]);
      expect(find.text('AI 사진 분석에 동의했어요. 사진 설명을 만들어 드려요.'), findsOneWidget);
      final account = (await tester.runAsync(
        () => container.read(accountProvider.future),
      ))!;
      expect(account.consent['photoAnalysis']!.granted, isTrue);
    });

    testWidgets('동의하지 않고 올리면 저장하지 않고 올리며, 이번에는 다시 묻지 않는다', (tester) async {
      final server = _AccountServer(photoAnalysis: false);
      final (:container, :results) = await _openHost(tester, server);

      await _tapUpload(tester);
      await tester.tap(_decline);
      await _settle(tester);

      expect(server.patches, isEmpty);
      expect(results, [true]);

      await _tapUpload(tester);
      expect(_sheetTitle, findsNothing);
      expect(results, [true, true]);
    });

    testWidgets('시트를 그냥 닫으면 거절로 보고 올리며, 이번에는 다시 묻지 않는다', (tester) async {
      final server = _AccountServer(photoAnalysis: false);
      final (:container, :results) = await _openHost(tester, server);

      await _tapUpload(tester);
      expect(_sheetTitle, findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await _settle(tester);

      expect(_sheetTitle, findsNothing);
      expect(results, [true]);
      expect(server.patches, isEmpty);

      await _tapUpload(tester);
      expect(_sheetTitle, findsNothing);
      expect(results, [true, true]);
    });

    testWidgets('다시 띄우지 않기를 누르면 올리고, 앱을 다시 켜도 그 계정에는 묻지 않는다', (tester) async {
      final store = _FakePromptStore();
      final server = _AccountServer(photoAnalysis: false);
      final first = await _openHost(tester, server, store: store);

      await _tapUpload(tester);
      expect(_mute, findsOneWidget);
      await tester.tap(_mute);
      await _settle(tester);

      expect(first.results, [true]);
      expect(server.patches, isEmpty);
      expect(store.mutedAccounts, {'account-a'});

      // 앱을 다시 켠 것처럼 새 컨테이너로 연다. 이번에 물었는지는 잊는다.
      final second = await _openHost(tester, server, store: store);
      await _tapUpload(tester);

      expect(_sheetTitle, findsNothing);
      expect(second.results, [true]);
    });

    testWidgets('앱을 다시 켜면 거절했던 계정에도 다시 묻는다', (tester) async {
      final store = _FakePromptStore();
      final server = _AccountServer(photoAnalysis: false);
      await _openHost(tester, server, store: store);
      await _tapUpload(tester);
      await tester.tap(_decline);
      await _settle(tester);

      await _openHost(tester, server, store: store);
      await _tapUpload(tester);

      expect(_sheetTitle, findsOneWidget);
    });

    testWidgets('이미 동의한 계정은 묻지 않는다', (tester) async {
      final server = _AccountServer(photoAnalysis: true);
      final (:container, :results) = await _openHost(tester, server);

      await _tapUpload(tester);

      expect(_sheetTitle, findsNothing);
      expect(results, [true]);
    });

    testWidgets('로그인하지 않았으면 묻지 않는다', (tester) async {
      final server = _AccountServer(photoAnalysis: false);
      final (:container, :results) = await _openHost(
        tester,
        server,
        loggedIn: false,
      );

      await _tapUpload(tester);

      expect(_sheetTitle, findsNothing);
      expect(results, [true]);
      expect(server.patches, isEmpty);
    });

    testWidgets('동의를 저장하지 못해도 알리고 사진은 올린다', (tester) async {
      final server = _AccountServer(photoAnalysis: false)..patchOffline = true;
      final (:container, :results) = await _openHost(tester, server);

      await _tapUpload(tester);
      await tester.tap(_agree);
      await _settle(tester);

      expect(results, [true]);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(server.consent['photoAnalysis'], isFalse);
    });
  });

  testWidgets('갤러리에서 사진을 더 올릴 때 동의하면 저장한 뒤 사진을 올린다', (tester) async {
    tester.view.physicalSize = const Size(1236, 6000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('saerok_photo_consent'),
    ))!;
    addTearDown(() => dir.delete(recursive: true));

    final accounts = _AccountServer(photoAnalysis: false);
    final profiles = FakeProfileServer(
      profiles: [
        FakeProfileServer.profile(
          id: 'p1',
          setupStatus: 'completed',
          photos: [FakeProfileServer.photo(id: 'photo-1')],
        ),
      ],
    );
    final sample = (await tester.runAsync(
      () => const MockRepository().loadProfile(),
    ))!;
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        profiles.override,
        accountApiProvider.overrideWithValue(accounts.api),
        photoConsentPromptStoreProvider.overrideWithValue(_FakePromptStore()),
        photoPickerProvider.overrideWithValue(_FakePicker(dir)),
        profileSampleProvider.overrideWith((ref) async => sample),
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
          child: MaterialApp.router(
            theme: buildAppTheme(),
            routerConfig: router,
          ),
        ),
      );
    });
    await _settle(tester);
    router.push(AppRoutes.profile);
    await _settle(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, '사진 추가하기'));
    await _settle(tester);
    await tester.tap(find.text('사진 추가하기'));
    await _settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, '마치기'));
    await _settle(tester);

    expect(_sheetTitle, findsOneWidget);
    expect(
      profiles.requests.where((r) => r.method == 'POST'),
      isEmpty,
      reason: '고르기 전에는 올리지 않는다',
    );

    await tester.tap(_agree);
    await _settle(tester);

    expect(accounts.patches, [
      {'photoAnalysis': true},
    ]);
    expect(
      profiles.requests
          .where((r) => r.method == 'POST' && r.path.endsWith('/photos'))
          .length,
      1,
    );
    expect(find.text('사진 1장을 모두 올렸어요.'), findsOneWidget);
  });
}
