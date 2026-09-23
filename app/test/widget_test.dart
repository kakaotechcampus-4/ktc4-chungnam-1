// 앱이 뜨고 첫 화면 이동이 이어지는지 확인한다.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/features/auth/auth_providers.dart';
import 'package:saerok/features/auth/auth_session.dart';
import 'package:saerok/features/auth/session_store.dart';
import 'package:saerok/main.dart';

/// 보관한 세션이 없는 단말이다.
///
/// 실제 보안 저장소는 플랫폼 채널이 필요해 테스트에서 끝나지 않는다. 세션
/// 복원은 `google_login_test.dart` 에서 따로 확인한다.
class _EmptySessionStore implements SessionStore {
  @override
  Future<AuthSession?> read() async => null;

  @override
  Future<void> write(AuthSession session) async {}

  @override
  Future<void> clear() async {}
}

void main() {
  testWidgets('앱이 스플래시로 뜨고 로그인으로 넘어간다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStoreProvider.overrideWithValue(_EmptySessionStore()),
        ],
        child: const SaerokApp(),
      ),
    );
    await tester.pump();

    expect(find.text('오늘의 만남을 준비해요'), findsOneWidget);

    // 스플래시는 잠깐 보여준 뒤, 되살릴 세션이 없으면 로그인으로 넘어간다.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text('로그인'), findsWidgets);
  });
}
