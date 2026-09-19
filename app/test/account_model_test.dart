import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, dynamic> accountJson;

  setUp(() async {
    final raw = await rootBundle.loadString('assets/mock/account.json');
    final fixture = jsonDecode(raw) as Map<String, dynamic>;
    accountJson = fixture['account'] as Map<String, dynamic>;
  });

  test('이메일을 보관하지 않는 계정을 읽는다', () {
    expect(accountJson['email'], isNull);
    expect(accountJson.containsKey('loginId'), isFalse);

    final account = Account.fromJson(accountJson);

    expect(account.accountId, 'account_demo_001');
    expect(account.authProvider, 'google');
    expect(account.email, isNull);
    expect(account.consentVersion, '2026-09-06');
  });

  test('이메일이 있는 응답은 값을 그대로 읽는다', () {
    accountJson['email'] = 'demo@example.com';

    expect(Account.fromJson(accountJson).email, 'demo@example.com');
  });

  test('이메일이 생략된 응답에 임의 값을 채우지 않는다', () {
    accountJson.remove('email');

    expect(Account.fromJson(accountJson).email, isNull);
  });

  test('이메일의 잘못된 타입을 정상 계정으로 읽지 않는다', () {
    accountJson['email'] = 42;

    expect(() => Account.fromJson(accountJson), throwsA(isA<TypeError>()));
  });
}
