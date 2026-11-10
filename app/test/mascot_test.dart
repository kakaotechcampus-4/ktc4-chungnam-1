import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/widgets/mascot.dart';

/// 지금 맨 위에 보이는(새로 나타나는) 그림.
Finder _face(String asset) => find.byKey(ValueKey(asset));

/// 실제 화면처럼 프레임을 이어 그리며 [ms] 만큼 흘린다. 한 번에 크게 흘리면
/// 그림이 바뀌는 겹침이 다음 프레임을 받지 못한다.
Future<void> _wait(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 16) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _pumpMascot(WidgetTester tester, MascotController controller) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(child: Mascot(size: 200, controller: controller)),
      ),
    ),
  );
}

void main() {
  // flutter_test_config.dart 가 끈 움직임을 이 파일에서는 켠다.
  setUp(() => Mascot.motion = true);
  tearDown(() => Mascot.motion = false);

  testWidgets('누르면 눈웃음으로 바뀌었다가 기본 얼굴로 돌아온다', (tester) async {
    final controller = MascotController();
    addTearDown(controller.dispose);
    await _pumpMascot(tester, controller);
    expect(_face(Mascot.idleAsset), findsOneWidget);

    await tester.tap(find.byType(Mascot));
    await _wait(tester, 300);
    expect(_face(Mascot.tapAsset), findsOneWidget);

    await _wait(tester, 900);
    expect(_face(Mascot.idleAsset), findsOneWidget);
    expect(_face(Mascot.tapAsset), findsNothing);
    // 하트가 다 사라질 때까지 흘린다.
    await _wait(tester, 600);
  });

  testWidgets('반응 중에 다시 눌러도 처음부터 다시 하지 않는다', (tester) async {
    final controller = MascotController();
    addTearDown(controller.dispose);
    await _pumpMascot(tester, controller);

    await tester.tap(find.byType(Mascot));
    await _wait(tester, 500);
    await tester.tap(find.byType(Mascot));
    // 두 번째 누름이 다시 시작했다면 아직 눈웃음이다.
    await _wait(tester, 600);
    expect(_face(Mascot.idleAsset), findsOneWidget);
  });

  testWidgets('성공하면 신나는 얼굴로 바뀌어 머물다가 기본으로 돌아온다', (tester) async {
    final controller = MascotController();
    addTearDown(controller.dispose);
    await _pumpMascot(tester, controller);

    controller.celebrate();
    await tester.pump();
    await _wait(tester, 400);
    expect(_face(Mascot.successAsset), findsOneWidget);

    // 약 2초 동안 신나는 얼굴을 유지한다.
    await _wait(tester, 1200);
    expect(_face(Mascot.successAsset), findsOneWidget);

    // 성공 중에는 눌러도 눈웃음으로 바뀌지 않는다.
    await tester.tap(find.byType(Mascot));
    await _wait(tester, 100);
    expect(_face(Mascot.tapAsset), findsNothing);

    await _wait(tester, 1400);
    expect(_face(Mascot.idleAsset), findsOneWidget);
    expect(_face(Mascot.successAsset), findsNothing);
  });

  testWidgets('화면에서 빠지면 타이머와 움직임을 정리한다', (tester) async {
    final controller = MascotController();
    addTearDown(controller.dispose);
    await _pumpMascot(tester, controller);
    controller.celebrate();
    await _wait(tester, 100);

    await tester.pumpWidget(const SizedBox());
    // 남은 타이머나 티커가 있으면 테스트 프레임워크가 실패시킨다.
    await tester.pump(const Duration(seconds: 20));
    // 듣기를 그만두지 않았다면 사라진 화면의 움직임을 시작하다 실패한다.
    controller.celebrate();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('움직임 줄이기가 켜져 있어도 표정은 바뀐다', (tester) async {
    final controller = MascotController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(body: Mascot(size: 200, controller: controller)),
        ),
      ),
    );
    await tester.tap(find.byType(Mascot));
    await _wait(tester, 300);
    expect(_face(Mascot.tapAsset), findsOneWidget);
    await tester.pumpAndSettle();
    expect(_face(Mascot.idleAsset), findsOneWidget);
  });

  testWidgets('카드 완성 얼굴인 동안 잠깐씩 쉬며 다시 축하한다', (tester) async {
    final controller = MascotController();
    addTearDown(controller.dispose);
    var reacted = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Mascot(
              size: 200,
              controller: controller,
              cheerful: true,
              onReact: () => reacted++,
            ),
          ),
        ),
      ),
    );

    controller.celebrate();
    // 첫 축하(2.6초) 뒤 3.5초 쉬고 다시 축하한다. 축하 중에는 누름을 받지 않는다.
    await _wait(tester, 6600);
    await tester.tap(find.byType(Mascot));
    expect(reacted, 0, reason: '두 번째 축하 중이다');

    // 두 번째 축하가 끝나면 다시 누름을 받는다.
    await _wait(tester, 2400);
    await tester.tap(find.byType(Mascot));
    expect(reacted, 1);
    await _wait(tester, 1200);

    await tester.pumpWidget(const SizedBox());
  });
}
