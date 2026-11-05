import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../data/profile_api.dart';
import '../auth/auth_providers.dart';
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
  /// 사진 한 장을 [profileId] 프로필에 올린다. 실패하면 [PhotoUploadFailure] 를
  /// 던진다. [profileId] 는 기본 정보를 마칠 때 서버가 만든 ID 다(2-2).
  Future<void> upload(PickedPhoto photo, {String? profileId});
}

/// 서버에 보내지 않고 잠시 뒤 성공한 것으로 친다.
///
/// 로그인 세션 없이 들어온 경우다(구글 설정이 없는 디버그 빌드의 임시 건너뛰기).
/// 서버에 만든 프로필이 없어 올릴 곳이 없다.
class MockPhotoUploader implements PhotoUploader {
  const MockPhotoUploader();

  static const _delay = Duration(milliseconds: 800);

  @override
  Future<void> upload(PickedPhoto photo, {String? profileId}) =>
      Future<void>.delayed(_delay);
}

/// 3-1 로 서버에 올린다.
///
/// 서버의 거절은 `errorCode` 를 그대로 담아 [PhotoUploadFailure] 로 옮긴다. 서버가
/// 다시 시도해도 된다고 알린 경우와 서버에 닿지 못한 경우만 다시 올릴 수 있다.
class ServerPhotoUploader implements PhotoUploader {
  const ServerPhotoUploader(this._api);

  final ProfileApi _api;

  /// 서버에 만든 프로필이 없다. 기본 정보를 저장하지 못한 채 사진 단계에 온
  /// 경우라 다시 올려도 같다.
  static const missingProfile = 'PROFILE_NOT_CREATED';

  /// 응답을 읽지 못했다. 서버에는 올라갔을 수 있어 다시 올리지 않는다.
  static const unexpectedResponse = 'UNEXPECTED_RESPONSE';

  @override
  Future<void> upload(PickedPhoto photo, {String? profileId}) async {
    if (profileId == null) throw const PhotoUploadFailure(missingProfile);
    try {
      await _api.uploadPhoto(profileId, photo.path);
    } on ApiServerFailure catch (failure) {
      throw PhotoUploadFailure(
        failure.errorCode ?? 'HTTP_${failure.statusCode}',
        retryable: failure.retryable,
      );
    } on ApiNetworkFailure {
      throw const PhotoUploadFailure(
        PhotoUploadFailure.networkError,
        retryable: true,
      );
    } on ApiUnexpectedResponseFailure {
      throw const PhotoUploadFailure(unexpectedResponse);
    } on ApiSignedOutFailure {
      throw const PhotoUploadFailure('UNAUTHENTICATED');
    }
  }
}

/// [current] 사진 중 아직 올리지 못한 것을 한 장씩 차례로 올린다.
///
/// 이미 올라간 사진은 건너뛴다. 그래서 일부가 실패한 뒤 다시 부르면 실패한
/// 사진만 다시 올린다. 사진의 상태가 바뀔 때마다 [update] 로 알린다. 한 장을
/// 올린 뒤 [active] 가 `false` 면(화면이 사라짐) 멈춘다.
///
/// 입력 흐름의 사진 단계와 등록 뒤 사진 추가가 같이 쓴다.
Future<void> uploadPendingPhotos({
  required PhotoUploader uploader,
  required String? profileId,
  required List<SetupPhoto> Function() current,
  required void Function(int index, SetupPhoto photo) update,
  required bool Function() active,
}) async {
  for (var i = 0; i < current().length; i++) {
    final photo = current()[i];
    if (photo.status == PhotoUploadStatus.uploaded) continue;

    update(i, photo.withStatus(PhotoUploadStatus.uploading));
    PhotoUploadFailure? failure;
    try {
      await uploader.upload(photo.picked, profileId: profileId);
    } on PhotoUploadFailure catch (caught) {
      failure = caught;
    } catch (_) {
      failure = const PhotoUploadFailure(
        PhotoUploadFailure.networkError,
        retryable: true,
      );
    }
    if (!active()) return;
    update(
      i,
      failure == null
          ? photo.withStatus(PhotoUploadStatus.uploaded)
          : photo.withStatus(PhotoUploadStatus.failed, failure: failure),
    );
  }
}

/// 로그인했으면 서버에 올린다. 아니면 목 업로더를 쓴다.
final photoUploaderProvider = Provider<PhotoUploader>((ref) {
  final online = ref.watch(sessionProvider.select((s) => s != null));
  if (!online) return const MockPhotoUploader();
  return ServerPhotoUploader(ref.watch(profileApiProvider));
});

/// 업로드 실패를 보호자에게 보여줄 문구로 옮긴다.
String photoUploadFailureMessage(PhotoUploadFailure failure) =>
    switch (failure.errorCode) {
      'IMAGE_TOO_LARGE' => '사진 용량이 너무 커요. 이 사진은 빼고 다른 사진을 골라주세요.',
      'INVALID_IMAGE_FORMAT' => 'JPEG나 PNG 사진만 올릴 수 있어요. 이 사진은 빼주세요.',
      'PHOTO_LIMIT_EXCEEDED' => '사진은 $maxProfilePhotos장까지만 올릴 수 있어요.',
      'UNAUTHENTICATED' => '로그인이 풀렸어요. 다시 로그인해주세요.',
      _ => '사진을 올리지 못했어요. 잠시 뒤 다시 시도해주세요.',
    };
