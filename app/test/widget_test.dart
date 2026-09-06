// 앱 골격이 뜨는지 확인한다. 화면이 생기면 화면별 테스트를 따로 추가한다.

import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('앱이 첫 화면까지 뜬다', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: SaerokApp()));
    await tester.pumpAndSettle();

    // 시작 경로는 스플래시다. 아직 화면이 없어 자리 표시가 보인다.
    expect(find.text('A-1'), findsOneWidget);
  });
}
