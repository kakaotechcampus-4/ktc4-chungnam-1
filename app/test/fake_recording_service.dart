// 기기 없이 녹음 알림 서비스를 띄우고 내리는 시점을 확인하려고 쓰는 대역이다.
//
// 실제 서비스와 알림은 `RecordingService.kt` 가 띄우므로 단위 테스트에서 볼 수
// 없다. 면회 녹음이 언제 무엇을 요청하는지만 여기에 남긴다.

import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:saerok/features/visit/recording_service.dart';

class FakeRecordingServicePlatform implements RecordingServicePlatform {
  FakeRecordingServicePlatform({
    this.grantsPermission = true,
    this.refusesShow = false,
  });

  /// 알림 권한 창에서 허용할지.
  bool grantsPermission;

  /// 서비스를 띄우지 못해 `false` 를 돌려줄지.
  bool refusesShow;

  /// 받은 요청 순서다. `show:<제목>`, `hide`, `permission`.
  final List<String> calls = [];

  /// 마지막 `show` 의 알림 본문.
  String? lastText;

  /// `hide` 를 받을 때 부른다. 다른 대역의 상태를 그 순간에 보려고 쓴다.
  void Function()? onHide;

  /// 권한 창의 답을 테스트가 정할 때 쓴다. `null` 이면 바로 답한다.
  Completer<bool>? pendingPermission;

  /// 마지막으로 띄우거나 내린 요청대로라면 지금 서비스가 떠 있다. 권한 묻기는
  /// 서비스를 바꾸지 않으므로 보지 않는다.
  bool get isShown {
    final changes = calls.where((c) => c != 'permission');
    return changes.isNotEmpty && changes.last.startsWith('show:');
  }

  /// 받은 `show` 의 제목들.
  List<String> get shownTitles => [
    for (final call in calls)
      if (call.startsWith('show:')) call.substring('show:'.length),
  ];

  @override
  Future<bool> show({required String title, required String text}) async {
    calls.add('show:$title');
    lastText = text;
    return !refusesShow;
  }

  @override
  Future<void> hide() async {
    calls.add('hide');
    onHide?.call();
  }

  @override
  Future<bool> requestNotificationPermission() async {
    calls.add('permission');
    final pending = pendingPermission;
    if (pending != null) return pending.future;
    return grantsPermission;
  }

  /// 이 대역을 끼우는 override.
  Override get asOverride =>
      recordingServicePlatformProvider.overrideWithValue(this);
}
