// 면회 중 녹음 화면을 가짜 서버(JourneyServer)와 함께 실제 화면으로 돌린다.
// 보충 카드 추가(5-3)와 녹음 중 뒤로 가기 확인 창을 본다.

import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/features/cards/cards_screen.dart' show cardSelectLabel;
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
