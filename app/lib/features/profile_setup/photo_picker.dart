import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// 프로필 사진은 프로필당 최대 5장이다(`docs/architecture/api-spec.md` 3-1).
const maxProfilePhotos = 5;

/// 기기 앨범에서 고른 사진 한 장이다.
///
/// 아직 서버에 올리지 않았으므로 단말의 파일 경로만 가진다. 경로는 화면에
/// 보여줄 때와 올릴 때만 쓰고 저장하지 않는다.
class PickedPhoto {
  const PickedPhoto(this.path);

  final String path;
}

/// 앨범에서 사진을 고른다.
///
/// 화면은 이 인터페이스만 보고 플러그인을 직접 부르지 않는다. 테스트는
/// [photoPickerProvider] 를 override 한다(ADR-005).
abstract interface class PhotoPicker {
  /// 최대 [limit] 장을 고른다. 사용자가 그만두면 빈 목록이다.
  Future<List<PickedPhoto>> pick({required int limit});
}

/// `image_picker` 로 기기 앨범을 연다.
///
/// 안드로이드에서는 시스템 사진 선택기를 쓰므로 저장소 권한을 따로 받지 않는다.
class DevicePhotoPicker implements PhotoPicker {
  DevicePhotoPicker([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<List<PickedPhoto>> pick({required int limit}) async {
    if (limit < 1) return const [];

    // 여러 장 고르기는 2장 이상만 제한할 수 있어 한 장 남았을 때는 따로 연다.
    if (limit == 1) {
      final file = await _picker.pickImage(source: ImageSource.gallery);
      return [if (file != null) PickedPhoto(file.path)];
    }

    final files = await _picker.pickMultiImage(limit: limit);
    return [for (final file in files) PickedPhoto(file.path)];
  }
}

final photoPickerProvider = Provider<PhotoPicker>((ref) => DevicePhotoPicker());
