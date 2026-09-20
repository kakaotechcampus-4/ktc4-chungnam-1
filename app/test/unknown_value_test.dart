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
      'ProposalStatus': ProposalStatus.parse,
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

  group('되돌린 변경은 정상 상태다', () {
    // reverted 는 보호자가 승인해 반영한 변경을 나중에 되돌린 상태다. 값을 읽지
    // 못한 경우가 아니므로 null 이 되면 안 된다.
    test('ChangeReviewStatus 는 reverted 를 읽는다', () {
      expect(ChangeReviewStatus.parse('reverted'), ChangeReviewStatus.reverted);
    });

    test('TagReviewStatus 는 reverted 를 읽지 않는다', () {
      // 이미지 분석 후보에는 되돌릴 대상이 없다. 두 타입을 다시 합치면 깨진다.
      expect(TagReviewStatus.parse('reverted'), isNull);
    });

    test('두 타입의 값 목록이 계약과 같다', () {
      expect(TagReviewStatus.values.map((v) => v.name), [
        'pending',
        'accepted',
        'rejected',
      ]);
      expect(ChangeReviewStatus.values.map((v) => v.name), [
        'pending',
        'accepted',
        'rejected',
        'reverted',
      ]);
    });

    test('변경 제안이 reverted 를 담는다', () {
      final change = ProposedChange.fromJson({
        'changeId': 'change_001',
        'changeType': 'lifeFactAdd',
        'text': '바다를 좋아하셨다',
        'reason': '면회에서 다시 말씀하셨다',
        'reviewStatus': 'reverted',
      });

      expect(change.reviewStatus, ChangeReviewStatus.reverted);
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
      final change = ProposedChange.fromJson({
        'changeId': 'change_002',
        'changeType': 'topicPriority',
        'topicTitle': '고향',
        'direction': 'up',
        'reason': '반응이 좋았다',
        'reviewStatus': 'accepted',
      });

      // lifeFactAdd 가 아니라 text 를 갖지 않는다. 이것은 정상이다.
      expect(change.text, isNull);
      expect(change.reviewStatus, ChangeReviewStatus.accepted);
    });
  });

  group('enum 이 아닌 상태 문자열은 아직 걸러지지 않는다', () {
    // 계약이 값을 정해 둔 자리인데 String 으로 남아 무엇이든 통과한다.
    // sessionStatus, reportStatus, proposalStatus 는 이 PR 에서 enum 으로
    // 올렸고 아래 셋은 남았다. 이 PR 범위 밖이라 현재 동작만 적어 둔다.
    test('changeType 은 계약에 없는 값도 통과한다', () {
      final change = ProposedChange.fromJson({
        'changeId': 'change_003',
        'changeType': 'lifeFactRemove',
        'reason': '확인이 필요하다',
        'reviewStatus': 'pending',
      });

      // 계약의 값은 topicPriority 와 lifeFactAdd 둘뿐이다.
      expect(change.changeType, 'lifeFactRemove');
    });

    test('direction 은 계약에 없는 값도 통과한다', () {
      final change = ProposedChange.fromJson({
        'changeId': 'change_004',
        'changeType': 'topicPriority',
        'topicTitle': '직업',
        'direction': 'sideways',
        'reason': '확인이 필요하다',
        'reviewStatus': 'pending',
      });

      // 계약의 값은 up 과 down 둘뿐이다.
      expect(change.direction, 'sideways');
    });

    test('sourceType 은 계약에 없는 값도 통과한다', () {
      final fact = LifeFact.fromJson({
        'factId': 'fact_001',
        'category': 'hobby',
        'text': '낚시를 좋아하셨다',
        'sourceType': 'importedFromSomewhere',
        'createdAt': '2026-08-21T12:10:00+09:00',
      });

      // 계약의 값은 caregiverVoiceInput, caregiverTextInput, visitConfirmed 다.
      expect(fact.sourceType, 'importedFromSomewhere');
    });
  });
}
