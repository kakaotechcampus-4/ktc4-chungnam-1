import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_text_field.dart';

/// 일대기에 더할 이야기의 제목과 내용. 수정 화면에 넘기고 돌려받는다.
class StoryDraft {
  const StoryDraft({required this.title, required this.content});

  final String title;
  final String content;
}

/// G-2 에서 여는 이야기 수정.
///
/// AI 가 제안한 이야기의 제목과 내용을 고친다. `수정 완료` 를 누르면 고친 값을
/// 들고 변경 사항 확인으로 돌아간다. 뒤로 가면 고친 값을 버린다. 원래 제안과
/// 제안 이유는 바꾸지 않으며, 고친 값은 승인할 때 따로 보낸다.
class StoryEditScreen extends StatefulWidget {
  const StoryEditScreen({required this.initial, super.key});

  final StoryDraft initial;

  /// `life_facts.title` 의 상한.
  static const titleMaxLength = 100;

  /// [reportId] 리포트의 이야기를 [initial] 로 열고, 고친 값을 돌려받는다.
  /// 뒤로 가면 `null` 이다.
  static Future<StoryDraft?> open(
    BuildContext context, {
    required String reportId,
    required StoryDraft initial,
  }) =>
      context.push<StoryDraft>(AppRoutes.storyEditOf(reportId), extra: initial);

  @override
  State<StoryEditScreen> createState() => _StoryEditScreenState();
}

class _StoryEditScreenState extends State<StoryEditScreen> {
  late final _title = TextEditingController(text: widget.initial.title);
  late final _content = TextEditingController(text: widget.initial.content);

  /// 계약상 제목과 내용은 비울 수 없다.
  bool get _filled =>
      _title.text.trim().isNotEmpty && _content.text.trim().isNotEmpty;

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  void _done() => context.pop(
    StoryDraft(title: _title.text.trim(), content: _content.text.trim()),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppTopBar(title: '이야기 수정하기'),
      body: ScreenBody(
        scrollable: true,
        bottom: PrimaryButton(
          label: '수정 완료',
          onPressed: _filled ? _done : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.xl),
            AppTextField(
              label: '제목',
              controller: _title,
              required: true,
              maxLength: StoryEditScreen.titleMaxLength,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.xl),
            AppTextField(
              label: '내용',
              controller: _content,
              required: true,
              keyboardType: TextInputType.multiline,
              minLines: 5,
              maxLines: null,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

/// 수정 화면에 넘길 이야기 없이 주소로 들어온 경우다. 고칠 대상을 알 수 없다.
class StoryEditMissingView extends StatelessWidget {
  const StoryEditMissingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(
        title: '이야기 수정하기',
        onBack: () => context.go(AppRoutes.home),
      ),
      body: const ErrorStateView(
        message: '고칠 이야기를 찾지 못했어요.\n변경 사항 확인에서 다시 열어주세요.',
      ),
    );
  }
}
