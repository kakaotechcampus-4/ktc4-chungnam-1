import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/providers.dart';
import 'setup_controller.dart';

/// 소중한 분 등록을 여는 길이다. 프로필 전환 화면과 홈이 함께 쓴다.
///
/// 모두 `입력 중` 슬롯으로 연다(`/profile/create?adding=`). 중간에 나가도 입력한
/// 값이 슬롯에 남고, 다시 열면 가 본 가장 먼 단계에서 이어서 입력한다.

/// 새로운 분을 등록하기 시작한다. 다른 분을 입력하던 중이어도 그 입력은
/// `입력 중` 으로 남겨 두고 새로 시작한다. 빈자리가 없으면 `false` 다.
bool startProfileSetup(BuildContext context, WidgetRef ref) {
  final id = ref.read(careProfilesProvider.notifier).beginAdding();
  if (id == null) return false;
  ref.invalidate(setupControllerProvider);
  ref.read(pendingSetupsProvider.notifier).save(id, const SetupState());
  context.push(AppRoutes.profileAddOf(id));
  return true;
}

/// `입력 중` 인 분의 입력을 가 본 가장 먼 단계부터 다시 연다.
///
/// 서버에서 불러온 입력 중인 분은 앱에 남은 입력이 없으니 서버 값에 단말 초안을
/// 더해 연다([SetupController.resume]). 초안을 읽는 동안 다시 눌러도 한 번만
/// 연다.
Future<void> resumeProfileSetup(
  BuildContext context,
  WidgetRef ref,
  String id,
) async {
  if (_resuming) return;
  _resuming = true;
  try {
    await ref.read(setupControllerProvider.notifier).resume(id);
  } finally {
    _resuming = false;
  }
  if (!context.mounted) return;
  context.push(AppRoutes.profileAddOf(id));
}

/// [resumeProfileSetup] 이 단말 초안을 읽는 중이다.
bool _resuming = false;

/// 등록을 마친 분이 없을 때 홈의 `오늘의 대화카드 받기` 가 부른다.
///
/// 가입 직후에는 정보를 묻지 않고 홈부터 보여주므로, 카드를 받으려는 이때 기본
/// 정보 입력을 바로 연다. 입력하다 나간 분이 있으면 그 입력을 이어서 열고,
/// 없으면 새로 시작한다. 빈자리가 없으면 프로필 전환 화면으로 보낸다.
void openFirstProfileSetup(BuildContext context, WidgetRef ref) {
  final pending = ref
      .read(careProfilesProvider)
      .entries
      .where((e) => e.pending)
      .firstOrNull;
  if (pending != null) {
    unawaited(resumeProfileSetup(context, ref, pending.id));
    return;
  }
  if (!startProfileSetup(context, ref)) {
    context.push(AppRoutes.profileSwitch);
  }
}
