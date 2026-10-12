// 계정을 바꿀 때 리포트 알림이 어디에 남는지 확인한다.
//
// 알림은 계정마다 따로 둔다. 로그아웃해도 지우지 않고, 다른 계정에는 보이지
// 않다가 그 계정으로 다시 들어오면 다시 보인다. 탈퇴한 계정의 알림만 지운다.

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:saerok/data/auth_api.dart';
import 'package:saerok/data/mock_repository.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/features/auth/auth_providers.dart';
import 'package:saerok/features/auth/auth_session.dart';
import 'package:saerok/features/auth/google_authenticator.dart';
import 'package:saerok/features/auth/session_store.dart';
import 'package:saerok/features/profile_setup/setup_controller.dart';

import 'sample_profile.dart';

/// 리포트 도착 시점을 테스트가 직접 정하는 저장소다.
class _WaitingRepository extends MockRepository {
  _WaitingRepository();

  final ready = Completer<void>();

  @override
  Future<void> awaitReportReady() => ready.future;
}

class _FakeGoogleAuthenticator implements GoogleAuthenticator {
  @override
  Future<String?> idToken() async => null;

  @override
  Future<String?> silentIdToken() async => null;

  @override
  Future<void> signOut() async {}
}

class _FakeSessionStore implements SessionStore {
  AuthSession? _session;

  @override
  Future<AuthSession?> read() async => _session;

  @override
  Future<void> write(AuthSession session) async => _session = session;

  @override
  Future<void> clear() async => _session = null;
}

/// 로그인한 계정의 어르신 목록을 서버처럼 내려준다.
///
/// 앱은 아직 서버의 프로필 목록(`api-spec.md` 2-1)을 받지 않아 로그아웃하면
/// 목록이 비고 다시 들어와도 빈 목록이다. 알림은 서버를 붙였을 때처럼 같은
/// 계정에 같은 어르신이 돌아오는 경우를 기준으로 확인한다.
class _ServerLikeProfiles extends CareProfilesNotifier {
  @override
  CareProfiles build() {
    final accountId = ref.watch(
      sessionProvider.select((s) => s?.account.accountId),
    );
    if (accountId == null) {
      return const CareProfiles(entries: [], selectedId: null);
    }
    final id = 'profile-of-$accountId';
    return CareProfiles(
      entries: [CareProfileEntry(id: id, basicInfo: sampleBasicInfo)],
      selectedId: id,
    );
  }
}

/// 합성 계정이다. 실제 사용자 정보가 아니다.
AuthSession _sessionOf(String accountId) => AuthSession(
  accessToken: 'fake-token-$accountId',
  tokenType: 'Bearer',
  expiresAt: DateTime(2100),
  account: AuthAccount(
    accountId: accountId,
    authProvider: 'google',
    displayName: '테스트 보호자',
    email: null,
    consentVersion: null,
    createdAt: null,
  ),
);

void main() {
  late _WaitingRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = _WaitingRepository();
    container = ProviderContainer(
      overrides: [
        careProfilesProvider.overrideWith(_ServerLikeProfiles.new),
        mockRepositoryProvider.overrideWithValue(repository),
        // 서버에 닿지 않아도 로그아웃은 된다. 알림만 보려고 서버를 끊어 둔다.
        authApiProvider.overrideWithValue(
          AuthApi(
            baseUrl: 'http://api.test',
            client: MockClient(
              (request) async => throw const SocketException('오프라인'),
            ),
          ),
        ),
        googleAuthenticatorProvider.overrideWithValue(
          _FakeGoogleAuthenticator(),
        ),
        sessionStoreProvider.overrideWithValue(_FakeSessionStore()),
      ],
    );
    addTearDown(container.dispose);
  });

  ReportNotice? notice() => container.read(reportNoticeProvider);

  void signIn(String accountId) =>
      container.read(sessionProvider.notifier).restore(_sessionOf(accountId));

  /// 프로필 설정의 로그아웃 버튼과 같은 순서다. `forgetCareProfiles` 가 지우는
  /// 것을 그대로 지운다.
  Future<void> signOut() async {
    await container.read(sessionProvider.notifier).signOut();
    container
      ..invalidate(careProfilesProvider)
      ..invalidate(setupControllerProvider)
      ..invalidate(pendingSetupsProvider);
  }

  /// 기다리던 리포트가 도착한다.
  Future<void> reportArrives() async {
    repository.ready.complete();
    await Future<void>.delayed(Duration.zero);
  }

  test('다른 계정으로 들어오면 앞 계정의 알림이 보이지 않는다', () async {
    signIn('account-a');
    container.read(reportNoticeProvider.notifier).arrive();
    expect(notice(), ReportNotice.ready);

    await signOut();
    signIn('account-b');

    expect(notice(), isNull);
  });

  test('원래 계정으로 다시 들어오면 알림이 다시 보인다', () async {
    signIn('account-a');
    container.read(reportNoticeProvider.notifier).arrive();

    await signOut();
    signIn('account-b');
    await signOut();
    signIn('account-a');

    expect(notice(), ReportNotice.ready);
  });

  test('로그아웃한 사이 도착한 리포트는 기다리던 계정에 남는다', () async {
    signIn('account-a');
    container.read(reportNoticeProvider.notifier).startGenerating();
    expect(notice(), ReportNotice.generating);

    await signOut();
    signIn('account-b');
    await reportArrives();

    expect(notice(), isNull, reason: '다른 계정에 도착을 띄우지 않는다');

    await signOut();
    signIn('account-a');

    expect(notice(), ReportNotice.ready);
  });

  test('다른 계정에서 확인을 마쳐도 앞 계정의 알림은 남는다', () async {
    signIn('account-a');
    container.read(reportNoticeProvider.notifier).arrive();

    await signOut();
    signIn('account-b');
    container.read(reportNoticeProvider.notifier).arrive();
    container.read(reportNoticeProvider.notifier).dismiss();
    expect(notice(), isNull);

    await signOut();
    signIn('account-a');

    expect(notice(), ReportNotice.ready);
  });

  group('탈퇴', () {
    test('탈퇴한 계정의 알림은 지우고 다른 계정의 알림은 남긴다', () async {
      signIn('account-b');
      container.read(reportNoticeProvider.notifier).arrive();
      await signOut();

      signIn('account-a');
      container.read(reportNoticeProvider.notifier).arrive();
      container.read(reportNoticeProvider.notifier).forgetAccount('account-a');

      expect(notice(), isNull);

      await signOut();
      signIn('account-b');

      expect(notice(), ReportNotice.ready);
    });

    test('탈퇴한 뒤에 도착한 리포트는 버린다', () async {
      signIn('account-a');
      container.read(reportNoticeProvider.notifier).startGenerating();
      container.read(reportNoticeProvider.notifier).forgetAccount('account-a');

      await reportArrives();
      // 같은 계정 이름으로 다시 들어와도 지난 계정의 리포트를 띄우지 않는다.
      signIn('account-a');

      expect(notice(), isNull);
    });
  });
}
