// 만남 끝내기 창과 녹음을 다시 보내기 전의 참여자 수 창이 같은 물음을 쓰는지
// 확인한다(2026-11-09 PM 결정). 기본값과 고르는 범위는 바꾸지 않는다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/visit/stop_recording_dialog.dart';

/// 버튼을 눌러 [show] 로 창을 띄운다. 창이 닫히며 돌려준 값이 돌려준 목록에 쌓인다.
Future<List<int?>> _open(
  WidgetTester tester,
  Future<int?> Function(BuildContext) show,
) async {
  final result = <int?>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result.add(await show(context)),
            child: const Text('열기'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  const question = '보호자님을 포함해 모두 몇 분인가요?';

  testWidgets('만남을 끝낼 때 보호자를 포함한 인원을 묻고 기본 2명을 돌려준다', (tester) async {
    final result = await _open(tester, showStopRecordingDialog);

    expect(find.text('만남을 끝낼까요?'), findsOneWidget);
    expect(find.text(question), findsOneWidget);
    expect(find.textContaining('함께했나요'), findsNothing);

    await tester.tap(find.text('끝내기'));
    await tester.pumpAndSettle();
    expect(result, [2]);
  });

  testWidgets('녹음을 다시 보내기 전에도 같은 물음을 쓰고 기본 2명을 돌려준다', (tester) async {
    final result = await _open(tester, showRecordingParticipantDialog);

    expect(find.text('녹음을 보내기 전에 확인해 주세요'), findsOneWidget);
    expect(find.text(question), findsOneWidget);
    expect(find.textContaining('함께했나요'), findsNothing);

    await tester.tap(find.text('확인하고 보내기'));
    await tester.pumpAndSettle();
    expect(result, [2]);
  });

  test('두 창이 쓰는 물음은 PM 이 정한 문구다', () {
    expect(participantQuestion, question);
  });
}
