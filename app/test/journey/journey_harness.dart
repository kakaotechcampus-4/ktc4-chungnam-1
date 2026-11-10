// 앱 전체 여정 테스트의 실행 틀이다.
//
// `lib/main.dart` 의 `SaerokApp` 을 그대로 띄운다. 라우터(`buildRouter`)와
// Riverpod provider 도 앱의 것이다. 바꾸는 것은 기기와 서버에 닿는 경계뿐이다.
//
// | 경계 | 대역 |
// | --- | --- |
// | 서버 HTTP (`apiClientProvider`, `authApiProvider`) | [JourneyServer] 의 MockClient |
// | 단말 세션 보관(보안 저장소) | [_MemorySessionStore]. 로그인한 세션이 들어 있다 |
// | 구글 로그인 SDK | [_NoGoogle]. 부르면 실패한다 |
// | 마이크 | [JourneyRecorder]. 임시 폴더에 합성 무음 WAV 를 쓴다 |
// | 카메라, 갤러리, 면회 사진 보관 | 기존 `test/fake_visit_*.dart` |
// | 녹음 재전송 기록, 고른 어르신 기억 | 기존 메모리 대역 |
// | 화면 켜짐 플랫폼 채널 | `FakeScreenAwakePlatform` |
// | 녹음 알림 포그라운드 서비스 채널 | `FakeRecordingServicePlatform` |
//
// 분석과 카드 생성을 기다리는 간격만 짧게 바꾼다. 화면 동작은 같고 기다리는
// 시간만 줄인다.
//
// `flutter test`(호스트, 가짜 시계)와 `flutter test integration_test/`(기기,
// 실제 시계)에서 같은 코드가 돈다. 그래서 `pumpAndSettle` 대신 찾는 화면이
// 나올 때까지 조금씩 시간을 흘리는 [JourneyDriver.waitFor] 를 쓴다.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/api_client.dart';
import 'package:saerok/data/auth_api.dart';
import 'package:saerok/data/mock_repository.dart';
import 'package:saerok/data/profile_relationship_store.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/data/selected_profile_store.dart';
import 'package:saerok/features/auth/auth_providers.dart';
import 'package:saerok/features/auth/auth_session.dart';
import 'package:saerok/features/auth/google_authenticator.dart';
import 'package:saerok/features/auth/session_refresher.dart';
import 'package:saerok/features/auth/session_store.dart';
import 'package:saerok/features/cards/card_generation_controller.dart';
import 'package:saerok/features/visit/pending_uploads.dart';
import 'package:saerok/features/visit/visit_camera.dart';
import 'package:saerok/features/visit/visit_gallery.dart';
import 'package:saerok/features/visit/visit_photos.dart';
import 'package:saerok/features/visit/visit_recorder.dart';
import 'package:saerok/main.dart';

import '../fake_pending_uploads.dart';
import '../fake_recording_service.dart';
import '../fake_screen_awake.dart';
import '../fake_profile_relationship_store.dart';
import '../fake_selected_profile_store.dart';
import '../fake_visit_camera.dart';
import '../fake_visit_gallery.dart';
import '../fake_visit_photos.dart';
import 'journey_server.dart';

/// 실제 앱을 띄우고 화면을 눌러 가며 확인한다.
class JourneyDriver {
  JourneyDriver._(this.tester, this.server, this.uploads, this.recorder);

  final WidgetTester tester;
  final JourneyServer server;
  final FakePendingUploads uploads;

  /// 앱이 쓰는 마이크 대역. 녹음을 언제 시작했는지 센다.
  final JourneyRecorder recorder;

