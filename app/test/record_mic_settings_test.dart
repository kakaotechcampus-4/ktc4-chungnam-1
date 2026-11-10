// E-1 녹음 안내에서 마이크 권한이 없을 때 설정을 여는 버튼을 확인한다
// (UX 점검 2026-11-10 9번).
//
// 설정 화면은 대역([FakeMicSettingsPlatform])이 받는다. 실제 안드로이드 설정
// 화면이 열리는지, 켜고 돌아와 녹음이 되는지는 이 테스트가 보지 않는다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/app/mic_settings.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/cards/cards_controller.dart';
import 'package:saerok/features/visit/record_screen.dart';
import 'package:saerok/features/visit/visit_controller.dart';
import 'package:saerok/features/visit/visit_recorder.dart';

import 'fake_card_api.dart';
import 'fake_mic_settings.dart';
import 'fake_visit_api.dart';
import 'fake_visit_recorder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const deniedNotice = '마이크 사용을 허용해야 녹음할 수 있어요.\n휴대전화 설정에서 새록의 마이크를 켜주세요.';

  /// 녹음 안내를 띄우고 `네, 좋아요` 를 눌러 시작에 실패한 상태를 만든다.
  Future<FakeVisitRecorder> openFailedIntro(
    WidgetTester tester, {
    required FakeMicSettingsPlatform settings,
    bool permitted = false,
    FakeVisitApi? visitApi,
    Size logical = const Size(412, 917),
    double textScale = 1.0,
  }) async {
    const dpr = 3.0;
    tester.view.physicalSize = logical * dpr;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);

    final recorder = FakeVisitRecorder(permitted: permitted);
    final container = ProviderContainer(
      overrides: [
        visitRecorderProvider.overrideWithValue(recorder),
        settings.asOverride,
        ...mockCardsWith(visitApi: visitApi),
      ],
    );
    addTearDown(container.dispose);

    // 목 데이터는 asset 에서 읽으므로 실제 비동기 처리를 기다린다.
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
            theme: buildAppTheme(),
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

    await tester.runAsync(() async {
      await tester.tap(find.text('네, 좋아요'));
      await Future<void>.delayed(const Duration(milliseconds: 40));
    });
    await tester.pump();
    await tester.pump();
    return recorder;
  }

  testWidgets('권한이 없으면 안내 아래에 설정 열기를 두고 누르면 설정을 연다', (tester) async {
    final settings = FakeMicSettingsPlatform();
    final recorder = await openFailedIntro(tester, settings: settings);

    expect(recorder.calls, ['hasPermission']);
    expect(find.text(deniedNotice), findsOneWidget);
    // 안내 상자 안에 있다.
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text(deniedNotice),
          matching: find.byType(Container),
        ),
        matching: find.text('설정 열기'),
      ),
      findsWidgets,
    );

    await tester.ensureVisible(find.text('설정 열기'));
    await tester.pump();
    await tester.tap(find.text('설정 열기'));
    await tester.pump();

    expect(settings.opened, 1);
    expect(find.text(micSettingsOpenFailedNotice), findsNothing);
    expect(settings.checked, 0, reason: '면회 시작 버튼은 그대로라 다시 묻는지 확인하지 않는다');
    expect(find.text('네, 좋아요'), findsOneWidget);
  });

  testWidgets('설정을 열지 못하면 알림 띠로 알린다', (tester) async {
    final settings = FakeMicSettingsPlatform(opens: false);
    await openFailedIntro(tester, settings: settings);

    await tester.ensureVisible(find.text('설정 열기'));
    await tester.pump();
    await tester.tap(find.text('설정 열기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(settings.opened, 1);
    expect(find.text(micSettingsOpenFailedNotice), findsOneWidget);
  });

  testWidgets('권한이 아닌 실패에는 설정 열기를 두지 않는다', (tester) async {
    final settings = FakeMicSettingsPlatform();
    await openFailedIntro(
      tester,
      settings: settings,
      permitted: true,
      visitApi: FakeVisitApi(failCreate: true),
    );

    expect(
      find.text('면회를 시작하지 못했어요.\n인터넷 연결을 확인한 뒤 다시 눌러주세요.'),
      findsOneWidget,
    );
    expect(find.text('설정 열기'), findsNothing);
  });

  for (final (name, size, scale) in [
    ('작은 화면', const Size(360, 640), 1.0),
    ('작은 화면과 글자 확대', const Size(360, 640), 1.3),
    ('390 화면과 글자 확대', const Size(390, 844), 1.3),
  ]) {
    testWidgets('$name 에서도 안내와 설정 열기가 넘치지 않고 눌린다', (tester) async {
      final settings = FakeMicSettingsPlatform();
      await openFailedIntro(
        tester,
        settings: settings,
        logical: size,
        textScale: scale,
      );

      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('설정 열기'));
      await tester.pump();
      expect(find.text(deniedNotice).hitTestable(), findsOneWidget);
      expect(find.text('설정 열기').hitTestable(), findsOneWidget);
      expect(find.text('네, 좋아요').hitTestable(), findsOneWidget);
    });
  }
}
