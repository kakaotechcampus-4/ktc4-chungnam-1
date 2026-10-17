import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/visit/visit_camera.dart';
import 'package:saerok/features/visit/visit_photo_screen.dart';

/// 정해 둔 순서대로 찍은 결과를 돌려주는 카메라다. 실제 카메라는 열지 않는다.
///
/// 결과는 경로(찍음), `null`(찍지 않고 나옴), [VisitCameraUnavailable](열지
/// 못함) 중 하나다. 경로는 기기에 없는 가짜 경로다.
class _FakeCamera implements VisitCamera {
  _FakeCamera(this._results);

  final List<Object?> _results;
  final discarded = <String>[];
  int captures = 0;

  /// 있으면 끝날 때까지 카메라가 열려 있는 것으로 친다.
  Completer<void>? gate;

  @override
  Future<String?> capture() async {
    captures++;
    final gate = this.gate;
    if (gate != null) await gate.future;
    final result = _results.removeAt(0);
    if (result is VisitCameraUnavailable) throw result;
    return result as String?;
  }

  @override
  Future<void> discard(String path) async => discarded.add(path);
}

Future<ProviderContainer> _open(WidgetTester tester, _FakeCamera camera) async {
  // 기준 화면 412 x 917 dp 다(`app/README.md`).
  tester.view.physicalSize = const Size(1236, 2751);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [visitCameraProvider.overrideWithValue(camera)],
  );
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: AppRoutes.visitPhoto,
    routes: [
      GoRoute(
        path: AppRoutes.visitPhoto,
        builder: (context, state) => const VisitPhotoScreen(),
      ),
      GoRoute(
        path: AppRoutes.visitRecord,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('녹음 화면'))),
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
  return container;
}

/// 화면에 띄운 사진 파일의 경로다. 사진이 없으면 `null` 이다.
String? _shownPhoto(WidgetTester tester) {
  final images = tester
      .widgetList<Image>(find.byType(Image))
      .map((image) => image.image)
      .whereType<FileImage>();
  return images.isEmpty ? null : images.single.file.path;
}

Future<void> _tapShutter(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel(RegExp(r'^사진 (다시 )?찍기$')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('찍기 전에는 사진 없이 녹음으로 넘어간다', (tester) async {
    final camera = _FakeCamera([]);
    final container = await _open(tester, camera);

    expect(find.text('눌러서 촬영하기'), findsOneWidget);
    expect(_shownPhoto(tester), isNull);

    await tester.tap(find.text('사진 없이 시작할게요'));
    await tester.pumpAndSettle();

    expect(find.text('녹음 화면'), findsOneWidget);
    expect(camera.captures, 0);
    expect(container.read(visitPhotoProvider), isNull);
  });

  testWidgets('찍으면 그 사진을 보여주고 들고 있는다', (tester) async {
    final camera = _FakeCamera(['/fake/visit-1.jpg']);
    final container = await _open(tester, camera);

    await _tapShutter(tester);

    expect(container.read(visitPhotoProvider), '/fake/visit-1.jpg');
    expect(_shownPhoto(tester), '/fake/visit-1.jpg');
    expect(find.text('다시 찍기'), findsOneWidget);

    await tester.tap(find.text('이 사진으로 시작하기'));
    await tester.pumpAndSettle();
    expect(find.text('녹음 화면'), findsOneWidget);
  });

  testWidgets('다시 찍으면 앞 사진 파일을 지운다', (tester) async {
    final camera = _FakeCamera(['/fake/visit-1.jpg', '/fake/visit-2.jpg']);
    final container = await _open(tester, camera);

    await _tapShutter(tester);
    await _tapShutter(tester);

    expect(container.read(visitPhotoProvider), '/fake/visit-2.jpg');
    expect(_shownPhoto(tester), '/fake/visit-2.jpg');
    expect(camera.discarded, ['/fake/visit-1.jpg']);
  });

  testWidgets('다시 찍다가 그만두면 앞 사진을 그대로 둔다', (tester) async {
    final camera = _FakeCamera(['/fake/visit-1.jpg', null]);
    final container = await _open(tester, camera);

    await _tapShutter(tester);
    await _tapShutter(tester);

    expect(container.read(visitPhotoProvider), '/fake/visit-1.jpg');
    expect(_shownPhoto(tester), '/fake/visit-1.jpg');
    expect(camera.discarded, isEmpty);
  });

  testWidgets('카메라를 열지 못하면 안내하고 사진 없이 시작할 수 있다', (tester) async {
    final camera = _FakeCamera([
      const VisitCameraUnavailable('no_available_camera'),
    ]);
    final container = await _open(tester, camera);

    await _tapShutter(tester);

    expect(find.textContaining('카메라를 열지 못했어요'), findsOneWidget);
    expect(container.read(visitPhotoProvider), isNull);

    await tester.tap(find.text('사진 없이 시작할게요'));
    await tester.pumpAndSettle();
    expect(find.text('녹음 화면'), findsOneWidget);
  });

  testWidgets('카메라가 열려 있는 동안에는 셔터와 시작을 막는다', (tester) async {
    final camera = _FakeCamera(['/fake/visit-1.jpg'])..gate = Completer();
    await _open(tester, camera);

    await tester.tap(find.bySemanticsLabel('사진 찍기'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('사진 찍기'));
    await tester.tap(find.text('사진 없이 시작할게요'));
    await tester.pump();

    expect(camera.captures, 1);
    expect(find.text('녹음 화면'), findsNothing);

    camera.gate!.complete();
    await tester.pumpAndSettle();
    expect(_shownPhoto(tester), '/fake/visit-1.jpg');
  });

  test('새 회차로 비우면 찍어 둔 사진 파일을 지운다', () {
    final camera = _FakeCamera([]);
    final container = ProviderContainer(
      overrides: [visitCameraProvider.overrideWithValue(camera)],
    );
    addTearDown(container.dispose);

    container.read(visitPhotoProvider.notifier).replace('/fake/visit-1.jpg');
    container.invalidate(visitPhotoProvider);
    container.read(visitPhotoProvider);

    expect(camera.discarded, ['/fake/visit-1.jpg']);
    expect(container.read(visitPhotoProvider), isNull);
  });
}
