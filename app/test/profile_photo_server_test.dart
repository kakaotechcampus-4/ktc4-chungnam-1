// 로그인한 상태의 프로필 사진이 서버(`api-spec.md` 3-1, 3-2, 2-3)와 이어지는지
// 확인한다.
//
// 서버는 `FakeProfileServer` 다. 사진 파일과 값은 모두 합성이다.

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/auth_api.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/features/auth/auth_providers.dart';
import 'package:saerok/features/auth/auth_session.dart';
import 'package:saerok/features/profile_setup/photo_picker.dart';
import 'package:saerok/features/profile_setup/photo_uploader.dart';
import 'package:saerok/features/profile_setup/setup_controller.dart';

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

/// 합성 PNG 파일 하나. 서버가 형식을 판별하지 않는 가짜라 내용은 몇 바이트면 된다.
Future<PickedPhoto> _syntheticPhoto() async {
  final dir = await Directory.systemTemp.createTemp('saerok_photo_test');
  addTearDown(() => dir.delete(recursive: true));
  final file = File('${dir.path}/synthetic.png')
    ..writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]);
  return PickedPhoto(file.path);
}

/// 로그인한 컨테이너. 서버에는 [photos] 를 가진 분 p1 이 있다.
Future<ProviderContainer> _signedIn(
  FakeProfileServer server, {
  Duration poll = const Duration(milliseconds: 1),
  // 넘기지 않으면 계정 동의를 덮어쓰지 않는다(계정을 읽지 못하면 지금처럼 묻는다).
  bool? analysisWanted,
}) async {
  final container = ProviderContainer(
    overrides: [
      server.override,
      photoAnalysisPollIntervalProvider.overrideWithValue(poll),
      if (analysisWanted != null)
        photoAnalysisWantedProvider.overrideWithValue(analysisWanted),
    ],
  );
  addTearDown(container.dispose);
  container.listen(careProfilesProvider, (_, _) {});
  container.read(sessionProvider.notifier).restore(_session());
  for (var i = 0; i < 200; i++) {
    if (container.read(careProfilesProvider).hasSelected) break;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  return container;
}

/// [check] 가 참이 될 때까지 기다린다.
Future<void> _until(bool Function() check) async {
  for (var i = 0; i < 200; i++) {
    if (check()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('기다린 상태가 오지 않았다');
}

const _filled = SetupDraft(
  name: '김새록',
  gender: 'female',
  birthYear: 1943,
  birthMonth: 3,
  birthDay: 12,
  stage: ConditionStage.mildDementia,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('사진 올리기(3-1)', () {
    test('기본 정보로 만든 프로필에 image 필드로 올린다', () async {
      final server = FakeProfileServer();
      final container = await _signedIn(server);
      final controller = container.read(setupControllerProvider.notifier);
      controller.updateDraft(_filled);
      await controller.submitBasicInfo();

      controller.addPhotos([await _syntheticPhoto()]);
      await controller.uploadPhotos();

      final upload = server.requests.lastWhere((r) => r.method == 'POST');
      expect(upload.path, '/api/v1/profiles/server-1/photos');
      expect(server.uploads.single, contains('name="image"'));
      expect(
        container.read(setupControllerProvider).draft.photos.single.status,
        PhotoUploadStatus.uploaded,
      );
      expect(server.profiles.single['photos'], hasLength(1));
    });

    test('서버의 거절은 errorCode 를 담아 실패로 남긴다', () async {
      final server =
          FakeProfileServer(profiles: [FakeProfileServer.profile(id: 'p1')])
            ..failures['POST /api/v1/profiles/p1/photos'] = (
              status: 413,
              errorCode: 'IMAGE_TOO_LARGE',
            );
      final uploader = ServerPhotoUploader(server.api);

      await expectLater(
        uploader.upload(await _syntheticPhoto(), profileId: 'p1'),
        throwsA(
          isA<PhotoUploadFailure>()
              .having((f) => f.errorCode, 'errorCode', 'IMAGE_TOO_LARGE')
              .having((f) => f.retryable, 'retryable', isFalse),
        ),
      );
      expect(
        photoUploadFailureMessage(const PhotoUploadFailure('IMAGE_TOO_LARGE')),
        '사진 용량이 너무 커요. 이 사진은 빼고 다른 사진을 골라주세요.',
      );
    });

    for (final (status, errorCode, message) in [
      (422, 'INVALID_IMAGE_FORMAT', 'JPEG나 PNG 사진만 올릴 수 있어요. 이 사진은 빼주세요.'),
      (409, 'PHOTO_LIMIT_EXCEEDED', '사진은 5장까지만 올릴 수 있어요.'),
    ]) {
      test('$status $errorCode 는 다시 올리지 않고 그 이유를 알린다', () async {
        final server =
            FakeProfileServer(profiles: [FakeProfileServer.profile(id: 'p1')])
              ..failures['POST /api/v1/profiles/p1/photos'] = (
                status: status,
                errorCode: errorCode,
              );

        final PhotoUploadFailure failure;
        try {
          await ServerPhotoUploader(
            server.api,
          ).upload(await _syntheticPhoto(), profileId: 'p1');
          fail('실패해야 한다');
        } on PhotoUploadFailure catch (caught) {
          failure = caught;
        }

        expect(failure.errorCode, errorCode);
        expect(failure.retryable, isFalse);
        expect(photoUploadFailureMessage(failure), message);
      });
    }

    test('서버가 다시 시도해도 된다고 하거나 닿지 못하면 다시 올릴 수 있다', () async {
      final server =
          FakeProfileServer(profiles: [FakeProfileServer.profile(id: 'p1')])
            ..failures['POST /api/v1/profiles/p1/photos'] = (
              status: 503,
              errorCode: 'IMAGE_STORAGE_UNAVAILABLE',
            )
            ..retryableErrors.add('IMAGE_STORAGE_UNAVAILABLE');
      final uploader = ServerPhotoUploader(server.api);
      final photo = await _syntheticPhoto();

      await expectLater(
        uploader.upload(photo, profileId: 'p1'),
        throwsA(
          isA<PhotoUploadFailure>().having(
            (f) => f.retryable,
            'retryable',
            isTrue,
          ),
        ),
      );

      server
        ..failures.clear()
        ..offline = true;
      await expectLater(
        uploader.upload(photo, profileId: 'p1'),
        throwsA(
          isA<PhotoUploadFailure>()
              .having(
                (f) => f.errorCode,
                'errorCode',
                PhotoUploadFailure.networkError,
              )
              .having((f) => f.retryable, 'retryable', isTrue),
        ),
      );
    });

    test('서버에 만든 프로필이 없으면 보내지 않는다', () async {
      final server = FakeProfileServer();
      final uploader = ServerPhotoUploader(server.api);

      await expectLater(
        uploader.upload(await _syntheticPhoto()),
        throwsA(
          isA<PhotoUploadFailure>().having(
            (f) => f.errorCode,
            'errorCode',
            ServerPhotoUploader.missingProfile,
          ),
        ),
      );
      expect(server.requests, isEmpty);
    });

    test('로그인하지 않았으면 서버에 보내지 않는 목 업로더를 쓴다', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(photoUploaderProvider), isA<MockPhotoUploader>());
    });
  });

  group('프로필의 사진(2-3, 3-2)', () {
    test('서버에 저장한 분은 서버에 올린 사진을 읽는다', () async {
      final server = FakeProfileServer(
        profiles: [
          FakeProfileServer.profile(
            id: 'p1',
            setupStatus: 'completed',
            photos: [FakeProfileServer.photo(id: 'photo-a')],
          ),
        ],
      );
      final container = await _signedIn(server);
      container.listen(serverProfilePhotosProvider, (_, _) {});

      final photos = await container.read(serverProfilePhotosProvider.future);

      expect(photos!.single.photoId, 'photo-a');
      expect(photos.single.imageUrl, 'https://example.test/photo-a.jpg');
      final bundle = await container.read(profileProvider.future);
      expect(bundle!.photos, isEmpty, reason: '서버에 저장한 분에게 목 사진을 붙이지 않는다');
    });

    test('분석 중인 사진은 3-2 로 다 될 때까지 묻는다', () async {
      final server = FakeProfileServer(
        profiles: [
          FakeProfileServer.profile(
            id: 'p1',
            setupStatus: 'completed',
            photos: [
              FakeProfileServer.photo(id: 'photo-a', analysisStatus: 'pending'),
              FakeProfileServer.photo(id: 'photo-b'),
            ],
          ),
        ],
      );
      server.analysisResults['photo-a'] = ['processing', 'completed'];
      final container = await _signedIn(server);
      container.listen(serverProfilePhotosProvider, (_, _) {});

      await _until(
        () =>
            container
                .read(serverProfilePhotosProvider)
                .value
                ?.first
                .analysisStatus ==
            PhotoAnalysisStatus.completed,
      );

      final photos = container.read(serverProfilePhotosProvider).value!;
      expect(photos.first.description, '합성 사진 설명이에요.');
      expect(
        server.requests.where(
          (r) => r.path == '/api/v1/profile-photos/photo-a',
        ),
        hasLength(2),
      );
      expect(
        server.requests.where(
          (r) => r.path == '/api/v1/profile-photos/photo-b',
        ),
        isEmpty,
        reason: '분석을 마친 사진은 묻지 않는다',
      );
    });

    test('AI 사진 분석에 동의하지 않은 계정의 사진은 묻지 않는다', () async {
      final server = FakeProfileServer(
        profiles: [
          FakeProfileServer.profile(
            id: 'p1',
            setupStatus: 'completed',
            photos: [
              FakeProfileServer.photo(id: 'photo-a', analysisStatus: 'pending'),
            ],
          ),
        ],
      );
      server.analysisResults['photo-a'] = ['completed'];
      final container = await _signedIn(server, analysisWanted: false);
      container.listen(serverProfilePhotosProvider, (_, _) {});

      await _until(
        () => container.read(serverProfilePhotosProvider).value != null,
      );
      // 묻는 간격(1ms)의 몇십 배를 기다려도 3-2 를 부르지 않는다.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        container.read(serverProfilePhotosProvider).value!.first.analysisStatus,
        PhotoAnalysisStatus.pending,
      );
      expect(
        server.requests.where(
          (r) => r.path == '/api/v1/profile-photos/photo-a',
        ),
        isEmpty,
        reason: '동의하지 않았으면 worker 가 분석하지 않으므로 끝나지 않는다',
      );
    });

    test('분석에 실패한 사진은 실패로 바꾸고 더 묻지 않는다', () async {
      final server = FakeProfileServer(
        profiles: [
          FakeProfileServer.profile(
            id: 'p1',
            setupStatus: 'completed',
            photos: [
              FakeProfileServer.photo(id: 'photo-a', analysisStatus: 'pending'),
            ],
          ),
        ],
      );
      server.analysisResults['photo-a'] = ['failed'];
      final container = await _signedIn(server);
      container.listen(serverProfilePhotosProvider, (_, _) {});

      await _until(
        () =>
            container
                .read(serverProfilePhotosProvider)
                .value
                ?.single
                .analysisStatus ==
            PhotoAnalysisStatus.failed,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        server.requests.where(
          (r) => r.path == '/api/v1/profile-photos/photo-a',
        ),
        hasLength(1),
      );
    });

    test('읽는 중 갤러리를 닫으면 늦게 온 분석 중 사진으로 묻기 시작하지 않는다', () async {
      final server = FakeProfileServer(
        profiles: [
          FakeProfileServer.profile(
            id: 'p1',
            setupStatus: 'completed',
            photos: [
              FakeProfileServer.photo(id: 'photo-a', analysisStatus: 'pending'),
            ],
          ),
        ],
      );
      final container = await _signedIn(server);
      final answer = Completer<void>();
      server.holds['GET /api/v1/profiles/p1'] = answer.future;

      final gallery = container.listen(serverProfilePhotosProvider, (_, _) {});
      await _until(
        () => server.requests.any((r) => r.path == '/api/v1/profiles/p1'),
      );
      // 응답이 오기 전에 갤러리를 닫는다.
      gallery.close();
      await Future<void>.delayed(Duration.zero);
      answer.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        server.requests.where(
          (r) => r.path == '/api/v1/profile-photos/photo-a',
        ),
        isEmpty,
      );
    });

    test('로그인하지 않았으면 서버에 묻지 않고 목 사진을 쓴다', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.listen(serverProfilePhotosProvider, (_, _) {});

      expect(await container.read(serverProfilePhotosProvider.future), isNull);
    });
  });
}
