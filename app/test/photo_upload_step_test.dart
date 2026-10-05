// B-7 사진 올리기에서 앨범으로 고르고 빼는 흐름을 확인한다.
//
// 앨범은 기기 화면이라 테스트에서 열 수 없다. 고른 결과만 대역이 정한다.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/profile_setup/photo_picker.dart';
import 'package:saerok/features/profile_setup/profile_setup_screen.dart';
import 'package:saerok/features/profile_setup/setup_controller.dart';

/// 차례대로 정해 둔 결과를 돌려주는 앨범 대역이다.
class _FakePicker implements PhotoPicker {
  _FakePicker(this._results);

  /// 앨범을 열 때마다 하나씩 꺼낸다. `null` 이면 앨범이 실패한다.
  final List<List<String>?> _results;

  /// 화면이 앨범에 넘긴 최대 장수.
  final limits = <int>[];

  @override
  Future<List<PickedPhoto>> pick({required int limit}) async {
    limits.add(limit);
    final next = _results.removeAt(0);
    if (next == null) {
      throw PlatformException(code: 'photo_access_denied');
    }
    return [for (final path in next) PickedPhoto(path)];
  }
}

List<String> _paths(int count, {int from = 1}) => [
  for (var i = from; i < from + count; i++) 'photo_$i.jpg',
];

/// 사진 단계까지 넘긴 입력 화면을 띄운다.
Future<ProviderContainer> _openPhotoStep(
  WidgetTester tester,
  _FakePicker picker,
) async {
  // 기준 화면 412 x 917 dp 다(`app/README.md`).
  tester.view.physicalSize = const Size(1236, 2751);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [photoPickerProvider.overrideWithValue(picker)],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const ProfileSetupScreen(),
      ),
    ),
  );

  final controller = container.read(setupControllerProvider.notifier);
  for (var i = 0; i < 1 + lifeFactStepCount; i++) {
    controller.next();
  }
  await tester.pumpAndSettle();
  expect(container.read(setupControllerProvider).isPhoto, isTrue);
  return container;
}

int _picked(ProviderContainer container) =>
    container.read(setupControllerProvider).draft.photos.length;

void main() {
  testWidgets('고른 사진을 칸에 놓고 장수를 보여준다', (tester) async {
    final picker = _FakePicker([_paths(2)]);
    final container = await _openPhotoStep(tester, picker);

    await tester.tap(find.text('사진 추가하기'));
    await tester.pumpAndSettle();

    expect(_picked(container), 2);
    expect(find.text('2/5'), findsOneWidget);
    expect(find.byTooltip('사진 1 빼기'), findsOneWidget);
    expect(find.byTooltip('사진 2 빼기'), findsOneWidget);
    expect(find.text('추가'), findsOneWidget, reason: '아직 세 장을 더 고를 수 있다');
    expect(picker.limits, [5]);
  });

  testWidgets('남은 장수만큼만 앨범에서 고르게 한다', (tester) async {
    final picker = _FakePicker([_paths(2), _paths(3, from: 3)]);
    final container = await _openPhotoStep(tester, picker);

    await tester.tap(find.text('사진 추가하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('추가'));
    await tester.pumpAndSettle();

    expect(picker.limits, [5, 3]);
    expect(_picked(container), 5);
    expect(find.text('5/5'), findsOneWidget);
    expect(find.text('추가'), findsNothing, reason: '다 채우면 추가 칸을 숨긴다');
  });

  testWidgets('다섯 장을 넘게 고르면 넘친 만큼 빼고 알린다', (tester) async {
    // 기기에 따라 앨범이 개수 제한을 지키지 않을 수 있다.
    final picker = _FakePicker([_paths(7)]);
    final container = await _openPhotoStep(tester, picker);

    await tester.tap(find.text('사진 추가하기'));
    await tester.pumpAndSettle();

    expect(_picked(container), 5);
    expect(find.text('사진은 5장까지 올릴 수 있어요. 2장은 빼고 담았어요.'), findsOneWidget);
  });

  testWidgets('X 를 누르면 그 사진만 빠진다', (tester) async {
    final picker = _FakePicker([_paths(3)]);
    final container = await _openPhotoStep(tester, picker);

    await tester.tap(find.text('사진 추가하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('사진 2 빼기'));
    await tester.pumpAndSettle();

    final paths = container
        .read(setupControllerProvider)
        .draft
        .photos
        .map((photo) => photo.path);
    expect(paths, ['photo_1.jpg', 'photo_3.jpg']);
    expect(find.text('2/5'), findsOneWidget);
  });

  testWidgets('모두 빼면 처음의 큰 추가 자리로 돌아가고 건너뛸 수 있다', (tester) async {
    final picker = _FakePicker([_paths(1)]);
    await _openPhotoStep(tester, picker);

    await tester.tap(find.text('사진 추가하기'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '마치기'), findsOneWidget);

    await tester.tap(find.byTooltip('사진 1 빼기'));
    await tester.pumpAndSettle();

    expect(find.text('사진 추가하기'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '건너뛰기'), findsOneWidget);
  });

  testWidgets('앨범에서 그냥 나오면 아무것도 바뀌지 않는다', (tester) async {
    final picker = _FakePicker([[]]);
    final container = await _openPhotoStep(tester, picker);

    await tester.tap(find.text('사진 추가하기'));
    await tester.pumpAndSettle();

    expect(_picked(container), 0);
    expect(find.text('사진 추가하기'), findsOneWidget);
    expect(find.textContaining('불러오지 못했어요'), findsNothing);
  });

  testWidgets('앨범이 사진을 넘겨주지 못하면 이유를 알린다', (tester) async {
    final picker = _FakePicker([null]);
    final container = await _openPhotoStep(tester, picker);

    await tester.tap(find.text('사진 추가하기'));
    await tester.pumpAndSettle();

    expect(_picked(container), 0);
    expect(find.text('사진을 불러오지 못했어요. 다시 시도해주세요.'), findsOneWidget);
  });

  testWidgets('빼기 버튼은 누를 수 있는 크기다', (tester) async {
    final picker = _FakePicker([_paths(1)]);
    await _openPhotoStep(tester, picker);

    await tester.tap(find.text('사진 추가하기'));
    await tester.pumpAndSettle();

    final size = tester.getSize(find.byTooltip('사진 1 빼기'));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });
}
