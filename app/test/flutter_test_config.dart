// `test/` 아래 모든 테스트보다 먼저 돈다(flutter_test 의 testExecutable).

import 'dart:async';

import 'package:saerok/widgets/mascot.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // 홈 마스코트는 계속 둥실 떠 있어 pumpAndSettle 이 끝나지 않는다. 마스코트
  // 자체를 보는 테스트는 켜고 pump 로 시간을 흘린다.
  Mascot.motion = false;
  await testMain();
}
