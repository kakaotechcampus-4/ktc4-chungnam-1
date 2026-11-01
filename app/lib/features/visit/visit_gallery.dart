/// 면회 전에 찍은 사진의 원본을 기기 갤러리에 남긴다(D-1).
///
/// 갤러리의 사진은 보호자의 것이다(PR #136 리뷰). 다시 찍어 밀려난 사진도
/// 남기며, 앱은 갤러리에 남긴 사진을 고치거나 지우지 않는다. 앱을 지우거나
/// 탈퇴해도 그대로 있다. 앱이 서버에 올리려고 따로 둔 사본은
/// [VisitPhotos] 가 관리한다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';

import 'visit_photos.dart';

abstract interface class VisitGallery {
  /// [path] 의 사진을 갤러리에 남긴다. 남기지 못하면 `false` 다.
  ///
  /// 남기지 못해도 면회는 이어간다. 그때는 앱의 사본이 유일한 파일이므로
  /// [VisitPhotos] 가 지우지 않는다.
  Future<bool> save(String path);
}

/// `gal` 로 갤러리의 '새록' 앨범에 남긴다. 앨범이 없으면 만든다.
///
/// 안드로이드 11 이상은 권한 없이 저장한다. 10 이하는 저장할 때 저장소 권한을
/// 묻는다(`AndroidManifest.xml`).
class DeviceVisitGallery implements VisitGallery {
  const DeviceVisitGallery();

  static const album = '새록';

  @override
  Future<bool> save(String path) async {
    try {
      if (!await Gal.hasAccess(toAlbum: true) &&
          !await Gal.requestAccess(toAlbum: true)) {
        return false;
      }
      await Gal.putImage(path, album: album);
      return true;
    } on GalException {
      return false;
    } on Exception {
      // 플러그인이 없거나(테스트, 지원하지 않는 기기) 채널이 실패했다.
      return false;
    }
  }
}

final visitGalleryProvider = Provider<VisitGallery>(
  (ref) => const DeviceVisitGallery(),
);
