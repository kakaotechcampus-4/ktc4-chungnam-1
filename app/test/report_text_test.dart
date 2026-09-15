// 리포트 본문을 문단으로 나누는 규칙을 확인한다.
//
// 나누기는 추측이라 틀릴 여지가 있다. 어디서 나누고 어디서 나누지 않는지를
// 고정해 둔다.

import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/features/report/report_text.dart';

void main() {
  group('문단 나누기', () {
    test('목 데이터의 요약을 문장 여섯으로 나눈다', () {
      const summary =
          '오늘은 재봉 일을 하시던 시절 이야기로 문을 열었어요. '
          '동인천 수선집에서 한복을 만드시던 때를 떠올리시며 오래 말씀해주셨고, '
          '함께 일하던 분들 이야기가 나올 때는 표정이 밝아지셨어요. '
          '노래 이야기에서는 라디오에서 나훈아 노래가 나오면 따라 부르셨다며 웃으셨고요. '
          '학창 시절 이야기는 꺼내자마자 말수가 줄어드셔서 오래 이어가지 못했어요. '
          '명절 음식 이야기는 준비해뒀지만 시간이 모자라 다음으로 미뤘습니다. '
          '오늘은 대체로 이야기가 잘 풀린 날이었어요.';

      final paragraphs = splitIntoParagraphs(summary);

      expect(paragraphs, hasLength(6));
      expect(paragraphs.first, '오늘은 재봉 일을 하시던 시절 이야기로 문을 열었어요.');
      expect(paragraphs.last, '오늘은 대체로 이야기가 잘 풀린 날이었어요.');
    });

    test('글자를 바꾸지 않는다', () {
      const summary = '첫 문장이에요. 둘째 문장이에요. 셋째 문장이에요.';

      // 문단을 다시 이으면 원문이 된다. 문장 사이 공백만 간격이 된다.
      expect(splitIntoParagraphs(summary).join(' '), summary);
    });

    test('문장이 하나면 그대로 둔다', () {
      const summary = '오늘은 이야기가 잘 풀렸어요.';

      expect(splitIntoParagraphs(summary), [summary]);
    });

    test('마침표 뒤가 붙어 있으면 나누지 않는다', () {
      // 소수점과 시각 표기다. 문장 끝이 아니다.
      const summary = '3.5년 만에 뵈었어요. 오전 9.30 에 도착했습니다.';

      final paragraphs = splitIntoParagraphs(summary);

      expect(paragraphs, hasLength(2));
      expect(paragraphs.first, '3.5년 만에 뵈었어요.');
      expect(paragraphs.last, '오전 9.30 에 도착했습니다.');
    });

    test('물음표와 느낌표에서도 나눈다', () {
      final paragraphs = splitIntoParagraphs('그러셨어요? 정말 반가웠어요!');

      expect(paragraphs, ['그러셨어요?', '정말 반가웠어요!']);
    });

    test('줄바꿈으로 나뉜 글도 문단이 된다', () {
      final paragraphs = splitIntoParagraphs('첫 문장이에요.\n\n둘째 문장이에요.');

      expect(paragraphs, ['첫 문장이에요.', '둘째 문장이에요.']);
    });

    test('빈 글은 빈 목록이다', () {
      expect(splitIntoParagraphs(''), isEmpty);
      expect(splitIntoParagraphs('   '), isEmpty);
    });

    test('마침표가 없어도 글을 잃지 않는다', () {
      const summary = '마침표를 빠뜨린 요약';

      expect(splitIntoParagraphs(summary), [summary]);
    });
  });
}
