// `test/` 아래 모든 테스트보다 먼저 돈다(flutter_test 의 testExecutable).

import 'dart:async';

import 'package:saerok/features/life_story/life_story_cover_screen.dart';
import 'package:saerok/widgets/mascot.dart';
import 'package:saerok/widgets/recording_pulse.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // 홈 마스코트는 계속 둥실 떠 있어 pumpAndSettle 이 끝나지 않는다. 마스코트
  // 자체를 보는 테스트는 켜고 pump 로 시간을 흘린다.
  Mascot.motion = false;
  // 앨범 표지 바탕의 꽃잎도 계속 날아다닌다.
  AlbumPetals.motion = false;
  // 녹음 중 마이크 원 둘레의 물결도 녹음하는 동안 계속 퍼진다. 끄면 움직임
  // 줄이기와 같은 고정 고리를 그린다.
  RecordingPulse.motion = false;
  await testMain();
}
