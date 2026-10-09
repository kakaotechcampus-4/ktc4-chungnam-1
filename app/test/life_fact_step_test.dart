// B-3 ~ B-6 생애 정보 입력 화면의 답하는 방법 선택을 확인한다.
//
// 리뷰 미팅 피드백으로 두 번 실패해야 열리던 직접 입력을 처음부터 고를 수 있게
// 했다. 새로 연 길과 기존 실패 흐름이 함께 살아 있는지 같이 본다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/design/tokens.dart';
import 'package:saerok/features/profile_setup/life_fact_step.dart';
import 'package:saerok/features/profile_setup/setup_steps.dart';
import 'package:saerok/features/profile_setup/speech_input.dart';

/// 정해진 결과만 돌려주는 대역이다. 목 데이터가 아니라 화면 흐름만 본다.
class _FixedSpeech implements SpeechInput {
  _FixedSpeech(this.outcome, this.delay);

  final SpeechOutcome outcome;

  /// 옮기는 중 화면을 보려면 결과가 바로 나오면 안 된다. 기본은 지연 없음이다.
  final Duration delay;

  /// 화면이 버린 녹음 수.
  int cancelled = 0;

  @override
  Future<SpeechRecording> start({
    required String category,
    required int attempt,
  }) async => _FixedRecording(this);
}

class _FixedRecording implements SpeechRecording {
  _FixedRecording(this._speech);

  final _FixedSpeech _speech;

  @override
  Future<SpeechOutcome> finish() async {
    if (_speech.delay > Duration.zero) {
      await Future<void>.delayed(_speech.delay);
    }
    return _speech.outcome;
  }

  @override
  Future<void> cancel() async => _speech.cancelled += 1;
}

final _step = lifeFactSteps.first;

Widget _wrap({
  required SpeechOutcome outcome,
  Duration delay = Duration.zero,
  ValueChanged<String>? onCaptured,
  VoidCallback? onCleared,
  _FixedSpeech? speech,
  String? initialText,
}) => ProviderScope(
  overrides: [
    speechInputProvider.overrideWith(
      (ref) async => speech ?? _FixedSpeech(outcome, delay),
    ),
  ],
  child: MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
        child: LifeFactStepView(
          step: _step,
          initialText: initialText,
          onCaptured: onCaptured ?? (_) {},
          onCleared: onCleared ?? () {},
        ),
      ),
    ),
  ),
);

/// 기준 화면 412 x 917 dp 로 맞춘다(`app/README.md`).
void _useReferenceScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1236, 2751);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// 마이크를 눌러 말하고 다 말했다고 알린 뒤 결과까지 기다린다.
Future<void> _speak(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.mic));
  await tester.pumpAndSettle();
  await tester.tap(find.text('다 말했어요'));
  await tester.pumpAndSettle();
}

