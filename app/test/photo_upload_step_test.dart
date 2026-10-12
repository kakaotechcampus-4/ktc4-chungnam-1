// B-7 사진 올리기에서 앨범으로 고르고 빼는 흐름을 확인한다.
//
// 앨범은 기기 화면이라 테스트에서 열 수 없다. 고른 결과만 대역이 정한다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/profile_setup/photo_picker.dart';
import 'package:saerok/features/profile_setup/photo_uploader.dart';
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

/// 서버 대신 업로드 결과를 정하는 대역이다.
class _FakeUploader implements PhotoUploader {
  _FakeUploader({Map<String, PhotoUploadFailure>? failures})
    : _failures = failures ?? {};

  /// 첫 시도에만 실패할 사진. 다시 올리면 성공한다.
  final Map<String, PhotoUploadFailure> _failures;

  /// 열려 있으면 업로드가 끝나지 않는다. 올리는 중 화면을 볼 때 쓴다.
  Completer<void>? gate;

  /// 올리려고 한 사진 경로를 순서대로 남긴다.
  final attempts = <String>[];

  @override
  Future<void> upload(PickedPhoto photo) async {
    attempts.add(photo.path);
    final gate = this.gate;
    if (gate != null) await gate.future;
    final failure = _failures.remove(photo.path);
    if (failure != null) throw failure;
  }
}

