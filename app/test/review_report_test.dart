// F, G 화면(보호자 소감과 리포트, 변경 사항 확인)의 규칙을 확인한다.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/mock_repository.dart';
import 'package:saerok/data/models.dart';
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
      expect(
        CareRecipientReaction.values.map((v) => v.name),
        ['pleased', 'calm', 'angry', 'lowEnergy', 'unknown'],
      );
      expect(
        CaregiverReaction.values.map((v) => v.name),
        ['positive', 'neutral', 'negative'],
      );
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

    test('고르지 않은 카드는 다루지 않은 것으로 기록한다', () async {
      final container = makeContainer();
      final controller = container.read(reviewControllerProvider.notifier);
      final cards = await const MockRepository().loadConversationCards();
      final three = cards.take(3).toList();

      controller.setSatisfaction(4);
      controller.setReaction(CareRecipientReaction.pleased);
      controller.setCardReaction(three.first.cardId, CaregiverReaction.positive);

      final evaluation = controller.toEvaluation(
        reviewId: 'review_demo_001',
        sessionId: 'session_demo_001',
        cards: three,
      )!;

      expect(evaluation.cardReviews, hasLength(3));
      expect(evaluation.cardReviews.first.wasUsed, isTrue);
      expect(
        evaluation.cardReviews.first.caregiverReaction,
        CaregiverReaction.positive,
      );
      expect(evaluation.cardReviews.last.wasUsed, isFalse);
      expect(
        evaluation.cardReviews.last.caregiverReaction,
        CaregiverReaction.neutral,
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
}
