// 목 데이터가 계약대로 읽히는지 확인한다.
//
// `mock_data_sync_test.dart` 가 원본과 사본이 같은지 보는 반면, 이 파일은
// 그 데이터가 `lib/data/models.dart` 로 문제없이 읽히는지 본다. 계약이 바뀌면
// 둘 중 하나가 먼저 깨진다.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/mock_repository.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const repository = MockRepository();

  test('계정을 읽는다', () async {
    final account = await repository.loadAccount();

    expect(account.accountId, 'account_demo_001');
    // 알림 수신은 필수 동의로 올렸다. 목 데이터도 수락 상태여야 한다.
    expect(account.consent['pushNotification']?.granted, isTrue);
    expect(account.consent['serviceData']?.granted, isTrue);
  });

  test('프로필을 읽는다', () async {
    final bundle = await repository.loadProfile();

    expect(bundle.profile.stage, ConditionStage.mildCognitiveImpairment);
    expect(bundle.lifeFacts, hasLength(3));
    // accepted 된 후보만 acceptedTags 에 담긴다.
    final accepted = bundle.tagCandidates
        .where((c) => c.reviewStatus == ReviewStatus.accepted)
        .map((c) => c.text)
        .toList();
    expect(accepted, bundle.photo.acceptedTags);
  });

  test('대화 카드 12장을 읽는다', () async {
    final cards = await repository.loadConversationCards();

    expect(cards, hasLength(12));
    // 앞 9장이 선택 화면, 뒤 3장이 면회 중 보충용이다.
    expect(cards.take(9), hasLength(9));
    for (final card in cards) {
      expect(card.followUpQuestions, hasLength(3));
      expect(card.topicDescription, isNotEmpty);
    }
  });

  test('면회 회차와 리포트를 읽는다', () async {
    final session = await repository.loadVisitSession();
    final report = await repository.loadVisitReport();

    expect(session.selectedCardIds, hasLength(4));
    expect(report.sessionId, session.sessionId);
    expect(report.cardSummaries, hasLength(4));
  });

  test('보호자 평가와 변경 제안을 읽는다', () async {
    final evaluation = await repository.loadCaregiverEvaluation();
    final proposal = await repository.loadChangeProposal();

    expect(evaluation.cardReviews, hasLength(4));
    // 반영이 끝난 상태라 pending 이 남아 있지 않다.
    expect(proposal.proposalStatus, 'reviewed');
    expect(
      proposal.changes.where((c) => c.reviewStatus == ReviewStatus.pending),
      isEmpty,
    );
  });

  test('provider 를 갈아끼우면 화면이 보는 값이 바뀐다', () async {
    final container = ProviderContainer(
      overrides: [mockRepositoryProvider.overrideWithValue(_EmptyRepository())],
    );
    addTearDown(container.dispose);

    final cards = await container.read(conversationCardsProvider.future);

    expect(cards, isEmpty);
  });
}

/// 데이터 출처를 바꿀 수 있는지 보기 위한 대역이다. 나중에 서버 구현이 같은
/// 자리에 들어간다.
class _EmptyRepository extends MockRepository {
  const _EmptyRepository();

  @override
  Future<List<ConversationCard>> loadConversationCards() async => const [];
}
