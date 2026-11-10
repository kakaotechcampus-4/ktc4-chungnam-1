/// 면회 흐름에서 로그인이 풀렸을 때 로그인 화면으로 가기 전에 띄우는 확인 창.
///
/// 세션을 다시 받지 못하면 앱은 로그인 화면으로 간다(`session_refresher.dart`).
/// 면회 흐름에서는 설명 없이 옮기지 않고 이 창으로 먼저 알린다(UX 점검 8번,
/// 2026-11-10). 녹음 중이었으면 녹음을 이어 가다가 만남을 끝내거나 화면을 떠나
/// 파일을 닫고 기기 기록을 남긴 뒤에 뜬다([sessionHoldProvider]). 그 녹음은 다른
/// 녹음처럼 기기에 남아, 같은 계정으로 다시 로그인하면 홈의 이어 하기로 보낼 수
/// 있다(`app/README.md` 의 녹음 보관).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_refresher.dart' show sessionHoldProvider;
import '../profile/profile_dialogs.dart' show showNoticeDialog;
import 'pending_uploads.dart';
import 'visit_controller.dart';

/// 창의 문구다. FE 초안이며 제품 문구로 확정하려면 PM 확인이 필요하다.
///
/// 줄은 낱말 사이에서 직접 나눈다. 360dp 화면에서 글자를 1.3배로 키워도 한 줄이
/// 넘치지 않는 길이로 두었다. 그대로 두면 낱말 가운데에서 줄이 바뀐다.
abstract final class VisitSignedOutMessages {
  static const title = '로그인이 풀렸어요';

  /// 이번 면회의 녹음 파일을 닫아 기기에 남겼다.
  static const recordingKept =
      '녹음은 휴대폰에 저장됐어요.\n같은 계정으로 로그인하면\n홈에서 이어서 할 수 있어요.';

  /// 남긴 녹음이 없다. 녹음 전이거나 녹음을 저장하지 못했거나, 이미 보냈다.
  static const noRecording = '다시 로그인한 뒤\n이어서 해주세요.';

  static const action = '다시 로그인하기';
}

/// 이번 실행의 면회에 닫아서 기기에 남긴, 아직 보내지 않은 녹음이 있는지.
///
/// 확인 창은 세션을 지우기 전에 뜨므로 면회 상태와 지금 계정의 기기 기록
/// (`pending-uploads.json`)이 그대로 남아 있다. 면회를 시작하지 않았으면 면회
/// 상태를 새로 만들지 않는다.
///
/// 홈의 이어 하기는 기기 기록에서 보내지 않은 녹음을 찾으므로 그 기록으로
/// 가린다. 녹음을 보낸 뒤 오는 위로 화면에서는 파일이 남아도 보냈다고 적어 이어서
/// 보낼 것이 없다. 기록을 읽지 못하면 남겼다고 말하지 않는다.
Future<bool> visitRecordingKept(WidgetRef ref) async {
  if (!ref.exists(visitControllerProvider)) return false;
  final visit = startedVisitOf(ref.read(visitControllerProvider));
  final sessionId = visit?.sessionId;
  if (visit == null ||
      sessionId == null ||
      visit.recording ||
      visit.recordingPath == null ||
      visit.problem == VisitRecordingProblem.saveFailed) {
    return false;
  }
  try {
    return await ref.read(pendingUploadsProvider).find(sessionId) != null;
  } on Exception {
    return false;
  }
}

/// 로그인이 풀렸다고 알린다. 버튼을 누르거나 뒤로 가기로 닫으면 끝난다.
///
/// 바깥을 눌러서는 닫히지 않는다. 닫힌 뒤에는 부르는 쪽이 로그인 화면으로 간다.
Future<void> showVisitSignedOutDialog(
  BuildContext context, {
  required bool recordingKept,
}) => showNoticeDialog(
  context,
  title: VisitSignedOutMessages.title,
  detail: recordingKept
      ? VisitSignedOutMessages.recordingKept
      : VisitSignedOutMessages.noRecording,
  label: VisitSignedOutMessages.action,
  barrierDismissible: false,
);