  /// 로그인한 보호자가 앱을 켠 상태로 시작한다. 스플래시가 보관한 세션을
  /// 서버(`GET /auth/me`)로 확인하고 홈으로 넘어간다.
  static Future<JourneyDriver> launch(
    WidgetTester tester,
    JourneyServer server,
  ) async {
    // 기준 화면 412 x 917 dp 다(`app/README.md`).
    tester.view.physicalSize = const Size(1236, 2751);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final audioDir = Directory.systemTemp.createTempSync('saerok_journey_');
    addTearDown(() {
      if (audioDir.existsSync()) audioDir.deleteSync(recursive: true);
    });
    final uploads = FakePendingUploads();
    final driver = JourneyDriver._(
      tester,
      server,
      uploads,
      JourneyRecorder(audioDir),
    );

    // 앱에 묶인 합성 목 자료(asset)는 실제 시간에서 먼저 읽는다. `rootBundle`
    // 은 읽은 Future 를 기억하는데, 가짜 시계 안에서 처음 읽으면 다음 테스트에서
    // 그 Future 가 끝나지 않는다. 앱이 읽는 자료 그대로이며 바꾸지 않는다.
    const repository = MockRepository();
    await tester.runAsync(() async {
      await repository.loadProfile();
      await repository.loadAccount();
      await repository.loadVisitReport();
      await repository.loadVisitSession();
      await repository.loadCaregiverEvaluation();
      await repository.loadChangeProposal();
    });

    await tester.pumpWidget(
      ProviderScope(overrides: driver._overrides(), child: const SaerokApp()),
    );
    return driver;
  }

  List<Override> _overrides() => [
    sessionStoreProvider.overrideWithValue(_MemorySessionStore(_session())),
    googleAuthenticatorProvider.overrideWithValue(const _NoGoogle()),
    authApiProvider.overrideWith(
      (ref) => AuthApi(baseUrl: JourneyServer.baseUrl, client: server.client),
    ),
    // 앱의 provider 와 같이 세션 갱신기를 단다. 서버 주소와 HTTP 만 바꾼다.
    apiClientProvider.overrideWith((ref) {
      final refresher = ref.read(sessionRefresherProvider);
      return ApiClient(
        authorization: () => ref.read(sessionProvider)?.authorizationHeader,
        beforeRequest: refresher.refreshIfExpiring,
        reauthenticate: refresher.retryAfterUnauthorized,
        continues: refresher.continues,
        baseUrl: JourneyServer.baseUrl,
        client: server.client,
      );
    }),
    selectedProfileStoreProvider.overrideWithValue(FakeSelectedProfileStore()),
    profileRelationshipStoreProvider.overrideWithValue(
      FakeProfileRelationshipStore(),
    ),
    visitRecorderProvider.overrideWithValue(recorder),
    pendingUploadsProvider.overrideWith((ref) => uploads),
    visitPhotosProvider.overrideWith((ref) => FakeVisitPhotos()),
    visitCameraProvider.overrideWithValue(FakeVisitCamera()),
    visitGalleryProvider.overrideWithValue(FakeVisitGallery()),
    FakeScreenAwakePlatform().asOverride,
    FakeRecordingServicePlatform().asOverride,
    reportPollIntervalProvider.overrideWithValue(
      const Duration(milliseconds: 200),
    ),
    cardPollIntervalProvider.overrideWithValue(
      const Duration(milliseconds: 200),
    ),
  ];

  static AuthSession _session() => AuthSession(
    accessToken: 'journey-token',
    tokenType: 'Bearer',
    expiresAt: DateTime(2100),
    account: const AuthAccount(
      accountId: JourneyServer.accountId,
      authProvider: 'google',
      displayName: '테스트 보호자',
      email: null,
      consentVersion: '2026-10-01',
      createdAt: '2026-10-13T09:00:00+09:00',
    ),
  );

  // ── 기다리기와 누르기 ──────────────────────────────

  /// 한 걸음. 실제 비동기 처리(HTTP 대역, 파일, asset)에 차례를 주고 화면을
  /// 한 장 그린다. 호스트에서는 가짜 시계를 100ms 흘린다.
  Future<void> step() async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// [finder] 가 나올 때까지 기다린다. 나오면 화면 전환이 끝나도록 조금 더
  /// 흘린다. 끝내 나오지 않으면 실패한다.
  Future<void> waitFor(Finder finder, {int maxSteps = 150}) async {
    for (var i = 0; i < maxSteps; i++) {
      if (finder.evaluate().isNotEmpty) {
        for (var j = 0; j < 6; j++) {
          await step();
        }
        return;
      }
      await step();
    }
    throw TestFailure(
      '화면에 나오지 않았다: $finder / 지금 화면의 글자: ${_texts()} / 최근 요청: ${_recent()}',
    );
  }

