// 릴리스 빌드의 서버 주소와 구글 클라이언트 ID 검사를 확인한다.
//
// 값은 모두 지어낸 예시다. 실제 주소와 클라이언트 ID 를 넣지 않는다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/app/release_config.dart';
import 'package:saerok/widgets/app_states.dart';

const _httpsUrl = 'https://api.example.com';
const _clientId = 'example-client-id.apps.googleusercontent.com';

List<ReleaseConfigProblem> _release({
  String apiBaseUrl = _httpsUrl,
  String googleServerClientId = _clientId,
}) => releaseConfigProblems(
  isRelease: true,
  apiBaseUrl: apiBaseUrl,
  googleServerClientId: googleServerClientId,
);

void main() {
  group('릴리스 빌드', () {
    test('https 주소와 클라이언트 ID 가 있으면 통과한다', () {
      expect(_release(), isEmpty);
      expect(_release(apiBaseUrl: 'https://api.example.com:8443/v1'), isEmpty);
    });

    test('기본값인 에뮬레이터 http 주소를 막는다', () {
      expect(_release(apiBaseUrl: 'http://10.0.2.2:8000'), [
        ReleaseConfigProblem.apiBaseUrlNotHttps,
      ]);
    });

    test('https 가 아니거나 host 가 없는 주소를 막는다', () {
      for (final url in [
        'http://api.example.com',
        'HTTP://api.example.com',
        'api.example.com',
        'https://',
        'https:///v1',
        'ftp://api.example.com',
        ' https://api.example.com',
        'https://api.example.com ',
      ]) {
        expect(_release(apiBaseUrl: url), [
          ReleaseConfigProblem.apiBaseUrlNotHttps,
        ], reason: url);
      }
    });

    test('scheme 대소문자는 구분하지 않는다', () {
      expect(_release(apiBaseUrl: 'HTTPS://api.example.com'), isEmpty);
    });

    test('빈 서버 주소는 비어 있다고 알린다', () {
      expect(_release(apiBaseUrl: ''), [
        ReleaseConfigProblem.apiBaseUrlMissing,
      ]);
      expect(_release(apiBaseUrl: '   '), [
        ReleaseConfigProblem.apiBaseUrlMissing,
      ]);
    });

    test('빈 클라이언트 ID 를 막는다', () {
      expect(_release(googleServerClientId: ''), [
        ReleaseConfigProblem.googleServerClientIdMissing,
      ]);
      expect(_release(googleServerClientId: '  '), [
        ReleaseConfigProblem.googleServerClientIdMissing,
      ]);
    });

    test('여러 문제를 한 번에 알린다', () {
      expect(
        _release(apiBaseUrl: 'http://10.0.2.2:8000', googleServerClientId: ''),
        [
          ReleaseConfigProblem.apiBaseUrlNotHttps,
          ReleaseConfigProblem.googleServerClientIdMissing,
        ],
      );
    });
  });

  test('디버그 빌드는 검사하지 않는다', () {
    expect(
      releaseConfigProblems(
        isRelease: false,
        apiBaseUrl: 'http://10.0.2.2:8000',
        googleServerClientId: '',
      ),
      isEmpty,
    );
  });

  test('테스트 실행은 릴리스가 아니므로 현재 값으로도 문제를 내지 않는다', () {
    expect(currentReleaseConfigProblems(isRelease: false), isEmpty);
  });

  test('문구에 값 대신 고칠 설정 이름만 담는다', () {
    expect(
      ReleaseConfigProblem.apiBaseUrlNotHttps.message,
      contains('SAEROK_API_BASE_URL'),
    );
    expect(
      ReleaseConfigProblem.googleServerClientIdMissing.message,
      contains('SAEROK_GOOGLE_SERVER_CLIENT_ID'),
    );
  });

  test('.env.example 을 고치지 않고 복사하면 릴리스 검사에 걸린다', () {
    // 클라이언트 ID 만 채우고 서버 주소를 그대로 두면 예시 주소로 릴리스가
    // 나간다. 예시 서버 주소는 https 가 아니어야 검사가 막는다.
    final values = <String, String>{};
    for (final line in File('.env.example').readAsLinesSync()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final eq = trimmed.indexOf('=');
      if (eq < 0) continue;
      values[trimmed.substring(0, eq)] = trimmed.substring(eq + 1);
    }

    expect(values.containsKey('SAEROK_API_BASE_URL'), isTrue);
    expect(
      _release(apiBaseUrl: values['SAEROK_API_BASE_URL']!),
      contains(ReleaseConfigProblem.apiBaseUrlNotHttps),
    );
  });

  testWidgets('설정 오류 화면은 안내와 고칠 항목을 보여 준다', (tester) async {
    await tester.pumpWidget(
      const ReleaseConfigErrorApp(
        problems: [
          ReleaseConfigProblem.apiBaseUrlNotHttps,
          ReleaseConfigProblem.googleServerClientIdMissing,
        ],
      ),
    );

    expect(find.byType(ErrorStateView), findsOneWidget);
    expect(find.textContaining('앱 설정이 올바르지 않아'), findsOneWidget);
    expect(find.textContaining('https 주소가 아니에요'), findsOneWidget);
    expect(
      find.textContaining('SAEROK_GOOGLE_SERVER_CLIENT_ID 가 비어 있어요'),
      findsOneWidget,
    );
    expect(find.text('다시 시도'), findsNothing);
  });
}