/// 사진 단계까지 넘긴 입력 화면을 띄운다.
Future<ProviderContainer> _openPhotoStep(
  WidgetTester tester,
  _FakePicker picker, {
  _FakeUploader? uploader,
}) async {
  // 기준 화면 412 x 917 dp 다(`app/README.md`).
  tester.view.physicalSize = const Size(1236, 2751);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      photoPickerProvider.overrideWithValue(picker),
      photoUploaderProvider.overrideWithValue(uploader ?? _FakeUploader()),
    ],
  );
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: AppRoutes.profileCreate,
    routes: [
      GoRoute(
        path: AppRoutes.profileCreate,
        builder: (context, state) => const ProfileSetupScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('홈 화면'))),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildAppTheme(),
        routerConfig: router,
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

  group('마치기를 누르면 올린다', () {
    /// 사진을 고르고 마치기를 누른다. 업로드가 끝나기를 기다리지 않는다.
    Future<ProviderContainer> pickAndFinish(
      WidgetTester tester, {
      required int count,
      required _FakeUploader uploader,
    }) async {
      final container = await _openPhotoStep(
        tester,
        _FakePicker([_paths(count)]),
        uploader: uploader,
      );
      await tester.tap(find.text('사진 추가하기'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '마치기'));
      await tester.pump();
      return container;
    }

    testWidgets('고르기만 해서는 올리지 않는다', (tester) async {
      final uploader = _FakeUploader();
      await _openPhotoStep(
        tester,
        _FakePicker([_paths(2)]),
        uploader: uploader,
      );

      await tester.tap(find.text('사진 추가하기'));
      await tester.pumpAndSettle();

      expect(uploader.attempts, isEmpty, reason: 'X 로 빼도 서버에 남지 않아야 한다');
    });

    testWidgets('올리는 동안에는 빼거나 더하거나 뒤로 갈 수 없다', (tester) async {
      final uploader = _FakeUploader()..gate = Completer<void>();
      final container = await pickAndFinish(
        tester,
        count: 2,
        uploader: uploader,
      );

      expect(find.text('사진을 올리고 있어요.'), findsOneWidget);
      expect(find.bySemanticsLabel('사진 1 올리는 중'), findsOneWidget);
      final button = find.widgetWithText(FilledButton, '올리는 중이에요');
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      expect(find.byTooltip('사진 1 빼기'), findsNothing);
      expect(find.text('추가'), findsNothing);

      final controller = container.read(setupControllerProvider.notifier);
      expect(controller.back(), isTrue, reason: '화면을 벗어나지 않는다');
      expect(container.read(setupControllerProvider).isPhoto, isTrue);

      uploader.gate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('모두 올리면 완료를 보여주고 홈으로 버튼을 눌러 넘어간다', (tester) async {
      final uploader = _FakeUploader();
      await pickAndFinish(tester, count: 2, uploader: uploader);
      await tester.pumpAndSettle();

      expect(uploader.attempts, ['photo_1.jpg', 'photo_2.jpg']);
      expect(find.text('사진 2장을 모두 올렸어요.'), findsOneWidget);
      expect(find.text('완료'), findsNWidgets(2));
      expect(
        find.byTooltip('사진 1 빼기'),
        findsNothing,
        reason: '서버에 올라간 사진은 지울 수 없다',
      );
      expect(find.text('추가'), findsNothing);
      expect(find.text('홈 화면'), findsNothing, reason: '자동으로 넘어가지 않는다');

      await tester.tap(find.widgetWithText(FilledButton, '홈으로'));
      await tester.pumpAndSettle();

      expect(find.text('홈 화면'), findsOneWidget);
    });

    testWidgets('일부가 실패하면 그 사진만 다시 올린다', (tester) async {
      final uploader = _FakeUploader(
        failures: {
          'photo_2.jpg': const PhotoUploadFailure(
            'IMAGE_STORAGE_UNAVAILABLE',
            retryable: true,
          ),
        },
      );
      await pickAndFinish(tester, count: 3, uploader: uploader);
      await tester.pumpAndSettle();

      expect(find.text('실패'), findsOneWidget);
      expect(find.text('완료'), findsNWidgets(2));
      expect(
        find.text('사진 1장을 올리지 못했어요. 사진을 올리지 못했어요. 잠시 뒤 다시 시도해주세요.'),
        findsOneWidget,
      );
      expect(find.byTooltip('사진 2 빼기'), findsOneWidget, reason: '실패한 사진은 서버에 없다');
      expect(find.byTooltip('사진 1 빼기'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, '다시 올리기'));
      await tester.pumpAndSettle();

      expect(uploader.attempts, [
        'photo_1.jpg',
        'photo_2.jpg',
        'photo_3.jpg',
        'photo_2.jpg',
      ]);
      expect(find.text('사진 3장을 모두 올렸어요.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '홈으로'), findsOneWidget);
    });

    testWidgets('다시 올려도 안 되는 실패는 빼라고 안내한다', (tester) async {
      final uploader = _FakeUploader(
        failures: {'photo_1.jpg': const PhotoUploadFailure('IMAGE_TOO_LARGE')},
      );
      await pickAndFinish(tester, count: 1, uploader: uploader);
      await tester.pumpAndSettle();

      expect(find.textContaining('사진 용량이 너무 커요'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '다시 올리기'), findsNothing);
      expect(
        find.widgetWithText(OutlinedButton, '올리지 못한 사진은 빼고 마치기'),
        findsOneWidget,
      );
    });

    testWidgets('실패한 사진은 빼고 마칠 수 있다', (tester) async {
      final uploader = _FakeUploader(
        failures: {'photo_2.jpg': const PhotoUploadFailure('IMAGE_TOO_LARGE')},
      );
      final container = await pickAndFinish(
        tester,
        count: 2,
        uploader: uploader,
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(OutlinedButton, '올리지 못한 사진은 빼고 마치기'),
      );
      await tester.pumpAndSettle();

      expect(find.text('홈 화면'), findsOneWidget);
      final paths = container
          .read(setupControllerProvider)
          .draft
          .photos
          .map((photo) => photo.path);
      expect(paths, ['photo_1.jpg']);
    });

    testWidgets('서버에 닿지 못하면 다시 올릴 수 있다', (tester) async {
      await pickAndFinish(tester, count: 1, uploader: _ThrowingUploader());
      await tester.pumpAndSettle();

      expect(find.text('실패'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '다시 올리기'), findsOneWidget);
    });
  });
}

/// 서버 오류가 아닌 예외로 실패한다. 연결이 끊긴 경우다.
class _ThrowingUploader extends _FakeUploader {
  @override
  Future<void> upload(PickedPhoto photo) async {
    attempts.add(photo.path);
    throw const _ConnectionLost();
  }
}

class _ConnectionLost implements Exception {
  const _ConnectionLost();
}
