// 면회 중 녹음 화면을 가짜 서버(JourneyServer)와 함께 실제 화면으로 돌린다.
// 보충 카드 추가(5-3)와 녹음 중 뒤로 가기 확인 창, 세션을 잃었을 때의 확인 창을
// 본다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/features/auth/auth_messages.dart';
import 'package:saerok/features/auth/auth_providers.dart';
import 'package:saerok/features/auth/google_sign_in_button.dart';
import 'package:saerok/features/auth/session_refresher.dart';
import 'package:saerok/features/cards/cards_screen.dart' show cardSelectLabel;
import 'package:saerok/features/visit/visit_controller.dart';
import 'package:saerok/features/visit/visit_signed_out_dialog.dart';
import 'package:saerok/widgets/app_surfaces.dart';

import 'journey/journey_harness.dart';
import 'journey/journey_server.dart';

Finder _toggle(String title) => find.byWidgetPredicate(
  (w) => w is SelectionToggle && w.label == cardSelectLabel(title),
);

/// 카드 두 장을 골라 녹음을 시작한다.
Future<(JourneyDriver, String)> _recording(WidgetTester tester) async {
  final server = JourneyServer();
  final app = await JourneyDriver.launch(tester, server);
  await app.waitFor(find.text('오늘의 대화카드 받기'), maxSteps: 300);
  await app.tap(find.text('오늘의 대화카드 받기'));
  await app.waitFor(find.text('오늘의 대화 카드'));
  final setId = server.setIds.single;
  for (final title in server.cardTitlesOf(setId).take(2)) {
    await app.tap(_toggle(title));
  }
  await app.tap(find.text('대화 시작하기'));
  await app.tap(find.text('사진 없이 시작할게요'));
  await app.tap(find.text('네, 좋아요'));
  await app.waitFor(find.text('녹음 중이에요'));
  return (app, setId);
}

