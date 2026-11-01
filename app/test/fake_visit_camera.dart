// 실제 카메라 대신 쓰는 면회 사진 카메라 대역이다. 경로는 모두 가짜다.

import 'dart:async';

import 'package:saerok/features/visit/visit_camera.dart';

/// 정해 둔 순서대로 찍은 결과를 돌려주는 카메라다. 실제 카메라는 열지 않는다.
///
/// 결과는 경로(찍음), `null`(찍지 않고 나옴), [VisitCameraUnavailable](열지
/// 못함) 중 하나다. 경로는 기기에 없는 가짜 경로다.
class FakeVisitCamera implements VisitCamera {
  FakeVisitCamera([List<Object?>? results]) : _results = results ?? [];

  final List<Object?> _results;
  int captures = 0;

  /// 있으면 끝날 때까지 카메라가 열려 있는 것으로 친다.
  Completer<void>? gate;

  @override
  Future<String?> capture() async {
    captures++;
    final gate = this.gate;
    if (gate != null) await gate.future;
    final result = _results.removeAt(0);
    if (result is VisitCameraUnavailable) throw result;
    return result as String?;
  }
}
