// A 화면(스플래시의 로그인과 구글 로그인 뒤 동의)의 규칙을 확인한다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/auth_api.dart';
import 'package:saerok/features/auth/consent_terms.dart';
import 'package:saerok/features/auth/google_consent_screen.dart';
import 'package:saerok/features/auth/google_sign_in_button.dart';
import 'package:saerok/features/auth/google_sign_in_panel.dart';
import 'package:saerok/features/auth/splash_screen.dart';
import 'package:saerok/design/theme.dart';

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
        'photoAnalysis',
      });
    });

    test('필수 둘과 선택 셋이다', () {
      final required = consentTerms.where((t) => t.required).map((t) => t.key);
      final optional = consentTerms.where((t) => !t.required).map((t) => t.key);

      expect(required, ['serviceData', 'sensitiveData']);
      // 알림 수신은 선택이다. 법률 문서와 계약 모두 선택으로 적고 있다.
      expect(optional, ['pushNotification', 'serviceImprovement', 'photoAnalysis']);
    });

    test('모든 항목에 문구와 설명이 있다', () {
      for (final term in consentTerms) {
        expect(term.statement, isNotEmpty, reason: term.key);
        expect(term.details, isNotEmpty, reason: term.key);
      }
    });
  });

  testWidgets('로그인이 필요하면 스플래시 로고 아래에 구글 로그인만 있다', (tester) async {
    await tester.pumpWidget(_wrap(const SplashScreen(signedOut: true)));
    await tester.pumpAndSettle();

    expect(find.text('새록'), findsOneWidget, reason: '따로 된 로그인 화면이 아니다');
    expect(find.byType(GoogleSignInPanel), findsOneWidget);
    expect(find.byType(GoogleSignInButton), findsOneWidget);
    // 아이디와 비밀번호는 받지 않는다(ADR-007). 회원가입으로 가는 길도 없다.
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('회원가입'), findsNothing);
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
