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

    test('필수 셋과 선택 하나다', () {
      final required = consentTerms.where((t) => t.required).map((t) => t.key);
      final optional = consentTerms.where((t) => !t.required).map((t) => t.key);

      expect(required, ['serviceData', 'sensitiveData', 'pushNotification']);
      expect(optional, ['serviceImprovement']);
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

  testWidgets('필수 동의를 모두 해야 회원가입을 누를 수 있다', (tester) async {
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

    // 필수 셋만 수락한다. 마지막 체크박스는 전체 동의라 제외한다.
    for (var i = 0; i < 3; i++) {
      final checkbox = find.byType(Checkbox).at(i);
      await tester.ensureVisible(checkbox);
      await tester.pumpAndSettle();
      await tester.tap(checkbox);
      await tester.pump();
    }

    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
  });
}
