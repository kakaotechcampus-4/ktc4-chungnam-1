// `lib/data/models.dart` 가 잘못된 입력을 다루는 방식을 고정한다.
//
// 이 PR 의 결정은 "계약에 없는 값을 정상 값으로 바꾸지 않는다" 이다. enum 파싱에
// `orElse` 를 붙이면 한 줄로 되돌아가는 결정이라 회귀 테스트로 묶어 둔다.
//
// 네 가지를 구분한다.
//   - 지원하지 않는 값: 계약에 없는 문자열이 들어온 경우
//   - 누락: 키 자체가 없는 경우
//   - null: 키는 있고 값이 `null` 인 경우
//   - 사용자가 고른 `unknown`: 계약에 있는 정상 값
//
// 화면이 이 값을 어떻게 보여주는지는 여기서 다루지 않는다.

import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/models.dart';

void main() {
  // 계약에 없는 값으로 쓸 입력들이다. 그럴듯한 오타, 빈 문자열, 대소문자가
  // 다른 값을 함께 넣는다. 마지막 둘은 `name` 비교가 느슨해지면 통과한다.
  const unsupported = ['severe', '', 'PENDING', 'pending ', '알 수 없음'];

  group('지원하지 않는 값은 null 이 된다', () {
    // enum 마다 parse 를 한 번씩 부른다. 하나라도 기본값으로 되돌아가면 깨진다.
    final parsers = <String, Object? Function(String)>{
      'ConditionStage': ConditionStage.parse,
      'CollectionStatus': CollectionStatus.parse,
      'TagReviewStatus': TagReviewStatus.parse,
      'ChangeReviewStatus': ChangeReviewStatus.parse,
      'SessionStatus': SessionStatus.parse,
      'ReportStatus': ReportStatus.parse,
      'TopicAction': TopicAction.parse,
      'CareRecipientReaction': CareRecipientReaction.parse,
      'CaregiverReaction': CaregiverReaction.parse,
      'VisitMood': VisitMood.parse,
    };

    for (final entry in parsers.entries) {
      test(entry.key, () {
        for (final raw in unsupported) {
          expect(
            entry.value(raw),
            isNull,
            reason: '${entry.key}.parse("$raw") 가 값을 돌려주면 안 된다',
          );
        }
      });
    }

    test('파싱하는 enum 을 빠뜨리지 않았다', () {
      // 새 enum 을 만들고 위 표에 넣지 않으면 이 단언이 먼저 깨진다.
      expect(parsers, hasLength(10));
    });
  });

  group('사용자가 고른 unknown 은 그대로 남는다', () {
    // "잘 모르겠어요" 는 보호자가 직접 고른 답이다. 앱이 읽지 못한 값을 이것으로
    // 바꾸면 둘을 화면에서 구분할 수 없다.
    test('ConditionStage', () {
      expect(ConditionStage.parse('unknown'), ConditionStage.unknown);
      expect(ConditionStage.unknown.label, '잘 모르겠어요');
    });

    test('CareRecipientReaction', () {
      expect(
        CareRecipientReaction.parse('unknown'),
        CareRecipientReaction.unknown,
      );
      expect(CareRecipientReaction.unknown.label, '잘 모르겠어요');
    });

    test('unknown 이 있는 enum 은 이 둘뿐이다', () {
      // 계약에 "모르겠다" 가 없는 enum 에 unknown 을 새로 만들면, 답하지 않은
      // 것과 답을 읽지 못한 것이 다시 섞인다.
      expect(
        CaregiverReaction.values.map((v) => v.name),
        isNot(contains('unknown')),
      );
      expect(VisitMood.values.map((v) => v.name), isNot(contains('unknown')));
      expect(
        CollectionStatus.values.map((v) => v.name),
        isNot(contains('unknown')),
      );
    });
  });

  group('검토 상태는 계약의 값만 읽는다', () {
    // 승인한 제안을 되돌리는 기능이 계약에서 빠졌다. reverted 를 다시 읽으면
    // 계약에 없는 상태가 화면까지 흘러간다.
    test('ChangeReviewStatus 는 reverted 를 읽지 않는다', () {
      expect(ChangeReviewStatus.parse('reverted'), isNull);
    });

    test('두 타입의 값 목록이 계약과 같다', () {
      const contract = ['pending', 'accepted', 'rejected'];
      expect(TagReviewStatus.values.map((v) => v.name), contract);
      expect(ChangeReviewStatus.values.map((v) => v.name), contract);
    });

    test('주제 행동의 값 목록이 계약과 같다', () {
      expect(TopicAction.values.map((v) => v.name), [
        'more',
        'less',
        'exclude',
      ]);
    });
  });

  group('누락과 null 은 파싱을 멈춘다', () {
    // 계약이 필수라고 적은 값은 없으면 객체를 만들 수 없다. 빈 문자열이나
    // 기본값으로 채우면 어디서 잘못됐는지 모르는 채로 화면까지 흘러간다.
    Map<String, dynamic> candidate() => {
      'candidateId': 'candidate_001',
      'text': '바다',
      'reviewStatus': 'accepted',
    };

    test('갖춰진 입력은 읽힌다', () {
      final parsed = ImageTagCandidate.fromJson(candidate());

      expect(parsed.candidateId, 'candidate_001');
      expect(parsed.reviewStatus, TagReviewStatus.accepted);
    });

    test('필수 문자열이 빠지면 던진다', () {
      final json = candidate()..remove('candidateId');

      expect(() => ImageTagCandidate.fromJson(json), throwsA(isA<TypeError>()));
    });

    test('필수 문자열이 null 이면 던진다', () {
      final json = candidate()..['text'] = null;

      expect(() => ImageTagCandidate.fromJson(json), throwsA(isA<TypeError>()));
    });

    test('상태 문자열이 빠지면 null 이 아니라 던진다', () {
      // parse 가 null 을 주는 것은 "값은 왔는데 계약에 없을 때" 뿐이다.
      // 키가 아예 없는 것은 데이터가 깨진 경우라 구분해서 다룬다.
      final json = candidate()..remove('reviewStatus');

      expect(() => ImageTagCandidate.fromJson(json), throwsA(isA<TypeError>()));
    });

    test('상태 문자열이 null 이면 던진다', () {
      final json = candidate()..['reviewStatus'] = null;

      expect(() => ImageTagCandidate.fromJson(json), throwsA(isA<TypeError>()));
    });

    test('지원하지 않는 값은 던지지 않고 null 로 담긴다', () {
      // 앞의 네 경우와 달리 나머지 필드는 쓸 수 있다. 리포트 하나를 통째로
      // 못 여는 대신 그 값만 "확인 필요" 로 보여주기로 한 결정이다.
      final json = candidate()..['reviewStatus'] = 'reverted';
      final parsed = ImageTagCandidate.fromJson(json);

      expect(parsed.reviewStatus, isNull);
      expect(parsed.text, '바다');
    });

    test('없어도 되는 값은 null 로 담긴다', () {
      final proposal = TopicProposal.fromJson({
        'proposalId': 'topic_proposal_001',
        'cardId': 'card_001',
        'topic': {'topicId': 'topic_001', 'title': '고향'},
        'suggestedAction': 'more',
        'reason': '반응이 좋았다',
        'reviewStatus': 'pending',
      });

      // 주제 설명은 이 화면을 위해 더한 값이라 아직 오지 않을 수 있다.
      expect(proposal.topic.description, isNull);
      expect(proposal.suggestedAction, TopicAction.more);
    });

    test('주제 행동이 계약에 없으면 null 로 담긴다', () {
      final proposal = TopicProposal.fromJson({
        'proposalId': 'topic_proposal_002',
        'cardId': 'card_002',
        'topic': {'topicId': 'topic_002', 'title': '직업'},
        'suggestedAction': 'sideways',
        'reason': '확인이 필요하다',
        'reviewStatus': 'pending',
      });

      expect(proposal.suggestedAction, isNull);
      expect(proposal.topic.title, '직업');
    });
  });

  group('enum 이 아닌 상태 문자열은 아직 걸러지지 않는다', () {
    // 계약이 값을 정해 둔 자리인데 String 으로 남아 무엇이든 통과한다.
    // 변경 제안의 changeType 과 direction 은 계약에서 빠지고 TopicAction 으로
    // 바뀌었다. 아래 하나가 남았다. 범위 밖이라 현재 동작만 적어 둔다.
    test('sourceType 은 계약에 없는 값도 통과한다', () {
      final fact = LifeFact.fromJson({
        'factId': 'fact_001',
        'category': 'hobby',
        'text': '낚시를 좋아하셨다',
        'sourceType': 'importedFromSomewhere',
      });

      // 계약의 값은 caregiverVoiceInput, caregiverTextInput, visitConfirmed 다.
      expect(fact.sourceType, 'importedFromSomewhere');
    });
  });
}
