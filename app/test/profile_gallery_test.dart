// 프로필 설정 갤러리에서 사진 설명을 확인하고 고치는 흐름을 확인한다.
//
// 설명은 AI 가 만든 후보다. 확인된 사실처럼 보이지 않는지, 분석이 끝나지 않았거나
// 실패한 사진을 정상 결과처럼 보여주지 않는지 함께 본다. 실패한 사진은 보호자가
// 직접 적을 수 있다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/auth_api.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/auth/auth_providers.dart';
import 'package:saerok/features/auth/auth_session.dart';
import 'package:saerok/features/profile/photo_description_store.dart';
import 'package:saerok/features/profile/profile_gallery.dart';
import 'package:saerok/features/profile_setup/setup_controller.dart';

import 'sample_profile.dart';

/// 저장 요청을 남기고, 정해 두면 실패한다.
class _FakeStore implements PhotoDescriptionStore {
  bool fail = false;
  final saved = <(String, String)>[];

  /// 열려 있으면 저장 응답이 오지 않는다. 저장하는 동안의 화면을 볼 때 쓴다.
  Completer<void>? gate;

  @override
  Future<void> save({
    required String photoId,
    required String description,
  }) async {
    final gate = this.gate;
    if (gate != null) await gate.future;
    if (fail) throw Exception('저장 실패');
    saved.add((photoId, description));
  }
}

/// 로그인한 계정의 세션이다. 값은 모두 합성이다.
AuthSession _sessionOf(String accountId) => AuthSession(
  accessToken: 'token-$accountId',
  tokenType: 'Bearer',
  expiresAt: DateTime.now().add(const Duration(hours: 1)),
  account: AuthAccount(
    accountId: accountId,
    authProvider: 'google',
    displayName: '보호자',
    email: null,
    consentVersion: null,
    createdAt: null,
  ),
);

ProfilePhoto _photo(
  String id,
  PhotoAnalysisStatus status, {
  String? description,
  String? errorCode,
  String profileId = 'profile_001',
}) => ProfilePhoto(
  photoId: id,
  profileId: profileId,
  imageUrl: 'asset:assets/images/family.webp',
  analysisStatus: status,
  description: description,
  errorCode: errorCode,
  createdAt: '2026-08-21T12:20:00+09:00',
);

const _aiText = '한복을 입은 어르신 두 분과 가족이 함께 찍은 사진이에요.';

final _photos = [
  _photo('photo_1', PhotoAnalysisStatus.completed, description: _aiText),
  _photo('photo_2', PhotoAnalysisStatus.processing),
  _photo('photo_3', PhotoAnalysisStatus.failed, errorCode: 'AI_SERVER_ERROR'),
];

/// 갤러리를 띄운다. [container] 를 넘기면 계정이나 어르신을 바꿔 다시 띄울 때
/// 같은 상태를 이어서 쓴다.
Future<ProviderContainer> _open(
  WidgetTester tester, {
  List<ProfilePhoto>? photos,
  _FakeStore? store,
  ProviderContainer? container,
}) async {
  // 기준 화면 412 x 917 dp 다(`app/README.md`).
  tester.view.physicalSize = const Size(1236, 2751);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final scope =
      container ??
      ProviderContainer(
        overrides: [
          photoDescriptionStoreProvider.overrideWithValue(
            store ?? _FakeStore(),
          ),
        ],
      );
  if (container == null) addTearDown(scope.dispose);

  final shown = photos ?? _photos;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: scope,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            // 다시 띄우면 처음 연 화면처럼 접힌 채로 시작한다.
            child: ProfileGallery(key: UniqueKey(), photos: shown),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return scope;
}

Finder _saveButton() => find.widgetWithText(FilledButton, '저장하기');

bool _enabled(WidgetTester tester, Finder button) =>
    tester.widget<FilledButton>(button).onPressed != null;

