// G-1 리포트의 `녹음 파일 공유` 를 확인한다(2026-11-09 PM 결정).
//
// 이 기기에 그 회차의 녹음 파일이 남아 있을 때만 버튼을 두고, 누르면 그 파일로
// 공유 창을 연다. 기기 기록은 `FakePendingUploads`, 공유 창은 `FakeRecordingShare` 다.
// 실제 파일과 공유 창은 쓰지 않는다. 값은 모두 합성이다.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/report/report_screen.dart';
import 'package:saerok/features/visit/pending_uploads.dart';
import 'package:saerok/features/visit/recording_share.dart';

import 'fake_pending_uploads.dart';
import 'fake_recording_share.dart';

const _sessionId = 'session_test_001';
const _audioPath = '/fake/visit_recordings/visit-1.wav';

const _report = VisitReport(
  reportId: _sessionId,
  sessionId: _sessionId,
  reportStatus: ReportStatus.ready,
  title: '합성 리포트 제목',
  visitDate: '2026-11-09',
  mood: VisitMood.good,
  summaryText: '합성 리포트 본문이에요.',
  cardSummaries: [],
);

/// 기록을 읽다 실패하는 기기.
class _BrokenUploads extends FakePendingUploads {
  @override
  Future<PendingUpload?> find(
    String sessionId, {
    bool includeUploaded = false,
  }) async => throw const FileSystemException('합성 실패');
}

/// 서버가 받은 뒤에도 기기에 남은 녹음.
FakePendingUploads _uploadedRecording() => FakePendingUploads()
  ..uploaded[_sessionId] = const PendingUpload(
    sessionId: _sessionId,
    audioPath: _audioPath,
    participantCount: 2,
  );

Future<void> _open(
  WidgetTester tester, {
  required PendingUploads uploads,
  RecordingShare? share,
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(1236, 4800);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        reportProvider.overrideWith((ref, reportId) async => _report),
        reportCardReviewsProvider.overrideWith(
          (ref, reportId) async => const <CardReview>[],
        ),
        reportSelectedCardIdsProvider.overrideWith(
          (ref, reportId) async => null,
        ),
        reportProposalsProvider.overrideWith(
          (ref, reportId) async => const ChangeProposal(
            sessionId: _sessionId,
            lifeFactProposals: [],
            topicProposals: [],
          ),
        ),
        pendingUploadsProvider.overrideWith((ref) => uploads),
        recordingShareProvider.overrideWithValue(share ?? FakeRecordingShare()),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const ReportScreen(reportId: _sessionId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _shareButton => find.widgetWithText(OutlinedButton, '녹음 파일 공유');

void main() {
  testWidgets('기기에 녹음이 남은 회차면 안내 문구 없이 공유 버튼만 둔다', (tester) async {
    await _open(tester, uploads: _uploadedRecording());

    expect(find.text('합성 리포트 본문이에요.'), findsOneWidget);
    expect(_shareButton, findsOneWidget);
    // 2026-11-09 PM 결정: 파일에 대화가 담겼다는 안내와 구역 이름을 두지 않는다.
    expect(find.textContaining('담겨 있어요'), findsNothing);
    expect(find.text('녹음 파일'), findsNothing);
  });

  testWidgets('아직 보내지 못한 녹음도 공유할 수 있다', (tester) async {
    final uploads = FakePendingUploads()
      ..saved[_sessionId] = const PendingUpload(
        sessionId: _sessionId,
        audioPath: _audioPath,
        participantCount: null,
      );
    await _open(tester, uploads: uploads);

    expect(_shareButton, findsOneWidget);
  });

  testWidgets('기기에 녹음이 없으면 공유 자리를 두지 않는다', (tester) async {
    await _open(tester, uploads: FakePendingUploads());

    expect(find.text('합성 리포트 본문이에요.'), findsOneWidget);
    expect(find.text('녹음 파일 공유'), findsNothing);
  });

  testWidgets('다른 회차의 녹음은 공유하지 않는다', (tester) async {
    final uploads = FakePendingUploads()
      ..uploaded['session_test_other'] = const PendingUpload(
        sessionId: 'session_test_other',
        audioPath: '/fake/visit_recordings/visit-2.wav',
        participantCount: 2,
      );
    await _open(tester, uploads: uploads);

    expect(find.text('녹음 파일 공유'), findsNothing);
  });

  testWidgets('기기 기록을 읽지 못해도 리포트는 보여주고 공유는 두지 않는다', (tester) async {
    await _open(tester, uploads: _BrokenUploads());

    expect(find.text('합성 리포트 본문이에요.'), findsOneWidget);
    expect(find.text('녹음 파일 공유'), findsNothing);
  });

  testWidgets('누르면 그 회차의 녹음 파일로 공유 창을 연다', (tester) async {
    final share = FakeRecordingShare();
    await _open(tester, uploads: _uploadedRecording(), share: share);

    await tester.tap(_shareButton);
    await tester.pumpAndSettle();

    expect(share.paths, [_audioPath]);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('그 사이 파일이 사라졌으면 알리고 버튼을 거둔다', (tester) async {
    final uploads = _uploadedRecording();
    final share = FakeRecordingShare(
      result: RecordingShareResult.missing,
      onShare: uploads.uploaded.clear,
    );
    await _open(tester, uploads: uploads, share: share);

    await tester.tap(_shareButton);
    await tester.pumpAndSettle();

    expect(find.text('녹음 파일을 찾지 못했어요.'), findsOneWidget);
    expect(_shareButton, findsNothing);
  });

  testWidgets('공유 창을 열지 못하면 알리고 버튼은 남긴다', (tester) async {
    final share = FakeRecordingShare(result: RecordingShareResult.failed);
    await _open(tester, uploads: _uploadedRecording(), share: share);

    await tester.tap(_shareButton);
    await tester.pumpAndSettle();

    expect(find.text('녹음 파일을 공유하지 못했어요.'), findsOneWidget);
    expect(_shareButton, findsOneWidget);
  });

  testWidgets('글자를 키워도 공유 자리가 넘치지 않는다', (tester) async {
    await _open(tester, uploads: _uploadedRecording(), textScale: 1.5);

    expect(tester.takeException(), isNull);
    expect(tester.getSize(_shareButton).height, greaterThanOrEqualTo(48));
  });

  group('기기 공유', () {
    test('파일이 없으면 공유 창을 열지 않고 missing 이다', () async {
      final missing =
          '${Directory.systemTemp.path}/saerok-test-missing-${DateTime.now().microsecondsSinceEpoch}.wav';

      expect(
        await const DeviceRecordingShare().share(missing),
        RecordingShareResult.missing,
      );
    });
  });
}
