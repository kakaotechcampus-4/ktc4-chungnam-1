// E-1 녹음 전 안내가 녹음 보관을 실제 동작과 다르게 말하지 않는지 확인한다.
//
// 서버 사본은 STT 직후 지우지만 기기 녹음 파일은 다시 보내기를 위해 남긴다
// (`app/README.md` 의 녹음 보관). 예전 문구 "분석이 끝나면 바로 지워요" 는 기기
// 파일까지 지우는 것처럼 읽혔다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/features/cards/cards_controller.dart';
import 'package:saerok/features/visit/record_screen.dart';
import 'package:saerok/features/visit/visit_controller.dart';
import 'package:saerok/features/visit/visit_recorder.dart';

import 'fake_card_api.dart';
import 'fake_visit_recorder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 녹음을 시작하지 않은 안내 상태로 화면을 띄운다.
  Future<FakeVisitRecorder> openIntro(
    WidgetTester tester, {
    Size logical = const Size(412, 917),
    double textScale = 1.0,
  }) async {
    const dpr = 3.0;
    tester.view.physicalSize = logical * dpr;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);

    final recorder = FakeVisitRecorder();
    final container = ProviderContainer(
      overrides: [
        visitRecorderProvider.overrideWithValue(recorder),
        ...withMockCards,
      ],
    );
    addTearDown(container.dispose);

    await tester.runAsync(() async {
      final cards = await container.read(cardsControllerProvider.future);
      container
          .read(cardsControllerProvider.notifier)
          .toggleSelected(cards.cards.first.cardId);
      await container.read(visitControllerProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: const RecordScreen(),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
    });
    await tester.pump();
    return recorder;
  }

  testWidgets('서버 사본과 휴대폰 녹음을 나눠 안내한다', (tester) async {
    final recorder = await openIntro(tester);

    expect(find.text(recordingRetentionNotice), findsOneWidget);
    expect(find.textContaining('바로 지워요'), findsNothing);
    expect(find.textContaining('분석이 끝나면'), findsNothing);
    expect(recordingRetentionNotice, contains('서버로 보낸 녹음은 분석 후 지우고'));
    expect(recordingRetentionNotice, contains('휴대폰에는'));
    expect(find.text('네, 좋아요'), findsOneWidget);
    expect(
      recorder.calls,
      isNot(contains('start')),
      reason: '안내만 보여 주고 녹음은 시작하지 않는다',
    );
  });

  for (final (name, size, scale) in [
    ('기준 화면', const Size(412, 917), 1.0),
    ('작은 화면과 글자 확대', const Size(360, 640), 1.3),
    ('작은 화면과 큰 글자', const Size(360, 640), 2.0),
  ]) {
    testWidgets('$name 에서도 문구가 잘리지 않고 버튼이 보인다', (tester) async {
      await openIntro(tester, logical: size, textScale: scale);

      expect(tester.takeException(), isNull);
      expect(find.text(recordingRetentionNotice), findsOneWidget);
      expect(find.text('네, 좋아요').hitTestable(), findsOneWidget);
    });
  }
}
