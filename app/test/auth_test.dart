// A 화면(로그인과 구글 로그인 뒤 동의)의 규칙을 확인한다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/auth_api.dart';
import 'package:saerok/features/auth/consent_terms.dart';
import 'package:saerok/features/auth/google_consent_screen.dart';
import 'package:saerok/features/auth/google_sign_in_button.dart';
import 'package:saerok/features/auth/login_screen.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/design/tokens.dart';

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(theme: buildAppTheme(), home: child),
);

/// 구글 로그인 뒤 동의 화면. 서버 응답 대신 계약의 기본 항목을 넘긴다.
Widget _consentScreen() => _wrap(
  GoogleConsentScreen(
    pending: ConsentRequiredResult(
      registrationToken: 'fake-registration-token',
      expiresIn: 600,
      consentVersion: consentVersion,
      requiredConsents: [
        for (final term in consentTerms)
          if (term.required) term.key,
      ],
      optionalConsents: [
        for (final term in consentTerms)
          if (!term.required) term.key,
      ],
    ),
  ),
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

  testWidgets('로그인 화면에는 구글 로그인만 있다', (tester) async {
    await tester.pumpWidget(_wrap(const LoginScreen()));

    expect(find.byType(GoogleSignInButton), findsOneWidget);
    // 아이디와 비밀번호는 받지 않는다(ADR-007). 회원가입으로 가는 길도 없다.
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('회원가입'), findsNothing);
  });

  testWidgets('동의 항목 이름은 줄바꿈 없이 한 줄에 들어간다', (tester) async {
    tester.view.physicalSize = const Size(1236, 4800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_consentScreen());
    await tester.pumpAndSettle();

    // 자세히 보기를 같은 줄에 두었더니 이름이 두 줄로 밀렸다.
    final twoLines =
        AppTypography.body.fontSize! * AppTypography.body.height! * 2;

    for (final term in consentTerms) {
      expect(
        tester.getRect(find.textContaining(term.label).first).height,
        lessThan(twoLines),
        reason: '${term.key} 이름이 줄바꿈되었다',
      );
    }
  });

  testWidgets('자세히 보기는 항목 이름 아래에 붙어 있다', (tester) async {
    tester.view.physicalSize = const Size(1236, 4800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_consentScreen());
    await tester.pumpAndSettle();

    final name = tester.getRect(find.textContaining('개인정보 처리 동의').first);
    final details = tester.getRect(find.text('자세히 보기').first);

    expect(
      details.top,
      greaterThanOrEqualTo(name.bottom),
      reason: '같은 줄에 두면 이름이 줄바꿈된다',
    );

    // 48 을 쓰면 24dp 가 벌어져 항목 사이 간격과 구분되지 않는다.
    // DESIGN.md 의 보조 글자 버튼 예외를 따른다.
    expect(
      details.top - name.bottom,
      lessThan(14),
      reason: '항목 이름에 붙어 있어야 그 항목의 것으로 읽힌다',
    );
  });

  testWidgets('알림 수신 동의에만 쓰임새를 한 줄로 드러낸다', (tester) async {
    tester.view.physicalSize = const Size(1236, 4800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_consentScreen());
    await tester.pumpAndSettle();

    expect(find.text('만남 리포트가 완성되면 알려드려요.'), findsOneWidget);

    final withNote = consentTerms.where((term) => term.note != null);
    expect(withNote.map((term) => term.key), [
      'pushNotification',
    ], reason: '끄면 불편해지는 항목만 목록에서 이유를 밝힌다');
  });
}
