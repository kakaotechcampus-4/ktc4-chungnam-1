// 목 데이터가 계약대로 읽히는지 확인한다.
//
// `mock_data_sync_test.dart` 가 원본과 사본이 같은지 보는 반면, 이 파일은
// 그 데이터가 `lib/data/models.dart` 로 문제없이 읽히는지 본다. 계약이 바뀌면
// 둘 중 하나가 먼저 깨진다.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/card_api.dart';
import 'package:saerok/data/mock_repository.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/providers.dart';

import 'fake_card_api.dart';
import 'sample_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const repository = MockRepository();

  test('계정을 읽는다', () async {
    final account = await repository.loadAccount();

    expect(account.accountId, 'account_demo_001');
    // 알림 수신은 선택 동의다. 이 목 데이터는 수락한 계정을 담는다.
    expect(account.consent['pushNotification']?.granted, isTrue);
    expect(account.consent['serviceData']?.granted, isTrue);
  });

  test('목 사진이 가리키는 앱 그림이 모두 있다', () async {
    // 그림 파일 이름이 바뀌면 갤러리에 깨진 그림이 뜬다. 화면을 띄우지 않고 여기서 잡는다.
    final bundle = await repository.loadProfile();
    const scheme = 'asset:';
    final assets = [
      for (final photo in bundle.photos)
        if (photo.imageUrl.startsWith(scheme))
          photo.imageUrl.substring(scheme.length),
    ];

    expect(assets, hasLength(bundle.photos.length));
    for (final path in assets) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
  });

  test('프로필을 읽는다', () async {
    final bundle = await repository.loadProfile();

    expect(bundle.profile.stage, ConditionStage.mildCognitiveImpairment);
    expect(bundle.lifeFacts, hasLength(3));
    // 사진은 분석 완료, 분석 중, 실패를 한 장씩 담는다.
    expect(bundle.photos.map((p) => p.analysisStatus), [
      PhotoAnalysisStatus.completed,
      PhotoAnalysisStatus.processing,
      PhotoAnalysisStatus.failed,
    ]);
    // 설명은 분석이 끝난 사진에만 있다.
    expect(bundle.photos.map((p) => p.description != null), [
      isTrue,
      isFalse,
      isFalse,
    ]);
    expect(bundle.photos.last.errorCode, 'AI_SERVER_ERROR');
    expect(
      bundle.profile.photoIds,
      bundle.photos.map((p) => p.photoId),
      reason: '프로필이 가리키는 사진과 사진 목록이 같아야 한다',
    );
  });

  test('대화 카드 묶음 12장을 순서대로 읽는다', () async {
    final set = await repository.loadCardSet();
    final cards = set.cards;

    expect(cards, hasLength(12));
    // 1~9 가 선택 화면, 10~12 가 면회 중 보충용이다.
    expect(cards.map((c) => c.position), List.generate(12, (i) => i + 1));
    expect(
      cards.map((c) => c.topic.topicId).toSet(),
      hasLength(12),
      reason: '한 묶음 안에서 같은 주제는 두 번 나오지 않는다',
    );
    for (final card in cards) {
      expect(card.followUpQuestions, hasLength(3));
      expect(card.topic.description, isNotEmpty);
      expect(card.description, isNotEmpty);
      expect(
        card.evidence,
        card.evidenceSource == 'none' ? isEmpty : isNotEmpty,
        reason: 'none 이면 근거가 비고, 나머지는 하나 이상이다',
      );
    }
  });

  test('카드 묶음은 position 으로 줄 세운다', () {
    Map<String, dynamic> card(String id, int position) => {
      'cardId': id,
      'position': position,
      'topic': {'topicId': 't$id', 'title': '주제', 'description': '설명'},
      'cardTitle': '카드',
      'description': '설명',
      'primaryQuestion': '질문',
      'followUpQuestions': ['하나', '둘', '셋'],
      'evidenceSource': 'none',
      'evidence': <Object>[],
      'selected': false,
    };

    final set = CardSet.fromJson({
      'setId': 's1',
      'usedBySessionId': null,
      'cards': [card('b', 2), card('c', 3), card('a', 1)],
    });

    expect(set.cards.map((c) => c.cardId), ['a', 'b', 'c']);
    expect(set.usedBySessionId, isNull);
  });

  test('목 묶음의 고른 카드는 회차의 선택과 같다', () async {
    final set = await repository.loadCardSet();
    final session = await repository.loadVisitSession();

    expect(
      set.cards.where((c) => c.selected).map((c) => c.cardId),
      session.selectedCardIds,
    );
    expect(set.usedBySessionId, session.sessionId);
    expect(session.setId, set.setId, reason: '회차는 그 묶음으로 만들었다');
  });

  test('면회 회차와 리포트를 읽는다', () async {
    final session = await repository.loadVisitSession();
    final report = await repository.loadVisitReport();

    expect(session.selectedCardIds, hasLength(4));
    // 리포트까지 저장한 회차라 음성 분석 작업도 있다.
    expect(session.sessionStatus, SessionStatus.completed);
    expect(session.analysisId, isNotNull);
    expect(report.sessionId, session.sessionId);
    expect(report.cardSummaries, hasLength(4));
  });

  test('보호자 평가와 변경 제안을 읽는다', () async {
    final evaluation = await repository.loadCaregiverEvaluation();
    final proposal = await repository.loadChangeProposal();

    // 리포트에는 카드 넷이 오는데 평가는 셋이다. 답하지 않고 넘어간 카드는
    // 목록에 담지 않는다. 그것이 미응답이다.
    expect(evaluation.cardReviews.map((r) => r.cardId), [
      'card_demo_001',
      'card_demo_004',
      'card_demo_010',
    ]);
    expect(
      evaluation.cardReviews.last.wasUsed,
      isFalse,
      reason: '명절 음식은 쓰지 않았다고 답한 카드다',
    );
    expect(evaluation.cardReviews.last.caregiverReaction, isNull);
    // 변경 사항 확인 화면이 읽는 7-3 응답이라 모두 확인 전이다.
    expect(proposal.sessionId, 'session_demo_001');
    expect(proposal.topicProposals, isNotEmpty);
    expect(proposal.lifeFactProposals, isNotEmpty);
    expect([
      ...proposal.topicProposals.map((p) => p.reviewStatus),
      ...proposal.lifeFactProposals.map((p) => p.reviewStatus),
    ], everyElement(ChangeReviewStatus.pending));
  });

  test('provider 를 갈아끼우면 화면이 보는 값이 바뀐다', () async {
    final container = ProviderContainer(
      overrides: [
        withSampleProfile,
        cardApiProvider.overrideWithValue(_EmptyCardApi()),
      ],
    );
    addTearDown(container.dispose);

    final cards = await container.read(conversationCardsProvider.future);

    expect(cards, isEmpty, reason: '카드는 목 데이터가 아니라 카드 API 에서 온다');
  });
}

/// 데이터 출처를 바꿀 수 있는지 보기 위한 대역이다. 카드는 서버 API 자리를
/// 갈아끼운다.
class _EmptyCardApi extends FakeCardApi {
  @override
  Future<CardSet> current(String profileId) async =>
      const CardSet(setId: 'empty', usedBySessionId: null, cards: []);
}
