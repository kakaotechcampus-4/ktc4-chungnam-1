import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'photo_picker.dart';

/// 프로필 사진 한 장의 업로드 상태다.
enum PhotoUploadStatus {
  /// 고르기만 했다. 아직 올리지 않았다.
  waiting,
  uploading,
  uploaded,
  failed,
}

/// 업로드가 실패한 이유다.
///
/// `errorCode` 는 `docs/architecture/api-spec.md` 3-1 의 값을 쓴다. 서버에 닿지
/// 못한 경우는 [networkError] 다.
class PhotoUploadFailure implements Exception {
  const PhotoUploadFailure(this.errorCode, {this.retryable = false});

  /// 서버에 닿지 못했다. 다시 시도할 수 있다.
  static const networkError = 'NETWORK_ERROR';

  final String errorCode;

  /// 같은 사진을 다시 올리면 될 수 있는지.
  final bool retryable;

  @override
  String toString() => 'PhotoUploadFailure($errorCode)';
}

/// 입력 흐름에 담긴 사진 한 장과 그 업로드 상태다.
class SetupPhoto {
  const SetupPhoto(
    this.picked, {
    this.status = PhotoUploadStatus.waiting,
    this.failure,
  });

  final PickedPhoto picked;
  final PhotoUploadStatus status;

  /// [PhotoUploadStatus.failed] 일 때만 있다.
  final PhotoUploadFailure? failure;

  String get path => picked.path;

  SetupPhoto withStatus(
    PhotoUploadStatus status, {
    PhotoUploadFailure? failure,
  }) => SetupPhoto(picked, status: status, failure: failure);
}

/// 프로필 사진을 서버에 올린다(`docs/architecture/api-spec.md` 3-1).
///
/// 화면은 이 인터페이스만 본다. 테스트는 [photoUploaderProvider] 를 override
/// 한다(ADR-005).
abstract interface class PhotoUploader {
  /// 사진 한 장을 올린다. 실패하면 [PhotoUploadFailure] 를 던진다.
  Future<void> upload(PickedPhoto photo);
}

/// 서버에 보내지 않고 잠시 뒤 성공한 것으로 친다.
///
/// 3-1 업로드 API 와 그 앞의 프로필 생성(2-2)이 앱에 아직 연결되지 않았다.
/// 연결되면 이 자리를 실제 호출이 대신한다.
class MockPhotoUploader implements PhotoUploader {
  const MockPhotoUploader();

  static const _delay = Duration(milliseconds: 800);

  @override
  Future<void> upload(PickedPhoto photo) =>
      Future<void>.delayed(_delay);
}

final photoUploaderProvider = Provider<PhotoUploader>(
  (ref) => const MockPhotoUploader(),
);

/// 업로드 실패를 보호자에게 보여줄 문구로 옮긴다.
String photoUploadFailureMessage(PhotoUploadFailure failure) =>
    switch (failure.errorCode) {
      'IMAGE_TOO_LARGE' => '사진 용량이 너무 커요. 이 사진은 빼고 다른 사진을 골라주세요.',
      'INVALID_IMAGE_FORMAT' => 'JPEG나 PNG 사진만 올릴 수 있어요. 이 사진은 빼주세요.',
      'PHOTO_LIMIT_EXCEEDED' => '사진은 $maxProfilePhotos장까지만 올릴 수 있어요.',
      _ => '사진을 올리지 못했어요. 잠시 뒤 다시 시도해주세요.',
    };
