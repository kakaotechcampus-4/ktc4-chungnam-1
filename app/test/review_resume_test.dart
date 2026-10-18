// 앱을 다시 켠 뒤 `평가 이어서 하기`(`/visit/review?session=<회차 ID>`)를
// 확인한다. 서버와 기기 기록은 대역을 쓰고 값은 모두 합성이다.
//
// 목 묶음(`conversation-cards.json`)은 `session_demo_001` 이 쓰는 중이고 네 장을
// 골랐다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/api_client.dart';
import 'package:saerok/data/card_api.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/features/review/review_controller.dart';
import 'package:saerok/features/review/review_screen.dart';
import 'package:saerok/features/review/status_notice.dart';
import 'package:saerok/features/review/submission_controller.dart';
import 'package:saerok/features/visit/pending_uploads.dart';

import 'fake_card_api.dart';
import 'fake_pending_uploads.dart';
import 'fake_visit_api.dart';
import 'sample_profile.dart';

const _sessionId = 'session_demo_001';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer makeContainer({
    required FakeVisitApi api,
    required FakePendingUploads uploads,
  }) {
    final container = ProviderContainer(
      overrides: [
        withSampleProfile,
        ...mockCardsWith(visitApi: api, pendingUploads: uploads),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  FakePendingUploads withPending() => FakePendingUploads()
    ..saved[_sessionId] = const PendingUpload(
      sessionId: _sessionId,
      audioPath: '/synthetic/visit.wav',
      participantCount: 2,
    );

  void answerRequired(ProviderContainer container) {
    container.read(reviewControllerProvider.notifier)
      ..setSatisfaction(4)
      ..setReaction(CareRecipientReaction.calm);
  }

  test('이 회차가 고른 카드와 기기에 남긴 녹음을 찾는다', () async {
    final container = makeContainer(
      api: FakeVisitApi(),
      uploads: withPending(),
    );

    final target = await container.read(
      reviewTargetProvider(_sessionId).future,
    );

    expect(target?.sessionId, _sessionId);
    expect(target?.cards.map((c) => c.cardId), [
      'card_demo_001',
      'card_demo_004',
      'card_demo_007',
      'card_demo_010',
    ]);
    expect(target?.audioPath, '/synthetic/visit.wav');
    expect(target?.participantCount, 2);
  });

  test('평가와 녹음을 그 회차로 보낸다', () async {
    final api = FakeVisitApi();
    final uploads = withPending();
    final container = makeContainer(api: api, uploads: uploads);
    answerRequired(container);

    final sent = await container
        .read(submissionProvider.notifier)
        .submit(resumeSessionId: _sessionId);

    expect(sent, isTrue);
    expect(api.evaluated?.sessionId, _sessionId);
    expect(api.audio?.sessionId, _sessionId);
    expect(api.audio?.audioPath, '/synthetic/visit.wav');
    expect(uploads.saved, isEmpty);
  });

  test('녹음 기록이 없으면 평가만 저장하고 녹음이 없다고 한다', () async {
    final api = FakeVisitApi();
    final container = makeContainer(api: api, uploads: FakePendingUploads());
    answerRequired(container);

    final sent = await container
        .read(submissionProvider.notifier)
        .submit(resumeSessionId: _sessionId);

    expect(sent, isFalse);
    expect(api.evaluated?.sessionId, _sessionId);
    expect(api.calls, isNot(contains('audio')));
    expect(
      container.read(submissionProvider).failure,
      SubmissionFailure.noRecording,
    );
  });

  testWidgets('녹음이 없으면 다시 누르게 하지 않고 리포트를 만들 수 없다고 한다', (tester) async {
    final container = makeContainer(
      api: FakeVisitApi(),
      uploads: FakePendingUploads(),
    );
    answerRequired(container);
    await tester.runAsync(
      () => container
          .read(submissionProvider.notifier)
          .submit(resumeSessionId: _sessionId),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ReviewScreen(sessionId: _sessionId)),
      ),
    );
    await tester.pump();

    expect(find.text(noRecordingTitle), findsOneWidget);
    expect(find.text(noRecordingBody), findsOneWidget);
    expect(find.text('리포트 만들기'), findsNothing);
  });

  test('묶음을 다른 회차가 쓰면 이어서 할 수 없다', () async {
    final api = FakeVisitApi();
    final container = makeContainer(api: api, uploads: withPending());
    answerRequired(container);

    expect(
      await container.read(reviewTargetProvider('session_other').future),
      isNull,
    );
    expect(
      await container
          .read(submissionProvider.notifier)
          .submit(resumeSessionId: 'session_other'),
      isFalse,
    );
    expect(api.calls, isEmpty);
    expect(
      container.read(submissionProvider).failure,
      SubmissionFailure.noSession,
    );
  });

  test('쓸 묶음이 없으면 이어서 할 수 없다', () async {
    final container = ProviderContainer(
      overrides: [
        withSampleProfile,
        cardApiProvider.overrideWithValue(_NoCardSetApi()),
        pendingUploadsProvider.overrideWithValue(withPending()),
      ],
    );
    addTearDown(container.dispose);

    expect(
      await container.read(reviewTargetProvider(_sessionId).future),
      isNull,
    );
  });
}

/// 쓸 묶음이 없다고 거절한다(API 4-3 `CARD_GENERATION_NOT_FOUND`).
class _NoCardSetApi extends FakeCardApi {
  @override
  Future<CardSet> current(String profileId) async =>
      throw const ApiServerFailure(
        statusCode: 404,
        errorCode: 'CARD_GENERATION_NOT_FOUND',
      );
}
