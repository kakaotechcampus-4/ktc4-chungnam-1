/// 리포트 본문을 화면에 나눠 그리기 위한 도구다.
library;

/// 문장이 끝나고 다음 문장이 시작하는 자리. 마침표 뒤에 공백이 있어야 한다.
///
/// 공백을 함께 보기 때문에 `3.5년` 이나 `오전 9.30` 처럼 마침표 뒤가 붙어 있는
/// 경우에는 나누지 않는다.
final _sentenceBreak = RegExp(r'(?<=[.!?])\s+');

/// 리포트 요약을 문장 단위 문단으로 나눈다.
///
/// 계약의 `VisitReport.summaryText` 는 문장 여럿을 한 덩어리로 담는다. 그대로
/// 한 문단으로 그리면 어디까지 읽었는지 놓치기 쉽다. 이 요약은 사실 대화 주제를
/// 하나씩 적은 목록이라, 문장에서 나누는 것은 없던 구조를 만드는 것이 아니라
/// 원래 구조를 드러내는 것이다.
///
/// **글자는 하나도 바꾸지 않는다.** 나누기만 하고 다듬거나 줄이지 않는다. AI 가
/// 쓴 글을 FE 가 고쳐 쓰지 않는다(`CLAUDE.md`). 문장 사이의 공백만 문단 간격이
/// 되어 사라진다.
///
/// 나누기는 어디까지나 추측이다. 문장이 하나로만 보이면 원문을 그대로 돌려준다.
/// 계약이 문단 배열을 담게 되면 이 함수는 사라진다.
List<String> splitIntoParagraphs(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const [];

  final pieces = trimmed
      .split(_sentenceBreak)
      .map((piece) => piece.trim())
      .where((piece) => piece.isNotEmpty)
      .toList();

  // 나눌 자리를 찾지 못하면 손대지 않는다.
  if (pieces.length < 2) return [trimmed];

  return pieces;
}
