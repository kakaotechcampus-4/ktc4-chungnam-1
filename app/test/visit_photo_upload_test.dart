// 면회 전에 찍은 사진을 회차에 올리는 흐름(API 5-2)을 확인한다.
//
// 사진은 녹음을 막지 않는다. 회차를 만든 뒤 따로 올리고, 다시 시도해도 되는
// 실패에만 한 번 더 올린다. 그래도 안 되면 녹음 화면에 다시 올리기를 둔다.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/api_client.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/cards/cards_controller.dart';
import 'package:saerok/features/visit/record_screen.dart';
import 'package:saerok/features/visit/visit_camera.dart';
import 'package:saerok/features/visit/visit_controller.dart';
import 'package:saerok/features/visit/visit_recorder.dart';

import 'fake_card_api.dart';
import 'fake_visit_api.dart';
import 'fake_visit_camera.dart';
import 'fake_visit_photos.dart';
import 'fake_visit_recorder.dart';

const _photo = '/fake/visit-photo.jpg';

ProviderContainer _container(FakeVisitApi api, [FakeVisitPhotos? photos]) {
  final container = ProviderContainer(
    overrides: [
      visitRecorderProvider.overrideWithValue(FakeVisitRecorder()),
      visitCameraProvider.overrideWithValue(FakeVisitCamera()),
      ...mockCardsWith(visitApi: api, visitPhotos: photos),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// 카드 한 장을 고르고, [photo] 가 있으면 찍어 둔다. [inGallery] 는 갤러리에
/// 원본을 남겼는지다.
Future<VisitController> _prepare(
  ProviderContainer container, {
  String? photo = _photo,
  bool inGallery = true,
}) async {
  final cards = await container.read(cardsControllerProvider.future);
  container
      .read(cardsControllerProvider.notifier)
      .toggleSelected(cards.cards.first.cardId);
  if (photo != null) {
    await container
        .read(visitPhotoProvider.notifier)
        .replace(photo, inGallery: inGallery);
  }

  await container.read(visitControllerProvider.future);
  return container.read(visitControllerProvider.notifier);
}

/// [_prepare] 뒤 녹음을 시작하고 사진을 올릴 때까지 기다린다.
Future<VisitController> _start(
  ProviderContainer container, {
  String? photo = _photo,
  bool inGallery = true,
}) async {
  final visit = await _prepare(container, photo: photo, inGallery: inGallery);
  await visit.startRecording();
  // 사진은 녹음과 따로 올라가므로 끝날 때까지 기다린다.
  await pumpEventQueue();
  return visit;
}

VisitState _read(ProviderContainer container) =>
    container.read(visitControllerProvider).value!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('사진이 없으면 올리지 않는다', () async {
    final api = FakeVisitApi();
    final container = _container(api);

    await _start(container, photo: null);

    expect(api.calls, isNot(contains('photo')));
    expect(_read(container).photoUpload, VisitPhotoUpload.none);
    expect(_read(container).recording, isTrue);
  });

  test('회차를 만든 뒤 사진을 올리고, 갤러리에 원본이 있으면 사본을 지운다', () async {
    final api = FakeVisitApi();
    final photos = FakeVisitPhotos();
    final container = _container(api, photos);

    await _start(container);

    expect(api.calls, ['create', 'photo']);
    expect(api.photos.single, (
      sessionId: FakeVisitApi.sessionId,
      photoPath: _photo,
    ));
    expect(_read(container).photoUpload, VisitPhotoUpload.uploaded);
    expect(_read(container).recording, isTrue);
    expect(photos.discarded, [_photo]);
    expect(photos.kept, isEmpty);
  });

  test('갤러리에 원본이 없으면 올린 뒤에도 사본을 남긴다', () async {
    final api = FakeVisitApi();
    final photos = FakeVisitPhotos();
    final container = _container(api, photos);

    await _start(container, inGallery: false);

    expect(_read(container).photoUpload, VisitPhotoUpload.uploaded);
    expect(photos.discarded, isEmpty);
    expect(photos.kept, {_photo: FakeVisitApi.sessionId});
  });

  test('연결이 끊기면 한 번 더 올린다', () async {
    final api = FakeVisitApi()..photoFailures.add(const ApiNetworkFailure());
    final container = _container(api);

    await _start(container);

    expect(api.calls.where((c) => c == 'photo'), hasLength(2));
    expect(_read(container).photoUpload, VisitPhotoUpload.uploaded);
  });

  test('한 번 더 올려도 안 되면 실패로 두고, 다시 올리기로 올린다', () async {
    final api = FakeVisitApi()
      ..photoFailures.addAll([
        const ApiNetworkFailure(),
        const ApiServerFailure(
          statusCode: 503,
          errorCode: 'IMAGE_STORAGE_UNAVAILABLE',
          retryable: true,
        ),
      ]);
    final photos = FakeVisitPhotos();
    final container = _container(api, photos);

    final visit = await _start(container);

    expect(api.calls.where((c) => c == 'photo'), hasLength(2));
    expect(_read(container).photoUpload, VisitPhotoUpload.failed);
    expect(container.read(visitPhotoProvider), _photo, reason: '다시 올릴 파일');
    expect(photos.kept, {_photo: null});

    await visit.retryPhotoUpload();

    expect(api.calls.where((c) => c == 'photo'), hasLength(3));
    expect(_read(container).photoUpload, VisitPhotoUpload.uploaded);
    expect(photos.discarded, [_photo]);
  });

  test('다시 올려도 받지 않는 거절이면 다시 올리지 않는다', () async {
    final api = FakeVisitApi()
      ..photoFailures.add(
        const ApiServerFailure(
          statusCode: 422,
          errorCode: 'INVALID_IMAGE_FORMAT',
        ),
      );
    final container = _container(api);

    final visit = await _start(container);

    expect(api.calls.where((c) => c == 'photo'), hasLength(1));
    expect(_read(container).photoUpload, VisitPhotoUpload.rejected);

    await visit.retryPhotoUpload();
    expect(api.calls.where((c) => c == 'photo'), hasLength(1));
  });

  test('사진 파일을 찾지 못하면 알리고 녹음은 이어 간다', () async {
    final api = FakeVisitApi()
      ..photoFailures.add(PathNotFoundException(_photo, const OSError()));
    final container = _container(api);

    final visit = await _start(container);

    expect(api.calls.where((c) => c == 'photo'), hasLength(1));
    expect(_read(container).photoUpload, VisitPhotoUpload.missing);
    expect(_read(container).recording, isTrue);

    await visit.retryPhotoUpload();
    expect(api.calls.where((c) => c == 'photo'), hasLength(1));
  });

  test('올리는 중에 다시 찍으면 앞 결과가 새 사진을 건드리지 않고 새 사진을 올린다', () async {
    const retaken = '/fake/visit-photo-2.jpg';
    final api = FakeVisitApi()..photoGate = Completer();
    final photos = FakeVisitPhotos();
    final container = _container(api, photos);

    await _start(container);
    expect(_read(container).photoUpload, VisitPhotoUpload.uploading);

    await container
        .read(visitPhotoProvider.notifier)
        .replace(retaken, inGallery: true);
    expect(photos.discarded, isEmpty, reason: '올리는 중인 사진은 지우지 않는다');

    api.photoGate!.complete();
    await pumpEventQueue();

    expect(api.photos.map((p) => p.photoPath), [_photo, retaken]);
    expect(container.read(visitPhotoProvider), retaken);
    expect(_read(container).photoUpload, VisitPhotoUpload.uploaded);
    expect(photos.discarded, [_photo, retaken], reason: '둘 다 갤러리에 있다');
    expect(photos.kept, isEmpty);
  });

  test('올리는 중에 다시 찍고 앞 사진이 실패하면 앞 사진은 올리기가 끝난 뒤 지운다', () async {
    const retaken = '/fake/visit-photo-2.jpg';
    final api = FakeVisitApi()
      ..photoGate = Completer()
      ..photoFailures.add(
        const ApiServerFailure(
          statusCode: 422,
          errorCode: 'INVALID_IMAGE_FORMAT',
        ),
      );
    final photos = FakeVisitPhotos();
    final container = _container(api, photos);

    await _start(container);
    // 새 사진은 갤러리에 남기지 못해 올린 뒤에도 사본을 남긴다.
    await container
        .read(visitPhotoProvider.notifier)
        .replace(retaken, inGallery: false);
    expect(photos.discarded, isEmpty, reason: '올리는 중인 사진은 지우지 않는다');
    api.photoGate!.complete();
    await pumpEventQueue();

    expect(photos.discarded, [_photo]);
    expect(photos.kept, {retaken: FakeVisitApi.sessionId});
    expect(_read(container).photoUpload, VisitPhotoUpload.uploaded);
  });

  test('회차를 만들지 못하면 사진도 올리지 않는다', () async {
    final api = FakeVisitApi(failCreate: true);
    final container = _container(api);

    await _start(container);

    expect(api.calls, ['create']);
    expect(_read(container).photoUpload, VisitPhotoUpload.none);
    expect(container.read(visitPhotoProvider), _photo);
  });

  group('녹음 화면 안내', () {
    /// 시간 표시가 1초마다 다시 그려지므로 pumpAndSettle 을 쓰지 않는다.
    Future<void> openRecording(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      tester.view.physicalSize = const Size(1236, 2751);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      // 컨테이너를 닫기 전에 화면을 내린다. 화면이 내려가며 녹음을 닫는다.
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));

      // 실제 흐름처럼 녹음 전 안내가 뜬 뒤 녹음을 시작한다.
      await tester.runAsync(() async {
        final visit = await _prepare(container);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: buildAppTheme(),
              home: const RecordScreen(),
            ),
          ),
        );
        await visit.startRecording();
        await pumpEventQueue();
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pump();
    }

    testWidgets('올렸으면 아무것도 알리지 않는다', (tester) async {
      final container = _container(FakeVisitApi());
      await openRecording(tester, container);

      expect(find.textContaining('사진을 올리지 못'), findsNothing);
    });

    testWidgets('실패하면 알리고 다시 올리기로 올린다', (tester) async {
      final api = FakeVisitApi()
        ..photoFailures.addAll([
          const ApiNetworkFailure(),
          const ApiNetworkFailure(),
        ]);
      final container = _container(api);
      await openRecording(tester, container);

      // 알림 띠가 올라올 시간을 준다.
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('사진을 올리지 못했어요'), findsOneWidget);

      // 녹음 시간이 흘러도 닫을 때까지 남는다.
      await tester.pump(const Duration(seconds: 10));
      expect(find.text('사진 다시 올리기'), findsOneWidget);

      await tester.tap(find.text('사진 다시 올리기'));
      await tester.runAsync(pumpEventQueue);
      // 알림 띠가 내려갈 시간을 준다.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(_read(container).photoUpload, VisitPhotoUpload.uploaded);
      expect(find.textContaining('사진을 올리지 못'), findsNothing);
    });

    testWidgets('만남을 끝내면 안내를 닫는다', (tester) async {
      final api = FakeVisitApi()
        ..photoFailures.addAll([
          const ApiNetworkFailure(),
          const ApiNetworkFailure(),
        ]);
      final container = _container(api);
      await openRecording(tester, container);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('사진 다시 올리기'), findsOneWidget);

      // 가짜 장치만 부르므로 runAsync 밖에서 끝낸다. 안에서 끝내면 알림 띠가
      // 내려가는 애니메이션의 마무리가 테스트가 끝난 뒤에 돈다.
      await container
          .read(visitControllerProvider.notifier)
          .stopRecording(participantCount: 2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('사진 다시 올리기'), findsNothing);
    });

    testWidgets('사진 파일을 찾지 못하면 알리고 다시 올리기를 숨긴다', (tester) async {
      final api = FakeVisitApi()
        ..photoFailures.add(PathNotFoundException(_photo, const OSError()));
      final container = _container(api);
      await openRecording(tester, container);

      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('찍은 사진을 찾지 못해'), findsOneWidget);
      expect(find.textContaining('녹음은 그대로 이어져요'), findsOneWidget);
      expect(find.text('사진 다시 올리기'), findsNothing);
    });

    testWidgets('받지 않는 거절이면 다시 올리기를 숨긴다', (tester) async {
      final api = FakeVisitApi()
        ..photoFailures.add(
          const ApiServerFailure(statusCode: 413, errorCode: 'IMAGE_TOO_LARGE'),
        );
      final container = _container(api);
      await openRecording(tester, container);

      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('리포트에 사진 없이 담겨요'), findsOneWidget);
      expect(find.text('사진 다시 올리기'), findsNothing);
    });
  });
}
