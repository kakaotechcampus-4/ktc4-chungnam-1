// 약관 `자세히 보기` 시트가 작은 화면과 큰 글자에서도 끝까지 읽히는지 확인한다.
//
// 2026-11-10 UX 점검 14번: 시트가 스크롤되지 않아 `AI 사진 분석 동의` 가
// 360x640 기본 글자에서 45, 1.3배에서 292, 390x844 1.3배에서 59 만큼 넘쳐
// 보유 기간 같은 아래 줄을 읽을 수 없었다. 가입 동의(1-2)와 설정의 계정 약관
// 동의가 같은 시트(`showConsentDetails`)를 쓴다. 설정 쪽은
// `consent_settings_test.dart` 에서 본다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/auth_api.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/auth/consent_form.dart';
import 'package:saerok/features/auth/consent_terms.dart';
import 'package:saerok/features/auth/google_consent_screen.dart';

void _screen(WidgetTester tester, Size size, double scale) {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// 시트를 여는 버튼 하나만 둔 화면.
Widget _opener(ConsentTerm term) => MaterialApp(
  theme: buildAppTheme(),
  home: Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () => showConsentDetails(context, term),
          child: const Text('열기'),
        ),
      ),
    ),
  ),
);

/// 구글 로그인 뒤 동의 화면. 서버 응답 대신 계약의 기본 항목을 넘긴다.
Widget _consentScreen() => ProviderScope(
  child: MaterialApp(
    theme: buildAppTheme(),
    home: GoogleConsentScreen(
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
  ),
);

final _photo = consentTerms.firstWhere((term) => term.key == 'photoAnalysis');

Finder get _sheet => find.byType(BottomSheet);

Finder get _close => find.descendant(
  of: _sheet,
  matching: find.widgetWithText(OutlinedButton, '닫기'),
);

/// 시트 안에서 [line] 이 보일 때까지 내리고, `닫기` 위에 온전히 보이는지 본다.
Future<void> _readToEnd(WidgetTester tester, ConsentTerm term) async {
  final last = find.descendant(
    of: _sheet,
    matching: find.text(term.details.last),
  );
  await tester.scrollUntilVisible(
    last,
    80,
    scrollable: find.descendant(of: _sheet, matching: find.byType(Scrollable)),
  );
  await tester.pumpAndSettle();

  final line = tester.getRect(last);
  final sheet = tester.getRect(_sheet);
  final close = tester.getRect(_close);
  expect(line.top, greaterThanOrEqualTo(sheet.top), reason: term.key);
  expect(
    line.bottom,
    lessThanOrEqualTo(close.top),
    reason: '${term.key}: 마지막 줄이 닫기 버튼에 가리지 않는다',
  );
}

void main() {
  const sizes = [
    (Size(360, 640), 1.0),
    (Size(360, 640), 1.3),
    (Size(390, 844), 1.0),
    (Size(390, 844), 1.3),
    (Size(360, 640), 2.0),
  ];

  for (final (size, scale) in sizes) {
    final tag = '${size.width.toInt()}x${size.height.toInt()} 글자 $scale배';

    testWidgets('$tag: 모든 약관을 끝까지 읽고 닫기로 닫는다', (tester) async {
      _screen(tester, size, scale);

      for (final term in consentTerms) {
        await tester.pumpWidget(_opener(term));
        await tester.tap(find.text('열기'));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '${term.key} 시트가 넘치지 않는다',
        );

        expect(
          find.descendant(of: _sheet, matching: find.text(term.label)),
          findsOneWidget,
        );
        expect(_close, findsOneWidget, reason: '${term.key} 시트에 닫기가 있다');
        await _readToEnd(tester, term);
        expect(
          tester.getRect(_close).height,
          greaterThanOrEqualTo(48),
          reason: '누르는 요소 최소 48',
        );

        await tester.tap(_close);
        await tester.pumpAndSettle();
        expect(_sheet, findsNothing, reason: '${term.key}: 닫기로 닫힌다');
      }
    });
  }

  testWidgets('제목과 닫기는 그 자리에 두고 약관만 스크롤한다', (tester) async {
    _screen(tester, const Size(360, 640), 1.3);
    await tester.pumpWidget(_opener(_photo));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    final title = find.descendant(
      of: _sheet,
      matching: find.text(_photo.label),
    );
    final titleTop = tester.getTopLeft(title).dy;
    final closeTop = tester.getTopLeft(_close).dy;

    await _readToEnd(tester, _photo);

    expect(tester.getTopLeft(title).dy, titleTop);
    expect(tester.getTopLeft(_close).dy, closeTop);
  });

  testWidgets('시트 바깥은 한국어 이름으로 읽는다', (tester) async {
    _screen(tester, const Size(390, 844), 1);
    await tester.pumpWidget(_opener(_photo));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    final barrier = tester.widget<ModalBarrier>(find.byType(ModalBarrier).last);
    expect(barrier.semanticsLabel, '닫기');
  });

  testWidgets('가입 동의 화면 360x640 글자 1.3배에서 AI 사진 분석 동의를 끝까지 읽는다', (
    tester,
  ) async {
    _screen(tester, const Size(360, 640), 1.3);
    await tester.pumpWidget(_consentScreen());
    await tester.pumpAndSettle();

    final details = find.text('자세히 보기');
    expect(details, findsNWidgets(consentTerms.length));
    final index = consentTerms.indexOf(_photo);
    await tester.ensureVisible(details.at(index));
    await tester.pumpAndSettle();
    await tester.tap(details.at(index));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await _readToEnd(tester, _photo);
    await tester.tap(_close);
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    expect(find.byType(GoogleConsentScreen), findsOneWidget, reason: '시트만 닫힌다');
  });
}