void main() {
  testWidgets('올린 사진을 보여주고 분석 상태를 칸에 붙인다', (tester) async {
    await _open(tester);

    expect(find.bySemanticsLabel('사진 1'), findsOneWidget);
    expect(find.text('분석 중'), findsOneWidget);
    expect(find.text('분석 실패'), findsOneWidget);
    expect(find.byType(TextField), findsNothing, reason: '누르기 전에는 접혀 있다');
  });

  testWidgets('사진을 누르면 AI 설명이 출처와 함께 펼쳐진다', (tester) async {
    await _open(tester);

    await tester.tap(find.bySemanticsLabel('사진 1'));
    await tester.pumpAndSettle();

    expect(find.text('AI가 만든 설명'), findsOneWidget);
    expect(find.widgetWithText(TextField, _aiText), findsOneWidget);
    expect(find.text('AI가 사진을 보고 만든 설명이에요. 사실과 다르면 고쳐주세요.'), findsOneWidget);
    expect(
      _enabled(tester, _saveButton()),
      isFalse,
      reason: '고치지 않았으면 저장할 것이 없다',
    );
  });

  testWidgets('고쳐서 저장하면 보호자가 고친 설명이 된다', (tester) async {
    final store = _FakeStore();
    await _open(tester, store: store);

    await tester.tap(find.bySemanticsLabel('사진 1'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  어머니 칠순 잔치 때 찍은 가족사진이에요.  ');
    await tester.pump();

    expect(_enabled(tester, _saveButton()), isTrue);

    await tester.tap(_saveButton());
    await tester.pumpAndSettle();

    expect(store.saved, [('photo_1', '어머니 칠순 잔치 때 찍은 가족사진이에요.')]);
    expect(find.text('설명을 저장했어요.'), findsOneWidget);
    expect(find.text('사진에 대한 설명'), findsOneWidget);
    expect(find.text('직접 적은 설명이에요. 다시 고칠 수 있어요.'), findsOneWidget);
    expect(find.text('AI가 만든 설명'), findsNothing);
    expect(_enabled(tester, _saveButton()), isFalse, reason: '저장한 내용과 같다');
  });

  testWidgets('고친 설명은 접었다 펼쳐도 남는다', (tester) async {
    await _open(tester);

    await tester.tap(find.bySemanticsLabel('사진 1'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '가족사진이에요.');
    await tester.pump();
    await tester.tap(_saveButton());
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('사진 1'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing, reason: '같은 사진을 다시 누르면 접힌다');

    await tester.tap(find.bySemanticsLabel('사진 1'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '가족사진이에요.'), findsOneWidget);
  });

  testWidgets('설명을 비우면 저장할 수 없다', (tester) async {
    await _open(tester);

    await tester.tap(find.bySemanticsLabel('사진 1'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();

    expect(find.text('설명을 비워둘 수 없어요.'), findsOneWidget);
    expect(_enabled(tester, _saveButton()), isFalse);
  });

  testWidgets('저장에 실패하면 알리고 고친 내용은 남긴다', (tester) async {
    final store = _FakeStore()..fail = true;
    await _open(tester, store: store);

    await tester.tap(find.bySemanticsLabel('사진 1'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '가족사진이에요.');
    await tester.pump();
    await tester.tap(_saveButton());
    await tester.pumpAndSettle();

    expect(find.text('저장하지 못했어요. 잠시 뒤 다시 시도해주세요.'), findsOneWidget);
    expect(find.text('AI가 만든 설명'), findsOneWidget, reason: '저장되지 않았다');
    expect(find.widgetWithText(TextField, '가족사진이에요.'), findsOneWidget);
    expect(_enabled(tester, _saveButton()), isTrue, reason: '다시 시도할 수 있다');
  });

  testWidgets('분석 중인 사진은 설명 대신 기다리라고 알린다', (tester) async {
    await _open(tester);

    await tester.tap(find.bySemanticsLabel('사진 2, 분석 중'));
    await tester.pumpAndSettle();

    expect(find.text('사진 설명을 만들고 있어요. 잠시 뒤 다시 확인해주세요.'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('분석에 실패한 사진은 실패를 알리고 직접 적게 한다', (tester) async {
    await _open(tester);

    await tester.tap(find.bySemanticsLabel('사진 3, 분석 실패'));
    await tester.pumpAndSettle();

    expect(find.text('AI가 설명을 만들지 못했어요. 직접 적어주셔도 돼요.'), findsOneWidget);
    expect(find.text('AI가 만든 설명'), findsNothing, reason: 'AI 설명이 없다');
    expect(find.text('사진에 대한 설명'), findsOneWidget);
    expect(
      find.text('설명을 비워둘 수 없어요.'),
      findsNothing,
      reason: '처음부터 빈칸인 것은 오류가 아니다',
    );
    expect(_enabled(tester, _saveButton()), isFalse);
  });

  testWidgets('실패한 사진에 직접 적어 저장하면 실패 표시를 뗀다', (tester) async {
    final store = _FakeStore();
    await _open(tester, store: store);

    await tester.tap(find.bySemanticsLabel('사진 3, 분석 실패'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '아버지 환갑 때 집 앞에서 찍은 사진이에요.');
    await tester.pump();
    await tester.tap(_saveButton());
    await tester.pumpAndSettle();

    expect(store.saved, [('photo_3', '아버지 환갑 때 집 앞에서 찍은 사진이에요.')]);
    expect(find.text('분석 실패'), findsNothing);
    expect(find.bySemanticsLabel('사진 3'), findsOneWidget);
    expect(find.textContaining('만들지 못했어요'), findsNothing);
    expect(find.text('직접 적은 설명이에요. 다시 고칠 수 있어요.'), findsOneWidget);
  });

  testWidgets('다른 사진을 누르면 그 사진으로 바뀐다', (tester) async {
    await _open(tester);

    await tester.tap(find.bySemanticsLabel('사진 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('사진 2, 분석 중'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('만들고 있어요'), findsOneWidget);
  });

  testWidgets('사진이 없으면 비어 있다고 알린다', (tester) async {
    await _open(tester, photos: const []);

    expect(find.text('아직 올린 사진이 없어요.'), findsOneWidget);
  });

  group('저장 결과는 그 사진에만 붙는다', () {
    testWidgets('저장하는 동안 다른 사진을 고르면 그 사진의 입력칸은 그대로다', (tester) async {
      final store = _FakeStore()..gate = Completer<void>();
      await _open(tester, store: store);

      await tester.tap(find.bySemanticsLabel('사진 1'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '가족사진이에요.');
      await tester.pump();
      await tester.tap(_saveButton());
      await tester.pump();

      // 저장 응답을 기다리는 동안 분석에 실패한 사진 3을 고른다.
      await tester.tap(find.bySemanticsLabel('사진 3, 분석 실패'));
      await tester.pumpAndSettle();
      expect(
        find.text('저장하는 중이에요'),
        findsNothing,
        reason: '사진 1의 저장 중 표시가 사진 3에 붙으면 안 된다',
      );

      store.gate!.complete();
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(TextField, '가족사진이에요.'),
        findsNothing,
        reason: '사진 1의 설명이 사진 3의 입력칸에 들어가면 안 된다',
      );
      expect(find.text('설명을 저장했어요.'), findsNothing);
      expect(_enabled(tester, _saveButton()), isFalse, reason: '사진 3은 빈칸이다');
      expect(store.saved, [('photo_1', '가족사진이에요.')]);

      // 사진 1로 돌아가면 저장한 설명이 있다.
      await tester.tap(find.bySemanticsLabel('사진 1'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '가족사진이에요.'), findsOneWidget);
      expect(find.text('사진에 대한 설명'), findsOneWidget);
    });
  });

  group('고친 설명은 계정과 어르신마다 따로 둔다', () {
    ProviderContainer newContainer() {
      final container = ProviderContainer(
        overrides: [
          photoDescriptionStoreProvider.overrideWithValue(_FakeStore()),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    Future<void> editPhoto1(WidgetTester tester, String text) async {
      await tester.tap(find.bySemanticsLabel('사진 1'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), text);
      await tester.pump();
      await tester.tap(_saveButton());
      await tester.pumpAndSettle();
    }

    Future<void> openPhoto1(WidgetTester tester) async {
      await tester.tap(find.bySemanticsLabel('사진 1'));
      await tester.pumpAndSettle();
    }

    testWidgets('다른 계정으로 바꾸면 앞 계정이 고친 설명이 보이지 않는다', (tester) async {
      final container = newContainer();
      final session = container.read(sessionProvider.notifier);

      session.restore(_sessionOf('account_a'));
      await _open(tester, container: container);
      await editPhoto1(tester, 'A 계정이 고친 설명이에요.');

      session.restore(_sessionOf('account_b'));
      await _open(tester, container: container);
      await openPhoto1(tester);
      expect(find.widgetWithText(TextField, _aiText), findsOneWidget);
      expect(find.text('AI가 만든 설명'), findsOneWidget);

      // A 계정으로 다시 들어오면 A 가 고친 설명이 있다.
      session.restore(_sessionOf('account_a'));
      await _open(tester, container: container);
      await openPhoto1(tester);
      expect(
        find.widgetWithText(TextField, 'A 계정이 고친 설명이에요.'),
        findsOneWidget,
      );
    });

    testWidgets('같은 목 사진이라도 다른 어르신에게는 보이지 않는다', (tester) async {
      final container = newContainer();

      await _open(tester, container: container);
      await editPhoto1(tester, '첫째 어르신의 설명이에요.');

      final other = [
        for (final photo in _photos) photo.forProfile('profile_002'),
      ];
      await _open(tester, container: container, photos: other);
      await openPhoto1(tester);

      expect(find.widgetWithText(TextField, _aiText), findsOneWidget);
    });

    testWidgets('로그아웃으로 어르신 정보를 지우면 고친 설명도 지운다', (tester) async {
      final container = newContainer();

      await _open(tester, container: container);
      await editPhoto1(tester, '지워질 설명이에요.');
      expect(container.read(editedPhotoDescriptionsProvider), hasLength(1));

      // 로그아웃과 탈퇴가 부르는 정리다. WidgetRef 가 필요해 화면에서 부른다.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => forgetCareProfiles(ref),
                child: const Text('정리'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('정리'));
      await tester.pump();

      expect(container.read(editedPhotoDescriptionsProvider), isEmpty);
    });
  });

  group('사진은 어르신마다의 photos[] 다', () {
    testWidgets('고른 어르신의 프로필은 사진을 그 분의 것으로 붙인다', (tester) async {
      final container = ProviderContainer(overrides: [withSampleProfile]);
      addTearDown(container.dispose);

      // 목 데이터는 asset 에서 읽으므로 실제 비동기 처리를 기다린다.
      final bundle = await tester.runAsync(
        () => container.read(profileProvider.future),
      );

      expect(bundle, isNotNull);
      expect(bundle!.photos, isNotEmpty);
      expect(bundle.photos.map((photo) => photo.profileId).toSet(), {
        sampleProfileId,
      });
    });
  });
}
