// A 화면(스플래시, 로그인, 회원가입)의 규칙을 확인한다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/features/auth/consent_terms.dart';
import 'package:saerok/features/auth/login_screen.dart';
import 'package:saerok/features/auth/signup_screen.dart';
import 'package:saerok/design/theme.dart';

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(theme: buildAppTheme(), home: child),
);

void main() {
  group('동의 항목', () {
    test('계약의 Account.consent 와 같은 키를 쓴다', () {
      final keys = consentTerms.map((t) => t.key).toSet();

      expect(keys, {
        'serviceData',
        'sensitiveData',
        'pushNotification',
        'serviceImprovement',
      });
    });

    test('필수 둘과 선택 둘이다', () {
      final required = consentTerms.where((t) => t.required).map((t) => t.key);
      final optional = consentTerms.where((t) => !t.required).map((t) => t.key);

      expect(required, ['serviceData', 'sensitiveData']);
      // 알림 수신은 선택이다. 법률 문서와 계약 모두 선택으로 적고 있다.
      expect(optional, ['pushNotification', 'serviceImprovement']);
    });

    test('모든 항목에 문구와 설명이 있다', () {
      for (final term in consentTerms) {
        expect(term.statement, isNotEmpty, reason: term.key);
        expect(term.details, isNotEmpty, reason: term.key);
      }
    });
  });

  testWidgets('로그인은 아이디와 비밀번호를 채워야 누를 수 있다', (tester) async {
    await tester.pumpWidget(_wrap(const LoginScreen()));

    final button = find.widgetWithText(FilledButton, '로그인');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    await tester.enterText(find.byType(TextField).first, 'demo_user');
    await tester.enterText(find.byType(TextField).last, 'password');
    await tester.pump();

    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
  });

  testWidgets('로그인 버튼도 고정하지 않아 작은 화면에서 입력칸이 살아 있다', (tester) async {
    const dpr = 3.0;
    // 화면이 작고 키보드가 큰 경우다. 고정 영역이 있으면 비밀번호 칸이 밀렸다.
    tester.view.physicalSize = const Size(360 * dpr, 780 * dpr);
    tester.view.devicePixelRatio = dpr;
    tester.view.padding = const FakeViewPadding(top: 24 * dpr);
    tester.view.viewInsets = const FakeViewPadding(bottom: 320 * dpr);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(const LoginScreen()));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.widgetWithText(FilledButton, '로그인'),
      ),
      findsOneWidget,
    );

    final viewport = tester.getRect(find.byType(SingleChildScrollView).first);
    final password = tester.getRect(find.byType(TextField).at(1));

    expect(
      password.bottom,
      lessThanOrEqualTo(viewport.bottom),
      reason: '비밀번호 칸이 스크롤 영역 밖으로 밀리면 안 된다',
    );
  });

  testWidgets('가입 버튼은 아래에 고정하지 않고 본문과 함께 흐른다', (tester) async {
    const dpr = 3.0;
    tester.view.physicalSize = const Size(411 * dpr, 891 * dpr);
    tester.view.devicePixelRatio = dpr;
    tester.view.padding = const FakeViewPadding(top: 24 * dpr);
    // 한글 키보드가 올라온 상태다.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300 * dpr);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(const SignupScreen()));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.widgetWithText(FilledButton, '회원가입'),
      ),
      findsOneWidget,
      reason: '고정 영역에 두면 키보드가 올라왔을 때 입력칸을 가린다',
    );

    final viewport = tester.getRect(find.byType(SingleChildScrollView).first);
    final visible = find.byType(TextField).evaluate().where((element) {
      final rect = tester.getRect(find.byWidget(element.widget));
      return rect.top >= viewport.top && rect.bottom <= viewport.bottom;
    }).length;

    expect(
      visible,
      greaterThanOrEqualTo(3),
      reason: '키보드 위에서 입력칸이 세 개는 보여야 한다',
    );
  });

  testWidgets('필수 동의만 하면 회원가입을 누를 수 있다', (tester) async {
    tester.view.physicalSize = const Size(1236, 4800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(const SignupScreen()));

    final button = find.widgetWithText(FilledButton, '회원가입');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    // 입력만 채우고 동의는 하지 않는다.
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '보호자');
    await tester.enterText(fields.at(1), 'demo');
    await tester.enterText(fields.at(2), 'demo_user');
    await tester.enterText(fields.at(3), 'password');
    await tester.pump();

    expect(
      tester.widget<FilledButton>(button).onPressed,
      isNull,
      reason: '동의 없이 가입할 수 없어야 한다',
    );
    expect(find.text('필수 항목에 모두 동의해야 가입할 수 있어요.'), findsOneWidget);

    // 체크박스는 동의 항목 순서대로 놓이고 그 뒤에 전체 동의가 온다.
    // 필수만 수락하고 선택은 건드리지 않는다.
    for (var i = 0; i < consentTerms.length; i++) {
      if (!consentTerms[i].required) continue;
      final checkbox = find.byType(Checkbox).at(i);
      await tester.ensureVisible(checkbox);
      await tester.pumpAndSettle();
      await tester.tap(checkbox);
      await tester.pump();
    }

    final pushIndex = consentTerms.indexWhere(
      (term) => term.key == 'pushNotification',
    );
    expect(
      tester.widget<Checkbox>(find.byType(Checkbox).at(pushIndex)).value,
      isFalse,
      reason: '알림 수신은 선택이라 수락하지 않았다',
    );
    expect(
      tester.widget<FilledButton>(button).onPressed,
      isNotNull,
      reason: '알림 수신에 동의하지 않아도 가입할 수 있어야 한다',
    );
  });
}
