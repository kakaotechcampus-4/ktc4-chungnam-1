// 스플래시의 구글 로그인 버튼(A-1)이 G 그림과 글자를 한 버튼으로 담는지 확인한다.
//
// 2026-11-10 UX 점검 13번: 버튼이 48 짜리 동그라미 하나였고, 아래 `구글 계정으로
// 로그인` 글자는 눌리지 않았으며 화면 낭독기가 같은 이름을 두 번 읽었다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/design/tokens.dart';
import 'package:saerok/features/auth/auth_providers.dart';
import 'package:saerok/features/auth/auth_session.dart';
import 'package:saerok/features/auth/google_sign_in_button.dart';
import 'package:saerok/features/auth/session_store.dart';
import 'package:saerok/features/auth/splash_screen.dart';

/// 화면 크기와 글자 배율을 정한다.
void _screen(WidgetTester tester, Size size, {double scale = 1}) {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// 스플래시 패널처럼 화면 좌우 여백 안에 버튼 하나를 둔다.
Widget _host({VoidCallback? onPressed, bool busy = false}) => MaterialApp(
  theme: buildAppTheme(),
  home: Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
        child: GoogleSignInButton(onPressed: onPressed, busy: busy),
      ),
    ),
  ),
);

/// 보관한 세션이 없는 단말이다.
class _EmptySessionStore implements SessionStore {
  @override
  Future<AuthSession?> read() async => null;

  @override
  Future<void> write(AuthSession session) async {}

  @override
  Future<void> clear() async {}
}

void main() {
  testWidgets('글자를 눌러도 로그인한다', (tester) async {
    _screen(tester, const Size(390, 844));
    var taps = 0;
    await tester.pumpWidget(_host(onPressed: () => taps++));

    await tester.tap(find.text(GoogleSignInButton.label));
    expect(taps, 1, reason: '그림과 글자가 한 버튼이다');

    await tester.tap(find.image(const AssetImage(GoogleSignInButton.asset)));
    expect(taps, 2);
  });

  testWidgets('누르는 자리는 높이 56 이상이고 화면 폭을 채운다', (tester) async {
    _screen(tester, const Size(360, 640));
    await tester.pumpWidget(_host(onPressed: () {}));

    final button = tester.getRect(find.byType(InkWell));
    expect(button.height, greaterThanOrEqualTo(AppSizes.control));
    expect(button.width, 360 - AppSpacing.screen * 2);
    // G 그림과 글자 모두 누르는 자리 안에 있다.
    expect(
      button.contains(tester.getCenter(find.text(GoogleSignInButton.label))),
      isTrue,
    );
    expect(
      button.contains(
        tester.getCenter(
          find.image(const AssetImage(GoogleSignInButton.asset)),
        ),
      ),
      isTrue,
    );
  });

  testWidgets('화면 낭독기는 이름 하나의 버튼으로 읽는다', (tester) async {
    final semantics = tester.ensureSemantics();
    _screen(tester, const Size(390, 844));
    await tester.pumpWidget(_host(onPressed: () {}));

    expect(
      find.bySemanticsLabel(GoogleSignInButton.label),
      findsOneWidget,
      reason: '그림 버튼과 아래 글자가 같은 이름을 두 번 읽지 않는다',
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel(GoogleSignInButton.label)),
      isSemantics(
        label: GoogleSignInButton.label,
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('로그인하는 동안은 진행 표시와 안내를 두고 누를 수 없다', (tester) async {
    final semantics = tester.ensureSemantics();
    _screen(tester, const Size(360, 640));
    var taps = 0;
    await tester.pumpWidget(_host(onPressed: () => taps++, busy: true));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('로그인하는 중이에요'), findsOneWidget);
    expect(find.text(GoogleSignInButton.label), findsNothing);
    expect(
      tester.getRect(find.byType(InkWell)).height,
      greaterThanOrEqualTo(AppSizes.control),
      reason: '기다리는 동안 버튼 크기가 바뀌지 않는다',
    );

    await tester.tap(find.text('로그인하는 중이에요'), warnIfMissed: false);
    expect(taps, 0);

    expect(find.bySemanticsLabel('로그인하는 중이에요'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('로그인하는 중이에요')),
      isSemantics(
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
        hasTapAction: false,
      ),
    );
    semantics.dispose();
  });

  testWidgets('누를 수 없으면 누를 수 없는 버튼으로 읽는다', (tester) async {
    final semantics = tester.ensureSemantics();
    _screen(tester, const Size(390, 844));
    await tester.pumpWidget(_host());

    expect(
      tester.getSemantics(find.bySemanticsLabel(GoogleSignInButton.label)),
      isSemantics(
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
        hasTapAction: false,
      ),
    );
    semantics.dispose();
  });

  for (final (size, scale) in const [
    (Size(360, 640), 1.3),
    (Size(360, 640), 2.0),
    (Size(390, 844), 1.3),
    (Size(390, 844), 2.0),
  ]) {
    final tag = '${size.width.toInt()}x${size.height.toInt()}';
    testWidgets('$tag 글자 $scale배에서도 글자가 잘리지 않고 버튼 안에 든다', (tester) async {
      _screen(tester, size, scale: scale);
      await tester.pumpWidget(_host(onPressed: () {}));

      expect(tester.takeException(), isNull);
      final button = tester.getRect(find.byType(InkWell));
      final text = tester.getRect(find.text(GoogleSignInButton.label));
      expect(button.height, greaterThanOrEqualTo(AppSizes.control));
      expect(button.top, lessThanOrEqualTo(text.top));
      expect(button.bottom, greaterThanOrEqualTo(text.bottom));
    });
  }

  testWidgets('버튼이 나타나도 스플래시 로고가 흔들리지 않는다', (tester) async {
    _screen(tester, const Size(390, 844));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStoreProvider.overrideWithValue(_EmptySessionStore()),
          // 구글 설정이 없는 디버그 빌드의 개발용 안내는 출시 빌드에 없다.
          skipGoogleLoginProvider.overrideWithValue(false),
        ],
        child: MaterialApp(theme: buildAppTheme(), home: const SplashScreen()),
      ),
    );
    await tester.pump();
    expect(find.byType(GoogleSignInButton), findsNothing);
    final before = tester.getTopLeft(find.text('새록'));

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.byType(GoogleSignInButton), findsOneWidget);
    expect(tester.getTopLeft(find.text('새록')), before);
  });
}
