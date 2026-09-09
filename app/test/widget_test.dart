// 앱이 뜨고 첫 화면 이동이 이어지는지 확인한다.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/main.dart';

void main() {
  testWidgets('앱이 스플래시로 뜨고 로그인으로 넘어간다', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: SaerokApp()));
    await tester.pump();

    expect(find.text('오늘의 만남을 준비해요'), findsOneWidget);

    // 스플래시는 잠깐 보여준 뒤 로그인으로 넘어간다.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text('로그인'), findsWidgets);
  });
}