  /// 실패 메시지에 붙일 지금 화면의 글자.
  List<String> _texts() => [
    for (final w in tester.widgetList<Text>(find.byType(Text)))
      w.data ?? w.textSpan?.toPlainText() ?? '',
  ];

  /// 실패 메시지에 붙일 최근 요청과 응답 코드.
  List<String> _recent() => [
    for (final r in server.responses.reversed.take(8).toList().reversed)
      '${r.method} ${r.path} ${r.status}',
  ];

  /// [finder] 가 사라질 때까지 기다린다.
  Future<void> waitUntilGone(Finder finder, {int maxSteps = 150}) async {
    for (var i = 0; i < maxSteps; i++) {
      if (finder.evaluate().isEmpty) return;
      await step();
    }
    throw TestFailure('화면에서 사라지지 않았다: $finder');
  }

  /// 보이게 끌어온 뒤 누른다. 누른 결과는 부르는 쪽이 [waitFor] 로 기다린다.
  Future<void> tap(Finder finder) async {
    await waitFor(finder);
    await tester.ensureVisible(finder);
    await step();
    await tester.tap(finder);
    await step();
  }

  /// 기기의 뒤로 가기 버튼을 누른다.
  Future<void> back() async {
    await tester.binding.handlePopRoute();
    for (var j = 0; j < 6; j++) {
      await step();
    }
  }

  /// 화면을 닫고 남은 타이머를 흘려보낸다. 앱 provider 도 함께 정리된다.
  Future<void> close() async {
    await tester.pumpWidget(const SizedBox());
    for (var j = 0; j < 10; j++) {
      await step();
    }
  }
}

/// 구글 로그인을 쓰지 않는 여정이다. 보관한 세션이 살아 있어 부르지 않는다.
class _NoGoogle implements GoogleAuthenticator {
  const _NoGoogle();

  @override
  Future<String?> idToken() async => null;

  @override
  Future<String?> silentIdToken() async => null;

  @override
  Future<void> signOut() async {}
}

class _MemorySessionStore implements SessionStore {
  _MemorySessionStore(this._session);

  AuthSession? _session;

  @override
  Future<AuthSession?> read() async => _session;

  @override
  Future<void> write(AuthSession session) async => _session = session;

  @override
  Future<void> clear() async => _session = null;
}

/// 마이크 대신 합성 무음 WAV(16kHz, 16-bit, mono, 0.1초)를 쓴다.
///
/// 앱이 6-2 로 파일을 실제로 읽어 multipart 로 보내므로 빈 경로가 아닌 파일이
/// 있어야 한다. 사람 목소리가 아니다.
class JourneyRecorder implements VisitRecorder {
  JourneyRecorder(this._dir);

  final Directory _dir;
  int _files = 0;
  String? _path;

  /// [start] 를 부른 횟수. 녹음 전 승인보다 먼저 녹음하지 않았는지 본다.
  int starts = 0;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<VisitRecording> start() async {
    starts++;
    final path = '${_dir.path}${Platform.pathSeparator}visit-${++_files}.wav';
    File(path).writeAsBytesSync(_silentWav());
    _path = path;
    return VisitRecording(path: path);
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<VisitRecording?> stop() async {
    final path = _path;
    return path == null ? null : VisitRecording(path: path);
  }

  @override
  Future<void> dispose() async {}

  static Uint8List _silentWav() {
    const sampleRate = 16000;
    const samples = 1600;
    const dataBytes = samples * 2;
    final header = ByteData(44)
      ..setUint32(0, 0x52494646) // RIFF
      ..setUint32(4, 36 + dataBytes, Endian.little)
      ..setUint32(8, 0x57415645) // WAVE
      ..setUint32(12, 0x666d7420) // fmt
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little) // PCM
      ..setUint16(22, 1, Endian.little) // mono
      ..setUint32(24, sampleRate, Endian.little)
      ..setUint32(28, sampleRate * 2, Endian.little)
      ..setUint16(32, 2, Endian.little)
      ..setUint16(34, 16, Endian.little)
      ..setUint32(36, 0x64617461) // data
      ..setUint32(40, dataBytes, Endian.little);
    return Uint8List.fromList([
      ...header.buffer.asUint8List(),
      ...Uint8List(dataBytes),
    ]);
  }
}
