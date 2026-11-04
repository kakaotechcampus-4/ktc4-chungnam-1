// 합성 응답으로 수동 분석 복구를 검사한다. 실제 AI와 기기 녹음 검증은 아니다.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saerok/data/api_client.dart';
import 'package:saerok/data/report_api.dart';
import 'package:saerok/features/review/upload_retry_controller.dart';
import 'package:saerok/features/visit/pending_uploads.dart';

import 'fake_card_api.dart';
import 'fake_pending_uploads.dart';
import 'fake_visit_api.dart';
import 'sample_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const target = (
    sessionId: FakeVisitApi.sessionId,
    analysisId: 'failed-analysis',
  );
  final provider = analysisRetryProvider(target);

  ProviderContainer setup(
    FakeVisitApi visits,
    FakePendingUploads uploads,
    Future<http.Response> Function(http.Request) handler,
  ) {
    final client = ApiClient(
      authorization: () => 'Bearer synthetic',
      baseUrl: 'https://synthetic.test',
      client: MockClient(handler),
    );
    final container = ProviderContainer(
      overrides: [
        withSampleProfile,
        ...mockCardsWith(visitApi: visits, pendingUploads: uploads),
        reportApiProvider.overrideWithValue(ReportApi(client)),
      ],
    );
    addTearDown(container.dispose);
    container.listen(provider, (_, _) {});
    return container;
  }

  test('전사가 남아 있으면 파일이 없어도 리포트만 다시 요청한다', () async {
    final visits = FakeVisitApi();
    var requests = 0;
    final container = setup(visits, FakePendingUploads(), (request) async {
      requests++;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/speech-analyses/failed-analysis/retry');
      return http.Response(
        jsonEncode({'analysisId': 'retry-analysis', 'status': 'sttCompleted'}),
        202,
      );
    });
    expect(
      await container.read(provider.future),
      UploadRetryOutcome.reportRequested,
    );
    expect(visits.calls, isEmpty);
    expect(requests, 1);
  });

  test('전사가 없으면 이미 전송했던 기기 파일을 다시 제출한다', () async {
    final visits = FakeVisitApi();
    final uploads = FakePendingUploads()
      ..uploaded[target.sessionId] = const PendingUpload(
        sessionId: FakeVisitApi.sessionId,
        audioPath: '/synthetic/kept.wav',
        participantCount: 2,
      );
    final container = setup(
      visits,
      uploads,
      (_) async => http.Response(
        jsonEncode({'errorCode': 'RECORDING_REQUIRED', 'message': 'synthetic failure'}),
        409,
      ),
    );
    expect(await container.read(provider.future), UploadRetryOutcome.sent);
    expect(visits.calls, ['audio']);
    expect(visits.audio?.audioPath, '/synthetic/kept.wav');
    expect(uploads.removedPaths, isEmpty);
  });

  test('전사도 기기 파일도 없으면 새 녹음을 꾸며 보내지 않는다', () async {
    final visits = FakeVisitApi();
    final container = setup(
      visits,
      FakePendingUploads(),
      (_) async =>
          http.Response(jsonEncode({'errorCode': 'RECORDING_REQUIRED'}), 409),
    );
    expect(await container.read(provider.future), UploadRetryOutcome.notFound);
    expect(visits.calls, isEmpty);
  });

  test('재요청 연결 실패를 녹음 재전송 사유로 쓰지 않는다', () async {
    final visits = FakeVisitApi();
    var attempts = 0;
    final container = setup(visits, FakePendingUploads(), (_) async {
      attempts++;
      throw http.ClientException('synthetic disconnected');
    });
    await expectLater(
      container.read(provider.future),
      throwsA(isA<ApiNetworkFailure>()),
    );
    expect(visits.calls, isEmpty);
    expect(attempts, 1, reason: '자동 반복 요청하지 않는다');
  });

  test('권한 거절을 녹음 재전송으로 우회하지 않는다', () async {
    final visits = FakeVisitApi();
    final container = setup(
      visits,
      FakePendingUploads(),
      (_) async => http.Response(
        jsonEncode({'errorCode': 'SPEECH_PROCESSING_CONSENT_REQUIRED'}),
        403,
      ),
    );
    await expectLater(
      container.read(provider.future),
      throwsA(isA<ApiServerFailure>()),
    );
    expect(visits.calls, isEmpty);
  });
}
