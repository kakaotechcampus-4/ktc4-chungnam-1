import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'visit_photos.dart';

/// 카메라를 열지 못했다. 화면은 사진 없이 시작하도록 안내한다.
class VisitCameraUnavailable implements Exception {
  const VisitCameraUnavailable(this.reason);

  /// 플러그인이 알려준 이유다. 화면 문구에는 쓰지 않는다.
  final String reason;

  @override
  String toString() => 'VisitCameraUnavailable($reason)';
}

/// 면회 전 사진을 찍는다(D-1).
///
/// 화면은 이 인터페이스만 보고 플러그인을 직접 부르지 않는다. 테스트는
/// [visitCameraProvider] 를 override 한다(ADR-005).
abstract interface class VisitCamera {
  /// 카메라로 한 장 찍는다. 사용자가 찍지 않고 나오면 `null` 이다.
  ///
  /// 카메라를 열지 못하면 [VisitCameraUnavailable] 을 던진다. 돌려준 경로는
  /// 카메라 앱이 남긴 임시 파일이며 [VisitPhotos.keep] 으로 옮겨 둔다.
  Future<String?> capture();
}

/// `image_picker` 로 기기 카메라 앱을 연다.
///
/// 안드로이드는 시스템 카메라 앱에 촬영을 맡기므로 카메라 권한을 따로 받지
/// 않는다. 매니페스트에 `CAMERA` 권한을 넣으면 실행 중 권한 요청이 필요해지니
/// 넣지 않는다.
class DeviceVisitCamera implements VisitCamera {
  DeviceVisitCamera([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// 5-2 의 크기 상한(기본 20MB) 안에 들도록 긴 변과 화질을 줄인다.
  static const _maxSide = 2048.0;
  static const _quality = 85;

  @override
  Future<String?> capture() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: _maxSide,
        maxHeight: _maxSide,
        imageQuality: _quality,
      );
      return file?.path;
    } on PlatformException catch (e) {
      throw VisitCameraUnavailable(e.code);
    }
  }
}

final visitCameraProvider = Provider<VisitCamera>((ref) => DeviceVisitCamera());

/// 이번 회차에 찍어 둔 면회 사진의 기기 안 경로다. 찍지 않았으면 `null` 이다.
///
/// 경로는 앱이 켜져 있는 동안만 들고 있다. 새 회차를 시작하거나 로그아웃할 때
/// invalidate 되지만 사진 파일은 지우지 않는다([VisitPhotos]). 다시 찍으면 앞
/// 사진이 올리지 않은 것일 때만 지운다.
class VisitPhotoNotifier extends Notifier<String?> {
  /// 서버에 올리고 있는 사진. 그사이 다시 찍어도 이 파일은 바로 지우지 않는다.
  final _sending = <String>{};

  /// 올리는 중에 다시 찍어 밀려난 사진. 올리기가 끝나면 올리지 못한 것만 지운다.
  final _replaced = <String>{};

  @override
  String? build() {
    ref.watch(visitPhotosProvider);
    _sending.clear();
    _replaced.clear();
    return null;
  }

  /// 카메라가 남긴 [capturedPath] 를 앱 전용 공간으로 옮겨 이번 사진으로 둔다.
  ///
  /// 옮기지 못하면 [FileSystemException] 이 그대로 나간다.
  Future<void> replace(String capturedPath) async {
    final photos = ref.read(visitPhotosProvider);
    final kept = await photos.keep(capturedPath);
    if (!ref.mounted) return;
    final previous = state;
    state = kept;
    if (previous == null || previous == kept) return;
    if (_sending.contains(previous)) {
      _replaced.add(previous);
    } else {
      await photos.discard(previous);
    }
  }

  /// [path] 를 서버에 올리기 시작했다.
  void sending(String path) => _sending.add(path);

  /// [path] 올리기를 마쳤다. 그사이 다시 찍어 밀려났으면 지운다. 올린 사진이면
  /// [VisitPhotos.discard] 가 남긴다.
  Future<void> sent(String path) async {
    if (!ref.mounted) return;
    _sending.remove(path);
    if (_replaced.remove(path)) {
      await ref.read(visitPhotosProvider).discard(path);
    }
  }
}

final visitPhotoProvider = NotifierProvider<VisitPhotoNotifier, String?>(
  VisitPhotoNotifier.new,
);