void main() {
  group('답하는 방법 선택', () {
    testWidgets('화면에 들어오면 두 방법을 나란히 보여준다', (tester) async {
      _useReferenceScreen(tester);
      await tester.pumpWidget(_wrap(outcome: const SpeechNotHeard()));

      expect(find.text('말로 답하기'), findsOneWidget);
      expect(find.text('글로 답하기'), findsOneWidget);

      // 고르기 전에는 어느 쪽도 먼저 나오지 않는다.
      expect(find.byIcon(Icons.mic), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('두 버튼은 같은 크기다', (tester) async {
      _useReferenceScreen(tester);
      await tester.pumpWidget(_wrap(outcome: const SpeechNotHeard()));

      final voice = tester.getSize(
        find.ancestor(
          of: find.text('말로 답하기'),
          matching: find.byType(InkWell),
        ).first,
      );
      final text = tester.getSize(
        find.ancestor(
          of: find.text('글로 답하기'),
          matching: find.byType(InkWell),
        ).first,
      );

      expect(voice, text, reason: '한쪽이 대안처럼 보이면 안 된다');
      expect(
        voice.height,
        greaterThanOrEqualTo(AppSizes.minTouch),
        reason: '누르는 요소의 최소 크기',
      );
    });

    testWidgets('말로 답하기를 고르면 녹음 안내가 나온다', (tester) async {
      _useReferenceScreen(tester);
      await tester.pumpWidget(_wrap(outcome: const SpeechNotHeard()));

      await tester.tap(find.text('말로 답하기'));
      await tester.pump();

      expect(find.byIcon(Icons.mic), findsOneWidget);
      expect(find.text('마이크를 누르고 말씀해주세요'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('글로 답하기를 고르면 입력 칸이 나오고 실패 문구는 없다', (tester) async {
      _useReferenceScreen(tester);
      await tester.pumpWidget(_wrap(outcome: const SpeechNotHeard()));

      await tester.tap(find.text('글로 답하기'));
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.mic), findsNothing);
      expect(
        find.text('목소리를 잘 듣지 못했어요.'),
        findsNothing,
        reason: '스스로 고른 사람에게 실패를 알리지 않는다',
      );
    });

    testWidgets('글로 쓴 문장을 그대로 넘긴다', (tester) async {
      _useReferenceScreen(tester);
      String? captured;
      await tester.pumpWidget(
        _wrap(
          outcome: const SpeechNotHeard(),
          onCaptured: (value) => captured = value,
        ),
      );

      await tester.tap(find.text('글로 답하기'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '  마을 이장을 오래 하셨어요.  ');

      expect(captured, '마을 이장을 오래 하셨어요.');
    });

    testWidgets('말로 답하기를 골라도 글로 바꿀 수 있다', (tester) async {
      _useReferenceScreen(tester);
      await tester.pumpWidget(_wrap(outcome: const SpeechNotHeard()));

      await tester.tap(find.text('말로 답하기'));
      await tester.pump();
      await tester.tap(find.text('글로 답할게요'));
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('목소리를 잘 듣지 못했어요.'), findsNothing);
    });

    testWidgets('글로 쓰다 말로 바꾸면 선택창을 거치지 않고 바로 녹음으로 간다', (tester) async {
      _useReferenceScreen(tester);
      await tester.pumpWidget(_wrap(outcome: const SpeechNotHeard()));

      await tester.tap(find.text('글로 답하기'));
      await tester.pump();
      await tester.tap(find.text('말로 답할게요'));
      await tester.pump();

      expect(find.byIcon(Icons.mic), findsOneWidget);
      expect(find.text('마이크를 누르고 말씀해주세요'), findsOneWidget);
      expect(
        find.text('말로 답하기'),
        findsNothing,
        reason: '방법을 다시 고르게 되돌리지 않는다',
      );
    });
  });

  group('방법을 바꾸는 버튼', () {
    /// 알약 모양 버튼의 사각형을 집는다.
    Rect switchRect(WidgetTester tester, String label) => tester.getRect(
      find
          .ancestor(of: find.text(label), matching: find.byType(InkWell))
          .first,
    );

    testWidgets('안내 문구와 떨어진 하단에 있고 누를 수 있는 크기다', (tester) async {
      _useReferenceScreen(tester);
      await tester.pumpWidget(_wrap(outcome: const SpeechNotHeard()));

      await tester.tap(find.text('말로 답하기'));
      await tester.pump();

      final hint = tester.getRect(find.text('마이크를 누르고 말씀해주세요'));
      final button = switchRect(tester, '글로 답할게요');

      expect(
        button.top - hint.bottom,
        greaterThan(AppSpacing.xxl),
        reason: '문구 바로 아래 붙으면 링크인지 구분되지 않는다',
      );
      expect(button.height, greaterThanOrEqualTo(AppSizes.minTouch));
    });

    testWidgets('글로 쓰는 중에도 같은 자리에 있다', (tester) async {
      _useReferenceScreen(tester);
      await tester.pumpWidget(_wrap(outcome: const SpeechNotHeard()));

      await tester.tap(find.text('말로 답하기'));
      await tester.pump();
      final voiceSide = switchRect(tester, '글로 답할게요');

      await tester.tap(find.text('글로 답할게요'));
      await tester.pump();
      final textSide = switchRect(tester, '말로 답할게요');

      expect(textSide.bottom, voiceSide.bottom);
      expect(textSide.height, greaterThanOrEqualTo(AppSizes.minTouch));
    });

    testWidgets('녹음하고 옮기는 동안에는 숨긴다', (tester) async {
      _useReferenceScreen(tester);
      await tester.pumpWidget(
        _wrap(
          outcome: const SpeechNotHeard(),
          delay: const Duration(milliseconds: 200),
        ),
      );

      await tester.tap(find.text('말로 답하기'));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();

      expect(find.text('듣고 있어요'), findsOneWidget);
      expect(
        find.text('글로 답할게요'),
        findsNothing,
        reason: '말하는 중에 방법을 바꾸게 하지 않는다',
      );

      await tester.tap(find.text('다 말했어요'));
      await tester.pump();

      expect(find.text('말씀을 글로 옮기고 있어요'), findsOneWidget);
      expect(find.text('글로 답할게요'), findsNothing);

      // 옮기기가 끝나면 다시 나온다.
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('글로 답할게요'), findsOneWidget);
    });
  });

  group('글로 옮기는 중', () {
    testWidgets('다 말했다고 알리면 옮기는 중임을 보여준다', (tester) async {
      _useReferenceScreen(tester);
      await tester.pumpWidget(
        _wrap(
          outcome: const SpeechHeard('30년 동안 초등학교 선생님을 하셨어요.'),
          delay: const Duration(milliseconds: 200),
        ),
      );

      await tester.tap(find.text('말로 답하기'));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();

      expect(find.text('듣고 있어요'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.text('다 말했어요'));
      await tester.pump();

      expect(find.text('말씀을 글로 옮기고 있어요'), findsOneWidget);
      expect(find.text('잠시만 기다려주세요'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('듣고 있어요'), findsNothing);
      expect(find.text('다 말했어요'), findsNothing);

      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('말씀을 글로 옮기고 있어요'), findsNothing);
      expect(find.text('30년 동안 초등학교 선생님을 하셨어요.'), findsOneWidget);
    });

    testWidgets('듣는 중에 마이크를 다시 눌러도 녹음을 끝낸다', (tester) async {
      _useReferenceScreen(tester);
      await tester.pumpWidget(
        _wrap(
          outcome: const SpeechNotHeard(),
          delay: const Duration(milliseconds: 200),
        ),
      );

      await tester.tap(find.text('말로 답하기'));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();

      expect(find.text('말씀을 글로 옮기고 있어요'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('듣는 중에 화면을 벗어나면 녹음을 버린다', (tester) async {
      _useReferenceScreen(tester);
      final speech = _FixedSpeech(const SpeechNotHeard(), Duration.zero);
      await tester.pumpWidget(
        _wrap(outcome: const SpeechNotHeard(), speech: speech),
      );

      await tester.tap(find.text('말로 답하기'));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.mic));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());

      expect(speech.cancelled, 1);
    });
  });

  group('기존 음성 흐름', () {
    testWidgets('한 번 실패하면 다시 시도할 수 있다', (tester) async {
      _useReferenceScreen(tester);
      await tester.pumpWidget(_wrap(outcome: const SpeechNotHeard()));

      await tester.tap(find.text('말로 답하기'));
      await tester.pump();
      await _speak(tester);

      expect(find.text('목소리를 잘 듣지 못했어요.'), findsOneWidget);
      expect(find.byIcon(Icons.mic), findsOneWidget, reason: '아직 직접 입력이 아니다');
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('두 번 실패하면 직접 입력으로 넘어가고 이유를 알린다', (tester) async {
      _useReferenceScreen(tester);
      await tester.pumpWidget(_wrap(outcome: const SpeechNotHeard()));

      await tester.tap(find.text('말로 답하기'));
      await tester.pump();
      await _speak(tester);
      await _speak(tester);

      expect(find.byType(TextField), findsOneWidget);
      expect(
        find.text('목소리를 잘 듣지 못했어요.'),
        findsOneWidget,
        reason: '실패로 넘어온 경우는 이유를 알린다',
      );
      expect(find.text('다시 녹음하기'), findsOneWidget);

      // 다시 녹음하기도 선택창이 아니라 마이크로 바로 간다.
      await tester.tap(find.text('다시 녹음하기'));
      await tester.pump();
      expect(find.byIcon(Icons.mic), findsOneWidget);
      expect(find.text('말로 답하기'), findsNothing);
    });

    testWidgets('알아들으면 들은 문장을 보여주고 넘긴다', (tester) async {
      _useReferenceScreen(tester);
      String? captured;
      await tester.pumpWidget(
        _wrap(
          outcome: const SpeechHeard('30년 동안 초등학교 선생님을 하셨어요.'),
          onCaptured: (value) => captured = value,
        ),
      );

      await tester.tap(find.text('말로 답하기'));
      await tester.pump();
      await _speak(tester);

      expect(captured, '30년 동안 초등학교 선생님을 하셨어요.');
      expect(find.text('30년 동안 초등학교 선생님을 하셨어요.'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });
  });

  group('적어 둔 답', () {
    // 합성 문장이다. 실제 어르신의 생애 정보가 아니다.
    const saved = '합성 예시 답입니다';

    testWidgets('있으면 입력칸에 채워 보여주고 다시 알리지 않는다', (tester) async {
      _useReferenceScreen(tester);
      var captured = 0;
      var cleared = 0;
      await tester.pumpWidget(
        _wrap(
          outcome: const SpeechNotHeard(),
          initialText: saved,
          onCaptured: (_) => captured++,
          onCleared: () => cleared++,
        ),
      );

      expect(find.widgetWithText(TextField, saved), findsOneWidget);
      expect(
        find.text('목소리를 잘 듣지 못했어요.'),
        findsNothing,
        reason: '실패해서 온 것이 아니다',
      );
      expect(captured, 0, reason: '이미 저장본에 있는 값이다');
      expect(cleared, 0);
    });

    testWidgets('채운 답을 고치면 고친 문장을 넘긴다', (tester) async {
      _useReferenceScreen(tester);
      String? captured;
      await tester.pumpWidget(
        _wrap(
          outcome: const SpeechNotHeard(),
          initialText: saved,
          onCaptured: (text) => captured = text,
        ),
      );

      await tester.enterText(find.byType(TextField), '$saved 고침');

      expect(captured, '$saved 고침');
    });

    testWidgets('공백뿐이면 방법 고르기부터 연다', (tester) async {
      _useReferenceScreen(tester);
      await tester.pumpWidget(
        _wrap(outcome: const SpeechNotHeard(), initialText: '  '),
      );

      expect(find.text('말로 답하기'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });
  });
}
