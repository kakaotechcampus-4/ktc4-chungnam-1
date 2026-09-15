// F, G 화면(보호자 소감과 리포트, 변경 사항 확인)의 규칙을 확인한다.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/mock_repository.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/features/review/review_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer makeContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  group('보호자 평가', () {
    test('계약의 enum 값을 그대로 쓴다', () {
      expect(CareRecipientReaction.values.map((v) => v.name), [
        'pleased',
        'calm',
        'angry',
        'lowEnergy',
        'unknown',
      ]);
      expect(CaregiverReaction.values.map((v) => v.name), [
        'positive',
        'neutral',
        'negative',
      ]);
      expect(VisitMood.values.map((v) => v.name), ['hard', 'normal', 'good']);
    });

    test('보호자 감정은 대화 만족도에서 계산한다', () {
      // 1이면 hard, 2~4는 normal, 5면 good 이다.
      expect(VisitMood.fromSatisfaction(1), VisitMood.hard);
      expect(VisitMood.fromSatisfaction(2), VisitMood.normal);
      expect(VisitMood.fromSatisfaction(4), VisitMood.normal);
      expect(VisitMood.fromSatisfaction(5), VisitMood.good);
    });

    test('앞의 두 물음에 답해야 제출할 수 있다', () {
      final container = makeContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      expect(container.read(reviewControllerProvider).canSubmit, isFalse);

      controller.setSatisfaction(4);
      expect(container.read(reviewControllerProvider).canSubmit, isFalse);

      controller.setReaction(CareRecipientReaction.pleased);
      final draft = container.read(reviewControllerProvider);
      expect(draft.canSubmit, isTrue);
      expect(draft.mood, VisitMood.normal);
    });

    test('미사용과 미응답을 갈라 기록한다', () async {
      final container = makeContainer();
      final controller = container.read(reviewControllerProvider.notifier);
      final cards = await const MockRepository().loadConversationCards();
      final three = cards.take(3).toList();

      controller.setSatisfaction(4);
      controller.setReaction(CareRecipientReaction.pleased);

      // 첫 장은 쓰고 평가했고, 둘째 장은 쓰지 않았다고 답했다.
      // 셋째 장은 답하지 않고 넘어갔다.
      controller.setCardReaction(
        three.first.cardId,
        CaregiverReaction.positive,
      );
      controller.setCardNotUsed(three[1].cardId);

      final evaluation = controller.toEvaluation(
        reviewId: 'review_demo_001',
        sessionId: 'session_demo_001',
        cards: three,
      )!;

      expect(
        evaluation.cardReviews.map((r) => r.cardId),
        [three.first.cardId, three[1].cardId],
        reason: '답하지 않은 카드는 담지 않는다. 담지 않는 것이 미응답이다',
      );

      final used = evaluation.cardReviews.first;
      expect(used.wasUsed, isTrue);
      expect(used.caregiverReaction, CaregiverReaction.positive);

      final notUsed = evaluation.cardReviews.last;
      expect(notUsed.wasUsed, isFalse);
      expect(
        notUsed.caregiverReaction,
        isNull,
        reason: '쓰지 않은 카드에 보호자가 하지 않은 평가를 대신 만들지 않는다',
      );
    });

    test('쓰지 않았다고 답한 뒤 다시 평가할 수 있다', () async {
      final container = makeContainer();
      final controller = container.read(reviewControllerProvider.notifier);
      final cards = await const MockRepository().loadConversationCards();
      final one = cards.take(1).toList();

      controller.setSatisfaction(4);
      controller.setReaction(CareRecipientReaction.pleased);
      controller.setCardNotUsed(one.first.cardId);
      controller.setCardReaction(one.first.cardId, CaregiverReaction.negative);

      final evaluation = controller.toEvaluation(
        reviewId: 'review_demo_001',
        sessionId: 'session_demo_001',
        cards: one,
      )!;

      expect(evaluation.cardReviews.single.wasUsed, isTrue);
      expect(
        evaluation.cardReviews.single.caregiverReaction,
        CaregiverReaction.negative,
      );
    });

    test('남길 말이 비면 담지 않는다', () {
      final container = makeContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      controller.setSatisfaction(3);
      controller.setReaction(CareRecipientReaction.calm);
      controller.setFreeNote('   ');

      final evaluation = controller.toEvaluation(
        reviewId: 'r',
        sessionId: 's',
        cards: const [],
      )!;

      expect(evaluation.freeNote, isNull);
    });

    test('새 회차를 시작하면 지난 소감이 남지 않는다', () {
      final container = makeContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      controller.setSatisfaction(5);
      controller.setReaction(CareRecipientReaction.pleased);
      controller.setFreeNote('지난 회차 소감');
      expect(container.read(reviewControllerProvider).canSubmit, isTrue);

      // 대화 시작하기를 누를 때 화면이 하는 일과 같다.
      container.invalidate(reviewControllerProvider);
      final fresh = container.read(reviewControllerProvider);

      expect(fresh.satisfaction, isNull);
      expect(fresh.reaction, isNull);
      expect(fresh.freeNote, isEmpty);
      expect(fresh.canSubmit, isFalse);
    });

    test('답하지 않으면 계약 객체를 만들지 않는다', () {
      final container = makeContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      expect(
        controller.toEvaluation(reviewId: 'r', sessionId: 's', cards: const []),
        isNull,
      );
    });
  });

  group('리포트', () {
    test('목 데이터의 감정과 만족도가 계약 규칙과 맞는다', () async {
      const repository = MockRepository();
      final report = await repository.loadVisitReport();
      final evaluation = await repository.loadCaregiverEvaluation();

      expect(
        report.mood,
        VisitMood.fromSatisfaction(evaluation.conversationSatisfaction),
        reason: 'mood 는 conversationSatisfaction 에서 계산한다',
      );
    });

    test('변경 제안은 두 가지 타입만 쓴다', () async {
      final proposal = await const MockRepository().loadChangeProposal();

      for (final change in proposal.changes) {
        expect(
          change.changeType,
          anyOf('topicPriority', 'lifeFactAdd'),
          reason: change.changeId,
        );
        if (change.changeType == 'topicPriority') {
          expect(change.direction, anyOf('up', 'down'));
          expect(change.topicTitle, isNotNull);
          expect(change.text, isNull, reason: 'topicPriority 는 text 를 갖지 않는다');
        } else {
          expect(change.text, isNotNull);
          expect(
            change.topicTitle,
            isNull,
            reason: 'lifeFactAdd 는 topicTitle 을 갖지 않는다',
          );
        }
      }
    });
  });

  /// 도착 시점을 테스트가 직접 정하는 저장소를 끼운 통을 만든다.
  (ProviderContainer, Completer<void>) makeWaitingContainer() {
    final ready = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        mockRepositoryProvider.overrideWithValue(_WaitingRepository(ready)),
      ],
    );
    addTearDown(container.dispose);
    return (container, ready);
  }

  group('리포트 알림', () {
    // 기다리는 화면을 없앴다. 소감을 제출하면 바로 홈으로 돌아가고, 만드는
    // 중과 도착을 모두 홈에서 알린다. 그래서 기다림은 화면이 아니라 알림
    // 상태가 센다.

    test('제출하면 곧바로 만드는 중이 되고 저장소가 알리면 도착으로 바뀐다', () async {
      final (container, ready) = makeWaitingContainer();

      expect(container.read(reportNoticeProvider), isNull);

      container.read(reportNoticeProvider.notifier).startGenerating();

      expect(
        container.read(reportNoticeProvider),
        ReportNotice.generating,
        reason: '홈에 돌아갔을 때 빈 화면이 아니라 만드는 중이 보여야 한다',
      );

      // 얼마나 걸리는지는 저장소가 정한다. 서버를 붙여도 이 자리만 바뀐다.
      ready.complete();
      await Future<void>.value();

      expect(container.read(reportNoticeProvider), ReportNotice.ready);
    });

    test('확인을 마치면 기다리던 결과도 버린다', () async {
      final (container, ready) = makeWaitingContainer();

      final notice = container.read(reportNoticeProvider.notifier);
      notice.startGenerating();
      notice.dismiss();

      ready.complete();
      await Future<void>.value();

      expect(
        container.read(reportNoticeProvider),
        isNull,
        reason: '지운 뒤에 지난 기다림이 살아나면 안 된다',
      );
    });
  });
}

/// 리포트 도착 시점을 테스트가 직접 정하는 저장소다.
class _WaitingRepository extends MockRepository {
  const _WaitingRepository(this._ready);

  final Completer<void> _ready;

  @override
  Future<void> awaitReportReady() => _ready.future;
}
