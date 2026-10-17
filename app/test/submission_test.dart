// 소감 화면의 `리포트 만들기` 가 서버에 남기는 순서를 확인한다.
//
// `lib/features/review/submission_controller.dart`. 서버 대신 `FakeVisitApi`
// 를 쓰고 값은 모두 합성이다.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/features/cards/cards_controller.dart';
import 'package:saerok/data/api_client.dart';
import 'package:saerok/features/review/review_controller.dart';
import 'package:saerok/features/review/submission_controller.dart';
import 'package:saerok/features/visit/visit_controller.dart';
import 'package:saerok/features/visit/visit_recorder.dart';

import 'fake_card_api.dart';
import 'fake_pending_uploads.dart';
import 'fake_visit_api.dart';
import 'fake_visit_recorder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 카드 두 장을 고르고 소감 앞까지 온 상태를 만든다.
  Future<ProviderContainer> afterVisit(
    FakeVisitApi api, {
    bool startRecording = true,
    int? participantCount = 2,
    FakePendingUploads? files,
  }) async {
    final container = ProviderContainer(
      overrides: [
        visitRecorderProvider.overrideWithValue(FakeVisitRecorder()),
        ...mockCardsWith(visitApi: api, pendingUploads: files),
      ],
    );
    addTearDown(container.dispose);

    final cards = await container.read(cardsControllerProvider.future);
    for (final card in cards.cards.take(2)) {
      container
          .read(cardsControllerProvider.notifier)
          .toggleSelected(card.cardId);
    }
    await container.read(visitControllerProvider.future);
    final visit = container.read(visitControllerProvider.notifier);
    if (startRecording) {
      await visit.startRecording();
      await visit.stopRecording(participantCount: participantCount);
    }

    final review = container.read(reviewControllerProvider.notifier);
    review.setSatisfaction(4);
    review.setReaction(CareRecipientReaction.pleased);
    return container;
  }

  test('회차에 평가를 저장한다', () async {
    final api = FakeVisitApi();
    final container = await afterVisit(api);
    final cards = container.read(visitControllerProvider).value!.cards;
    container
        .read(reviewControllerProvider.notifier)
        .setCardReaction(cards.first.cardId, CaregiverReaction.positive);

    final sent = await container.read(submissionProvider.notifier).submit();

    expect(sent, isTrue);
    expect(api.evaluated?.sessionId, FakeVisitApi.sessionId);
    final body = api.evaluated!.evaluation.toJson();
    expect(body, {
      'conversationSatisfaction': 4,
      'careRecipientReaction': 'pleased',
      'cardReviews': [
        {
          'cardId': cards.first.cardId,
          'wasUsed': true,
          'caregiverReaction': 'positive',
        },
      ],
      'freeNote': null,
    });
    final state = container.read(submissionProvider);
    expect(state.evaluationSaved, isTrue);
    expect(state.failure, isNull);
  });

  test('쓰지 않은 카드는 평가 없이 보낸다', () async {
    final api = FakeVisitApi();
    final container = await afterVisit(api);
    final cards = container.read(visitControllerProvider).value!.cards;
    container
        .read(reviewControllerProvider.notifier)
        .setCardNotUsed(cards.first.cardId);

    await container.read(submissionProvider.notifier).submit();

    expect(api.evaluated!.evaluation.toJson()['cardReviews'], [
      {
        'cardId': cards.first.cardId,
        'wasUsed': false,
        'caregiverReaction': null,
      },
    ]);
  });

  test('보내지 못하면 실패를 남기고 다시 누르면 다시 보낸다', () async {
    final api = FakeVisitApi(failEvaluation: true);
    final container = await afterVisit(api);
    final controller = container.read(submissionProvider.notifier);

    expect(await controller.submit(), isFalse);
    var state = container.read(submissionProvider);
    expect(state.failure, SubmissionFailure.network);
    expect(state.evaluationSaved, isFalse);
    expect(state.sending, isFalse);

    api.failEvaluation = false;
    expect(await controller.submit(), isTrue);
    state = container.read(submissionProvider);
    expect(state.evaluationSaved, isTrue);
    expect(state.failure, isNull);
  });

  test('저장한 평가는 다시 보내지 않는다', () async {
    final api = FakeVisitApi();
    final container = await afterVisit(api);
    final controller = container.read(submissionProvider.notifier);

    await controller.submit();
    await controller.submit();

    expect(api.calls.where((c) => c == 'evaluation'), hasLength(1));
  });

  test('서버에 회차가 없으면 보내지 않는다', () async {
    final api = FakeVisitApi();
    final container = await afterVisit(api, startRecording: false);

    final sent = await container.read(submissionProvider.notifier).submit();

    expect(sent, isFalse);
    expect(api.calls, isEmpty);
    expect(
      container.read(submissionProvider).failure,
      SubmissionFailure.noSession,
    );
  });

  group('녹음 제출', () {
    test('평가를 저장한 뒤 녹음과 참여자 수를 보내고 파일은 남긴다', () async {
      final api = FakeVisitApi();
      final files = FakePendingUploads();
      final container = await afterVisit(api, files: files);
      final path = container.read(visitControllerProvider).value!.recordingPath;

      final sent = await container.read(submissionProvider.notifier).submit();

      expect(sent, isTrue);
      expect(api.calls, containsAllInOrder(['evaluation', 'audio']));
      expect(api.audio?.sessionId, FakeVisitApi.sessionId);
      expect(api.audio?.audioPath, path);
      expect(api.audio?.participantCount, 2);
      expect(files.uploaded[FakeVisitApi.sessionId]?.audioPath, path);
      expect(files.removedPaths, isEmpty, reason: '서버가 받아도 원본은 남긴다');
      expect(
        container.read(submissionProvider).analysisId,
        FakeVisitApi.analysisId,
      );
    });

    test('녹음만 실패하면 다시 누를 때 녹음만 보낸다', () async {
      final api = FakeVisitApi(audioFailure: const ApiNetworkFailure());
      final files = FakePendingUploads();
      final container = await afterVisit(api, files: files);
      final controller = container.read(submissionProvider.notifier);

      expect(await controller.submit(), isFalse);
      var state = container.read(submissionProvider);
      expect(state.evaluationSaved, isTrue);
      expect(state.failure, SubmissionFailure.network);
      expect(files.uploaded, isEmpty, reason: '다시 보낼 목록에 남긴다');

      api.audioFailure = null;
      expect(await controller.submit(), isTrue);
      expect(api.calls.where((c) => c == 'evaluation'), hasLength(1));
      expect(api.calls.where((c) => c == 'audio'), hasLength(2));
      expect(files.uploaded, hasLength(1));
      expect(files.removedPaths, isEmpty);
    });

    test('이미 끝난 회차라고 거절되면 분석 작업 없이 마치고 파일은 남긴다', () async {
      final api = FakeVisitApi(
        audioFailure: const ApiServerFailure(
          statusCode: 409,
          errorCode: 'ANALYSIS_ALREADY_COMPLETED',
        ),
      );
      final files = FakePendingUploads();
      final container = await afterVisit(api, files: files);

      expect(
        await container.read(submissionProvider.notifier).submit(),
        isTrue,
      );
      expect(container.read(submissionProvider).analysisId, isNull);
      expect(files.uploaded, hasLength(1));
      expect(files.removedPaths, isEmpty);
    });

    test('참여자 수를 확인받지 않았으면 녹음을 보내지 않는다', () async {
      final api = FakeVisitApi();
      final container = await afterVisit(api, participantCount: null);

      expect(
        await container.read(submissionProvider.notifier).submit(),
        isFalse,
      );
      expect(api.calls, isNot(contains('audio')));
      final state = container.read(submissionProvider);
      expect(state.failure, SubmissionFailure.noRecording);
      expect(state.evaluationSaved, isTrue, reason: '평가는 먼저 저장한다');
    });
  });

  group('기기에 남기는 녹음 기록', () {
    test('녹음을 끝내면 회차 ID 로 적고, 서버가 받으면 보냈다고만 적는다', () async {
      final api = FakeVisitApi();
      final files = FakePendingUploads();
      final container = await afterVisit(api, files: files);
      final visit = container.read(visitControllerProvider).value!;

      final saved = files.saved[FakeVisitApi.sessionId];
      expect(saved?.audioPath, visit.recordingPath);
      expect(saved?.participantCount, 2);

      await container.read(submissionProvider.notifier).submit();

      expect(files.saved, isEmpty, reason: '다시 보낼 목록에서 뺀다');
      final uploaded = files.uploaded[FakeVisitApi.sessionId];
      expect(uploaded?.audioPath, visit.recordingPath);
      expect(uploaded?.participantCount, 2);
      expect(files.removedPaths, isEmpty);
    });

    test('녹음을 보내지 못하면 기록을 남긴다', () async {
      final api = FakeVisitApi(audioFailure: const ApiNetworkFailure());
      final files = FakePendingUploads();
      final container = await afterVisit(api, files: files);

      await container.read(submissionProvider.notifier).submit();

      expect(files.saved, contains(FakeVisitApi.sessionId));
    });

    test('참여자 수를 확인받지 않았으면 적지 않는다', () async {
      final files = FakePendingUploads();
      await afterVisit(FakeVisitApi(), files: files, participantCount: null);

      expect(files.saved, isEmpty);
    });
  });
}
