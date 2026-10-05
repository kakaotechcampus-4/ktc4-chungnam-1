// 프로필 설정 갤러리에서 사진 설명을 확인하고 고치는 흐름을 확인한다.
//
// 설명은 AI 가 만든 후보다. 확인된 사실처럼 보이지 않는지, 분석이 끝나지 않았거나
// 실패한 사진을 정상 결과처럼 보여주지 않는지 함께 본다. 실패한 사진은 보호자가
// 직접 적을 수 있다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/profile/photo_description_store.dart';
import 'package:saerok/features/profile/profile_gallery.dart';

/// 저장 요청을 남기고, 정해 두면 실패한다.
class _FakeStore implements PhotoDescriptionStore {
  bool fail = false;
  final saved = <(String, String)>[];

  @override
  Future<void> save({
    required String photoId,
    required String description,
  }) async {
    if (fail) throw Exception('저장 실패');
    saved.add((photoId, description));
  }
}

ProfilePhoto _photo(
  String id,
  PhotoAnalysisStatus status, {
  String? description,
  String? errorCode,
}) => ProfilePhoto(
  photoId: id,
  profileId: 'profile_001',
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

Future<void> _open(
  WidgetTester tester, {
  List<ProfilePhoto>? photos,
  _FakeStore? store,
}) async {
  // 기준 화면 412 x 917 dp 다(`app/README.md`).
  tester.view.physicalSize = const Size(1236, 2751);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        photoDescriptionStoreProvider.overrideWithValue(store ?? _FakeStore()),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ProfileGallery(photos: photos ?? _photos),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
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
}
