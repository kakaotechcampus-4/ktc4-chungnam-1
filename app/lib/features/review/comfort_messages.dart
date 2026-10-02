/// 보호자 평가를 제출한 뒤 위로 화면에 띄우는 문구다.
///
/// 모두 고정 문구다. AI 가 만들지 않고, 어르신 상태를 해석하지 않는다.
/// 보호자가 고른 Q1 대화 만족도(1 이상 5 이하)만 보고 고른다.
library;

/// 점수와 관계없이 늘 보이는 문장이다.
const comfortFixedMessage = '오늘도 다녀오셨네요.\n그것만으로 충분히 잘하고 계세요.';

/// 점수에 따라 달라지는 문단이다.
class ComfortMessage {
  const ComfortMessage({required this.title, required this.body});

  final String title;
  final String body;
}

const _messages = <int, ComfortMessage>{
  1: ComfortMessage(
    title: '대화가 잘 안 풀린 날도 있어요.',
    body:
        '매일 완벽하게 이야기 나눌 수는 없으니까요. 남겨주신 기록을 바탕으로, '
        '다음 면회에는 더 편하게 꺼낼 수 있는 이야기를 준비해 둘게요.',
  ),
  2: ComfortMessage(
    title: '조금 아쉬운 마음이 남으셨군요.',
    body:
        '아쉬움이 남는 건 그만큼 마음을 쓰셨다는 뜻이에요. '
        '오늘 남겨주신 기록을 참고해 다음 카드를 다시 골라 둘게요.',
  ),
  3: ComfortMessage(
    title: '평소 같은 하루도 소중해요.',
    body:
        '특별한 일이 없어도 곁에서 보낸 시간은 그대로 남아요. '
        '다음 면회에도 편하게 나눌 이야기를 준비해 둘게요.',
  ),
  4: ComfortMessage(
    title: '좋은 시간을 보내셨네요.',
    body:
        '오늘 이야기가 잘 이어졌던 카드를 기억해 둘게요. '
        '다음 면회에서도 그 이야기를 이어갈 수 있어요.',
  ),
  5: ComfortMessage(
    title: '참 따뜻한 만남이었네요.',
    body:
        '오늘 나눈 이야기가 기록에 잘 남았어요. '
        '이 이야기를 더 이어갈 수 있는 카드를 다음 면회에 준비해 둘게요.',
  ),
};

/// 점수가 없거나 범위를 벗어나면 `null` 이다. 이때는 문단을 띄우지 않는다.
ComfortMessage? comfortMessageFor(int? satisfaction) => _messages[satisfaction];
