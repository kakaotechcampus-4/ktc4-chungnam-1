// 앱을 다시 켠 뒤의 `음성 다시 보내기`(`/visit/upload`)를 확인한다.
//
// `lib/features/review/upload_retry_controller.dart`. 서버와 기기 기록은
// 대역을 쓰고 값은 모두 합성이다.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/api_client.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/features/review/upload_retry_controller.dart';
import 'package:saerok/features/visit/pending_uploads.dart';

import 'fake_card_api.dart';
import 'fake_pending_uploads.dart';
import 'fake_visit_api.dart';
import 'sample_profile.dart';

const _sessionId = FakeVisitApi.sessionId;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer makeContainer(
    FakeVisitApi api,
    FakePendingUploads uploads, {
    String? sessionId = _sessionId,
  }) {
    final container = ProviderContainer(
      overrides: [
        withSampleProfile,
        ...mockCardsWith(visitApi: api, pendingUploads: uploads),
      ],
    );
    addTearDown(container.dispose);
    // autoDispose 라서 보는 쪽이 있어야 살아 있다. 화면이 보는 것과 같다.
    container.listen(uploadRetryProvider(sessionId), (_, _) {});
    return container;
  }

  FakePendingUploads withPending() => FakePendingUploads()
    ..saved[_sessionId] = const PendingUpload(
      sessionId: _sessionId,
      audioPath: '/synthetic/visit.wav',
      participantCount: 3,
    );

  test('기록한 녹음과 참여자 수를 보내고 보냈다고 적는다', () async {
    final api = FakeVisitApi();
    final uploads = withPending();
    final container = makeContainer(api, uploads);

    final outcome = await container.read(
      uploadRetryProvider(_sessionId).future,
    );

    expect(outcome, UploadRetryOutcome.sent);
    expect(api.calls, ['audio'], reason: '평가는 다시 보내지 않는다');
    expect(api.audio?.audioPath, '/synthetic/visit.wav');
    expect(api.audio?.participantCount, 3);
    expect(uploads.saved, isEmpty);
    expect(uploads.uploaded[_sessionId]?.audioPath, '/synthetic/visit.wav');
    expect(uploads.removedPaths, isEmpty, reason: '서버가 받아도 원본은 남긴다');
    expect(
      container.read(reportNoticeProvider),
      ReportNotice.generating,
      reason: '홈에 리포트를 만드는 중을 알린다',
    );
  });

  test('기록이 없으면 보내지 않고 찾을 수 없다고 한다', () async {
    final api = FakeVisitApi();
    final container = makeContainer(api, FakePendingUploads());

    expect(
      await container.read(uploadRetryProvider(_sessionId).future),
      UploadRetryOutcome.notFound,
    );
    expect(api.calls, isEmpty);
  });

  test('주소에 회차가 없으면 찾을 수 없다고 한다', () async {
    final api = FakeVisitApi();
    final container = makeContainer(api, withPending(), sessionId: null);

    expect(
      await container.read(uploadRetryProvider(null).future),
      UploadRetryOutcome.notFound,
    );
    expect(api.calls, isEmpty);
  });

  test('이미 끝난 회차라고 거절되면 보냈다고 적고 알림은 띄우지 않는다', () async {
    final api = FakeVisitApi(
      audioFailure: const ApiServerFailure(
        statusCode: 409,
        errorCode: 'ANALYSIS_ALREADY_FAILED',
      ),
    );
    final uploads = withPending();
    final container = makeContainer(api, uploads);

    expect(
      await container.read(uploadRetryProvider(_sessionId).future),
      UploadRetryOutcome.alreadyClosed,
    );
    expect(uploads.saved, isEmpty);
    expect(uploads.uploaded, contains(_sessionId));
    expect(uploads.removedPaths, isEmpty);
    expect(container.read(reportNoticeProvider), isNull);
  });

  test('보내지 못하면 기록을 남기고 다시 보내기로 다시 보낸다', () async {
    final api = FakeVisitApi(audioFailure: const ApiNetworkFailure());
    final uploads = withPending();
    final container = makeContainer(api, uploads);
    final provider = uploadRetryProvider(_sessionId);

    await expectLater(
      container.read(provider.future),
      throwsA(isA<ApiNetworkFailure>()),
    );
    expect(uploads.saved, contains(_sessionId));

    api.audioFailure = null;
    container.read(provider.notifier).retry();

    expect(await container.read(provider.future), UploadRetryOutcome.sent);
    expect(api.calls, ['audio', 'audio']);
  });

  test('리포트 알림에 받은 분석 작업 ID 를 넘긴다', () async {
    final notice = _RecordingNotice();
    final container = ProviderContainer(
      overrides: [
        withSampleProfile,
        ...mockCardsWith(
          visitApi: FakeVisitApi(),
          pendingUploads: withPending(),
        ),
        reportNoticeProvider.overrideWith(() => notice),
      ],
    );
    addTearDown(container.dispose);
    container.listen(uploadRetryProvider(_sessionId), (_, _) {});

    await container.read(uploadRetryProvider(_sessionId).future);

    expect(_RecordingNotice.analysisIds, [FakeVisitApi.analysisId]);
  });
}

/// 리포트 알림에 넘긴 분석 작업 ID 를 모은다.
class _RecordingNotice extends ReportNoticeNotifier {
  static final analysisIds = <String?>[];

  @override
  void startGenerating({String? analysisId}) => analysisIds.add(analysisId);
}