void main() {
  testWidgets('녹음 중에 보충 카드를 더하면 서버(5-3)에 알리고 번호가 늘어난다', (tester) async {
    final (app, setId) = await _recording(tester);

    await app.tap(find.text('위로 올려서 대화 카드 꺼내기'));
    await app.tap(find.text('대화 카드 추가'));
    for (final title in app.server.cardTitlesOf(setId).skip(9).take(2)) {
      await app.tap(_toggle(title));
    }
    await app.tap(find.text('2장 추가하기'));
    await app.waitFor(find.bySemanticsLabel(RegExp('4번 카드')));

    expect(find.textContaining('카드를 추가하지 못했어요'), findsNothing);
    final patch = app.server.requests.singleWhere(
      (r) => r.method == 'PATCH' && r.path.endsWith('/cards'),
    );
    expect((patch.body! as Map)['cardIds'], hasLength(2));
    await app.close();
  });

  // 2026-11-10 E2E: 녹음 중 매시간 뜨는 계정 선택 창을 취소하면 로그인 화면으로
  // 가서 녹음 화면이 닫히고 녹음이 멈출 수 있었다. 이 여정의 구글 대역은 조용히
  // 받지 못하므로, 다시 받기가 취소된 것과 같다.
  //
  // UX 점검 8번(2026-11-10): 만남을 끝내 파일을 닫은 뒤 바로 옮기지 않고, 녹음을
  // 남겨 두었다는 확인 창을 띄운 뒤 로그인 화면으로 가서 풀린 이유를 알린다.
  testWidgets('녹음 중 세션을 다시 받지 못해도 녹음을 이어 가고, 만남을 끝내면 확인 창을 거쳐 로그인 화면으로 간다', (
    tester,
  ) async {
    final (app, _) = await _recording(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.text('녹음 중이에요')),
    );

    final renewed = container.read(sessionRefresherProvider).refresh();
    await app.step();
    expect(await renewed, isFalse);
    for (var i = 0; i < 6; i++) {
      await app.step();
    }

    expect(find.text('녹음 중이에요'), findsOneWidget);
    expect(container.read(sessionProvider), isNotNull);
    expect(container.read(visitControllerProvider).value!.recording, isTrue);
    expect(find.byType(GoogleSignInButton), findsNothing);

    await app.tap(find.byIcon(Icons.stop));
    await app.waitFor(find.text('만남을 끝낼까요?'));
    await app.tap(find.text('끝내기'));

    await app.waitFor(find.text(VisitSignedOutMessages.title));
    expect(find.text(VisitSignedOutMessages.recordingKept), findsOneWidget);
    expect(
      find.byType(GoogleSignInButton),
      findsNothing,
      reason: '확인 전에는 옮기지 않는다',
    );
    expect(container.read(sessionProvider), isNotNull, reason: '뒤 화면을 그대로 둔다');
    expect(app.recorder.stops, 1, reason: '녹음 파일을 먼저 닫는다');
    final upload = app.uploads.saved.values.single;
    expect(upload.participantCount, 2, reason: '닫은 녹음은 다시 보낼 수 있게 남는다');

    await app.tap(find.text(VisitSignedOutMessages.action));
    await app.waitFor(find.byType(GoogleSignInButton));
    expect(find.text(sessionLostSignInNotice), findsOneWidget);
    expect(container.read(sessionProvider), isNull);
    expect(app.uploads.saved.values.single.audioPath, upload.audioPath);
    await app.close();
  });

  testWidgets('녹음 중 세션을 잃은 채 녹음 화면을 떠나면 파일을 닫은 뒤 확인 창을 띄운다', (tester) async {
    final (app, _) = await _recording(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.text('녹음 중이에요')),
    );
    final renewed = container.read(sessionRefresherProvider).refresh();
    await app.step();
    expect(await renewed, isFalse);

    await app.back();
    await app.tap(find.text('그만두고 나가기'));

    await app.waitFor(find.text(VisitSignedOutMessages.title));
    expect(find.text(VisitSignedOutMessages.recordingKept), findsOneWidget);
    expect(find.text('사진 없이 시작할게요'), findsOneWidget, reason: '떠난 앞 화면 위에 뜬다');
    expect(app.recorder.stops, 1);
    final upload = app.uploads.saved.values.single;
    expect(upload.participantCount, isNull, reason: '사람 수는 보낼 때 다시 묻는다');

    await app.tap(find.text(VisitSignedOutMessages.action));
    await app.waitFor(find.byType(GoogleSignInButton));
    expect(find.text(sessionLostSignInNotice), findsOneWidget);
    await app.close();
  });

  testWidgets('녹음 화면에서 녹음 전에 세션을 잃으면 확인 창을 거쳐 로그인 화면으로 간다', (tester) async {
    final server = JourneyServer();
    final app = await JourneyDriver.launch(tester, server);
    await app.waitFor(find.text('오늘의 대화카드 받기'), maxSteps: 300);
    await app.tap(find.text('오늘의 대화카드 받기'));
    await app.waitFor(find.text('오늘의 대화 카드'));
    await app.tap(_toggle(server.cardTitlesOf(server.setIds.single).first));
    await app.tap(find.text('대화 시작하기'));
    await app.tap(find.text('사진 없이 시작할게요'));
    await app.waitFor(find.text('네, 좋아요'));
    final container = ProviderScope.containerOf(
      tester.element(find.text('네, 좋아요')),
    );

    final renewed = container.read(sessionRefresherProvider).refresh();
    await app.step();
    expect(await renewed, isFalse);

    await app.waitFor(find.text(VisitSignedOutMessages.title));
    expect(find.text(VisitSignedOutMessages.noRecording), findsOneWidget);
    expect(find.text(VisitSignedOutMessages.recordingKept), findsNothing);
    expect(find.text('네, 좋아요'), findsOneWidget, reason: '뒤 화면을 그대로 둔다');
    expect(app.recorder.starts, 0);

    await app.tap(find.text(VisitSignedOutMessages.action));
    await app.waitFor(find.byType(GoogleSignInButton));
    expect(find.text(sessionLostSignInNotice), findsOneWidget);
    expect(container.read(sessionProvider), isNull);
    await app.close();
  });

  // 위로 화면은 녹음을 서버에 보낸 뒤에만 온다. 기기에 파일은 남지만 보냈다고
  // 적어 홈에서 이어서 보낼 것이 없다. 녹음을 남겼다는 문구를 쓰지 않는다.
  testWidgets('녹음을 보낸 뒤 위로 화면에서 세션을 잃으면 이어서 할 녹음이 있다고 말하지 않는다', (tester) async {
    final (app, _) = await _recording(tester);
    await app.tap(find.byIcon(Icons.stop));
    await app.waitFor(find.text('만남을 끝낼까요?'));
    await app.tap(find.text('끝내기'));
    await app.waitFor(find.text('오늘 만남은\n어떠셨나요?'));
    await app.tap(find.text('좋았어요').first);
    await app.tap(find.text('4'));
    await app.tap(find.text('기뻐하셨어요'));
    await app.tap(find.text('리포트 만들기'));
    await app.waitFor(find.text('제출 완료!'));
    expect(app.uploads.saved, isEmpty, reason: '보낸 녹음은 다시 보낼 목록에서 뺀다');
    expect(app.uploads.uploaded, hasLength(1));
    final container = ProviderScope.containerOf(
      tester.element(find.text('제출 완료!')),
    );

    final renewed = container.read(sessionRefresherProvider).refresh();
    await app.step();
    expect(await renewed, isFalse);

    await app.waitFor(find.text(VisitSignedOutMessages.title));
    expect(find.text(VisitSignedOutMessages.noRecording), findsOneWidget);
    expect(find.text(VisitSignedOutMessages.recordingKept), findsNothing);

    await app.tap(find.text(VisitSignedOutMessages.action));
    await app.waitFor(find.byType(GoogleSignInButton));
    expect(find.text(sessionLostSignInNotice), findsOneWidget);
    await app.close();
  });

  testWidgets('면회 흐름 밖에서 세션을 잃으면 확인 창 없이 로그인 화면으로 가서 이유를 알린다', (tester) async {
    final app = await JourneyDriver.launch(tester, JourneyServer());
    await app.waitFor(find.text('오늘의 대화카드 받기'), maxSteps: 300);
    final container = ProviderScope.containerOf(
      tester.element(find.text('오늘의 대화카드 받기')),
    );

    final renewed = container.read(sessionRefresherProvider).refresh();
    await app.step();
    expect(await renewed, isFalse);

    await app.waitFor(find.byType(GoogleSignInButton));
    expect(find.text(VisitSignedOutMessages.title), findsNothing);
    expect(find.text(sessionLostSignInNotice), findsOneWidget);
    await app.close();
  });

  testWidgets('녹음 중에 뒤로 가면 그만둘지 묻고, 계속하면 머문다', (tester) async {
    final (app, _) = await _recording(tester);

    await app.back();
    expect(find.text('녹음을 그만둘까요?'), findsOneWidget);
    await app.tap(find.text('계속 녹음하기'));
    await app.waitUntilGone(find.text('녹음을 그만둘까요?'));
    expect(find.text('녹음 중이에요'), findsOneWidget);
    expect(app.recorder.starts, 1);

    await app.back();
    await app.tap(find.text('그만두고 나가기'));
    await app.waitFor(find.text('사진 없이 시작할게요'));
    expect(find.text('녹음 중이에요'), findsNothing);
    await app.close();
  });
}
