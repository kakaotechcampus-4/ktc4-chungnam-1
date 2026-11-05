// 홈 말풍선(home_talk.dart)을 실제 앱과 가짜 서버로 확인한다.
//
// 가짜 서버의 어르신은 세부 정보 `하시던 일` 하나가 있고, 여기에 합성 이야기
// `라디오 노래` 하나를 더한다. 이야기가 둘이면 같은 이야기를 연달아 고르지
// 않으므로 바뀔 때마다 다른 쪽이 나온다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/features/home/home_phrases.dart';
import 'package:saerok/widgets/mascot.dart';

import 'journey/journey_harness.dart';
import 'journey/journey_server.dart';

const _job = '하시던 일';
const _radio = '라디오 노래';

JourneyServer _server() => JourneyServer()
  ..lifeFacts.add({
    'factId': '00000000-0000-4000-8000-000000000101',
    'storyCategory': 'hobby',
    'title': _radio,
    'content': '아침마다 라디오 노래를 따라 부르셨어요.',
    'imageNumber': 1,
    'createdAt': '2026-10-20T10:00:00+09:00',
  });

Finder _anyOf(List<String> texts) =>
    find.byWidgetPredicate((w) => w is Text && texts.contains(w.data));

final _greetings = [
  ...morningGreetings,
  ...afternoonGreetings,
  ...eveningGreetings,
];

/// 마스코트 반응(0.85초)이 끝나 다음 누름을 받을 때까지 흘린다.
Future<void> _settleReaction(JourneyDriver app) async {
  for (var i = 0; i < 12; i++) {
    await app.step();
  }
}

void main() {
  testWidgets('처음에는 인사말이고, 마스코트를 누르면 일대기 이야기로 바뀐다', (tester) async {
    final app = await JourneyDriver.launch(tester, _server());
    await app.waitFor(find.byType(Mascot));
    expect(_anyOf(_greetings), findsOneWidget);
    expect(_anyOf(storyRemarks), findsNothing);

    await app.tap(find.byType(Mascot));
    await app.waitFor(_anyOf(storyRemarks));
    expect(_anyOf(_greetings), findsNothing);
    final first = find.text(_job).evaluate().isNotEmpty ? _job : _radio;
    final second = first == _job ? _radio : _job;

    // 같은 이야기를 연달아 고르지 않는다.
    await _settleReaction(app);
    await app.tap(find.byType(Mascot));
    await app.waitFor(find.text(second));
    expect(find.text(first), findsNothing);
    await app.close();
  });

  testWidgets('이야기 말풍선을 누르면 그 이야기로 가고, 돌아오면 다른 이야기로 바뀐다', (
    tester,
  ) async {
    final app = await JourneyDriver.launch(tester, _server());
    await app.waitFor(find.byType(Mascot));
    await app.tap(find.byType(Mascot));
    await app.waitFor(_anyOf(storyRemarks));
    final shown = find.text(_job).evaluate().isNotEmpty ? _job : _radio;
    final other = shown == _job ? _radio : _job;

    await app.tap(find.text(shown));
    await app.waitFor(find.text('목차로'));

    await app.back();
    await app.waitFor(find.text(other));
    expect(find.byType(Mascot), findsOneWidget);
    await app.close();
  });

  testWidgets('대화 카드 받기를 누르면 말풍선이 이야기로 바뀐다', (tester) async {
    final app = await JourneyDriver.launch(tester, _server());
    await app.waitFor(find.byType(Mascot));
    expect(_anyOf(_greetings), findsOneWidget);

    await app.tap(find.text('오늘의 대화카드 받기'));
    // 이미 준비된 묶음이라 카드 화면으로 간다. 돌아오면 또 바뀐다.
    await app.back();
    await app.waitFor(_anyOf(storyRemarks));
    await app.close();
  });
}
