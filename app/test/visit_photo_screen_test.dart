import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/visit/visit_camera.dart';
import 'package:saerok/features/visit/visit_gallery.dart';
import 'package:saerok/features/visit/visit_photo_screen.dart';
import 'package:saerok/features/visit/visit_photos.dart';

import 'fake_visit_camera.dart';
import 'fake_visit_gallery.dart';
import 'fake_visit_photos.dart';

Future<ProviderContainer> _open(
  WidgetTester tester,
  FakeVisitCamera camera, {
  FakeVisitPhotos? photos,
  FakeVisitGallery? gallery,
}) async {
  // 기준 화면 412 x 917 dp 다(`app/README.md`).
  tester.view.physicalSize = const Size(1236, 2751);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      visitCameraProvider.overrideWithValue(camera),
      visitPhotosProvider.overrideWithValue(photos ?? FakeVisitPhotos()),
      visitGalleryProvider.overrideWithValue(gallery ?? FakeVisitGallery()),
    ],
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
    final camera = FakeVisitCamera();
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
    final camera = FakeVisitCamera(['/fake/visit-1.jpg']);
    final container = await _open(tester, camera);

    await _tapShutter(tester);

    expect(container.read(visitPhotoProvider), '/fake/visit-1.jpg');
    expect(_shownPhoto(tester), '/fake/visit-1.jpg');
    expect(find.text('다시 찍기'), findsOneWidget);

    await tester.tap(find.text('이 사진으로 시작하기'));
    await tester.pumpAndSettle();
    expect(find.text('녹음 화면'), findsOneWidget);
  });

  testWidgets('찍으면 갤러리에 원본을 남기고 사본을 둔다', (tester) async {
    final camera = FakeVisitCamera(['/fake/visit-1.jpg']);
    final photos = FakeVisitPhotos();
    final gallery = FakeVisitGallery();
    await _open(tester, camera, photos: photos, gallery: gallery);

    await _tapShutter(tester);

    expect(gallery.saved, ['/fake/visit-1.jpg']);
    expect(photos.kept, {'/fake/visit-1.jpg': null});
    expect(photos.inGallery, {'/fake/visit-1.jpg'});
    expect(find.textContaining('갤러리에 저장하지 못했어요'), findsNothing);
  });

  testWidgets('다시 찍으면 앞 사진은 갤러리에 두고 사본만 지운다', (tester) async {
    final camera = FakeVisitCamera(['/fake/visit-1.jpg', '/fake/visit-2.jpg']);
    final photos = FakeVisitPhotos();
    final gallery = FakeVisitGallery();
    final container = await _open(
      tester,
      camera,
      photos: photos,
      gallery: gallery,
    );

    await _tapShutter(tester);
    await _tapShutter(tester);

    expect(container.read(visitPhotoProvider), '/fake/visit-2.jpg');
    expect(_shownPhoto(tester), '/fake/visit-2.jpg');
    expect(gallery.saved, ['/fake/visit-1.jpg', '/fake/visit-2.jpg']);
    expect(photos.discarded, ['/fake/visit-1.jpg']);
    expect(photos.kept.keys, ['/fake/visit-2.jpg']);
  });

  testWidgets('갤러리에 저장하지 못하면 안내하고 사진은 그대로 쓴다', (tester) async {
    final camera = FakeVisitCamera(['/fake/visit-1.jpg']);
    final photos = FakeVisitPhotos();
    final container = await _open(
      tester,
      camera,
      photos: photos,
      gallery: FakeVisitGallery(fails: true),
    );

    await _tapShutter(tester);

    expect(find.textContaining('갤러리에 저장하지 못했어요'), findsOneWidget);
    expect(container.read(visitPhotoProvider), '/fake/visit-1.jpg');
    expect(photos.inGallery, isEmpty);

    await tester.tap(find.text('이 사진으로 시작하기'));
    await tester.pumpAndSettle();
    expect(find.text('녹음 화면'), findsOneWidget);
  });

  testWidgets('갤러리에 남기지 못한 사진은 다시 찍어도 사본을 남긴다', (tester) async {
    final camera = FakeVisitCamera(['/fake/visit-1.jpg', '/fake/visit-2.jpg']);
    final photos = FakeVisitPhotos();
    final gallery = FakeVisitGallery(fails: true);
    await _open(tester, camera, photos: photos, gallery: gallery);

    await _tapShutter(tester);
    gallery.fails = false;
    await _tapShutter(tester);

    expect(photos.discarded, isEmpty, reason: '사본이 하나뿐인 원본이다');
    expect(photos.kept.keys, ['/fake/visit-1.jpg', '/fake/visit-2.jpg']);
    expect(find.textContaining('갤러리에 저장하지 못했어요'), findsNothing);
  });

  testWidgets('다시 찍다가 그만두면 앞 사진을 그대로 둔다', (tester) async {
    final camera = FakeVisitCamera(['/fake/visit-1.jpg', null]);
    final photos = FakeVisitPhotos();
    final container = await _open(tester, camera, photos: photos);

    await _tapShutter(tester);
    await _tapShutter(tester);

    expect(container.read(visitPhotoProvider), '/fake/visit-1.jpg');
    expect(_shownPhoto(tester), '/fake/visit-1.jpg');
    expect(photos.discarded, isEmpty);
  });

  testWidgets('카메라를 열지 못하면 안내하고 사진 없이 시작할 수 있다', (tester) async {
    final camera = FakeVisitCamera([
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
    final camera = FakeVisitCamera(['/fake/visit-1.jpg'])..gate = Completer();
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

  testWidgets('사진을 저장하지 못하면 안내하고 사진 없이 시작할 수 있다', (tester) async {
    final camera = FakeVisitCamera(['/fake/visit-1.jpg']);
    final photos = FakeVisitPhotos()
      ..keepFailure = const FileSystemException('합성 실패');
    final container = await _open(tester, camera, photos: photos);

    await _tapShutter(tester);

    expect(find.textContaining('사진을 저장하지 못했어요'), findsOneWidget);
    expect(container.read(visitPhotoProvider), isNull);

    await tester.tap(find.text('사진 없이 시작할게요'));
    await tester.pumpAndSettle();
    expect(find.text('녹음 화면'), findsOneWidget);
  });

  testWidgets('카메라가 열린 사이 화면을 떠나면 갤러리에만 남기고 면회에 쓰지 않는다', (tester) async {
    final camera = FakeVisitCamera(['/fake/visit-1.jpg'])..gate = Completer();
    final photos = FakeVisitPhotos();
    final gallery = FakeVisitGallery();
    final container = await _open(
      tester,
      camera,
      photos: photos,
      gallery: gallery,
    );

    await tester.tap(find.bySemanticsLabel('사진 찍기'));
    await tester.pump();
    // 화면을 내린다. 컨테이너는 그대로 둔다.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const SizedBox.shrink(),
      ),
    );

    camera.gate!.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(container.read(visitPhotoProvider), isNull);
    expect(photos.kept, isEmpty);
    expect(gallery.saved, ['/fake/visit-1.jpg']);
  });

  test('새 회차나 로그아웃으로 비워도 사진 파일은 남긴다', () async {
    final photos = FakeVisitPhotos();
    final container = ProviderContainer(
      overrides: [
        visitCameraProvider.overrideWithValue(FakeVisitCamera()),
        visitPhotosProvider.overrideWithValue(photos),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(visitPhotoProvider.notifier)
        .replace('/fake/visit-1.jpg', inGallery: true);
    container.invalidate(visitPhotoProvider);

    expect(container.read(visitPhotoProvider), isNull);
    expect(photos.discarded, isEmpty);
    expect(photos.kept.keys, ['/fake/visit-1.jpg']);
  });
}
