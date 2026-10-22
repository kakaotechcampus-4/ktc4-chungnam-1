// 기기 갤러리 대신 쓰는 면회 사진 갤러리 대역이다. 실제 갤러리에 저장하지 않는다.

import 'package:saerok/features/visit/visit_gallery.dart';

class FakeVisitGallery implements VisitGallery {
  FakeVisitGallery({this.fails = false});

  /// `true` 면 저장하지 못한 것으로 답한다.
  bool fails;

  /// 갤러리에 남긴 사진 경로.
  final saved = <String>[];

  @override
  Future<bool> save(String path) async {
    if (fails) return false;
    saved.add(path);
    return true;
  }
}
