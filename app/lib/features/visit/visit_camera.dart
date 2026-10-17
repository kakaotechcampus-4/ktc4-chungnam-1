import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

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
  /// 카메라를 열지 못하면 [VisitCameraUnavailable] 을 던진다.
  Future<String?> capture();

  /// 찍은 사진 파일을 기기에서 지운다. 파일이 없어도 실패하지 않는다.
  Future<void> discard(String path);
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

  @override
  Future<void> discard(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      // 이미 없으면 그대로 둔다.
    }
  }
}

final visitCameraProvider = Provider<VisitCamera>((ref) => DeviceVisitCamera());

/// 이번 회차에 찍어 둔 면회 사진의 기기 안 경로다. 찍지 않았으면 `null` 이다.
///
/// 앱이 켜져 있는 동안만 들고 있다. 다시 찍으면 앞 사진 파일을 지운다. 새
/// 회차를 시작할 때 invalidate 되며 그때도 남은 파일을 지운다.
class VisitPhotoNotifier extends Notifier<String?> {
  late VisitCamera _camera;

  /// [state] 와 같은 값이다. 비울 때는 ref 와 state 를 쓸 수 없어 따로 둔다.
  String? _path;

  @override
  String? build() {
    _camera = ref.watch(visitCameraProvider);
    _path = null;
    ref.onDispose(() {
      final path = _path;
      if (path != null) _camera.discard(path);
    });
    return null;
  }

  void replace(String path) {
    final previous = _path;
    state = _path = path;
    if (previous != null && previous != path) _camera.discard(previous);
  }

  /// 서버에 올린 뒤 기기의 사진 파일을 지운다.
  void forget() {
    final path = _path;
    state = _path = null;
    if (path != null) _camera.discard(path);
  }
}

final visitPhotoProvider = NotifierProvider<VisitPhotoNotifier, String?>(
  VisitPhotoNotifier.new,
);
