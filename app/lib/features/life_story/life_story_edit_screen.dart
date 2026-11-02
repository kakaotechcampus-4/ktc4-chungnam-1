import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api_client.dart';
import '../../data/profile_api.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_surfaces.dart';
import '../../widgets/app_text_field.dart';
import '../profile/profile_dialogs.dart';
import 'life_story.dart';
import 'life_story_book_loader.dart';
import 'life_story_image.dart';
import 'life_story_providers.dart';

/// 이야기를 직접 담거나 고친다. [storyId] 가 없으면 새 이야기다.
///
/// 분류, 제목(100자 이하), 내용과 기본 이미지 다섯 장 중 하나를 받는다. 새
/// 이야기는 이미지를 하나 미리 골라 둔다. 저장하면 앞 화면으로 돌아가고, 고친
/// 이야기는 그 결과를 돌려준다. 고치던 내용이 있는데 뒤로 가면 한 번 묻는다.
/// 저장하지 못하면 안내하고 쓰던 내용을 그대로 둔다.
class LifeStoryEditScreen extends StatelessWidget {
  const LifeStoryEditScreen({this.storyId, super.key});

  final String? storyId;

  @override
  Widget build(BuildContext context) {
    final id = storyId;
    return Scaffold(
      appBar: AppTopBar(title: id == null ? '이야기 추가하기' : '이야기 수정하기'),
      body: LifeStoryBookLoader(
        builder: (context, book) {
          final story = id == null ? null : book.find(id);
          if (id != null && (story == null || story.isProfileDetail)) {
            return const EmptyStateView(message: '고칠 이야기를 찾을 수 없어요.');
          }
          return _EditForm(profileId: book.profile.profileId, story: story);
        },
      ),
    );
  }
}

class _EditForm extends ConsumerStatefulWidget {
  const _EditForm({required this.profileId, required this.story});

  final String profileId;

  /// 고칠 이야기. 새 이야기면 `null` 이다.
  final LifeStory? story;

  @override
  ConsumerState<_EditForm> createState() => _EditFormState();
}

class _EditFormState extends ConsumerState<_EditForm> {
  late final _title = TextEditingController(text: widget.story?.title);
  late final _content = TextEditingController(text: widget.story?.content);
  late LifeStoryCategory? _category = widget.story?.category;
  late int _imageNumber =
      widget.story?.imageNumber ??
      ref.read(lifeStoryRandomProvider).nextInt(lifeStoryImageCount) + 1;
  late final int _initialImageNumber = _imageNumber;

  /// 저장했거나 나가기로 했다. 이때는 다시 묻지 않고 닫는다.
  bool _leaving = false;

  /// 서버에 보내는 중이다. 이때는 버튼을 막아 두 번 담기지 않게 한다.
  bool _saving = false;

  /// 계약상 제목과 내용은 비울 수 없다.
  bool get _filled =>
      _category != null &&
      _title.text.trim().isNotEmpty &&
      _content.text.trim().isNotEmpty;

  bool get _dirty =>
      _title.text != (widget.story?.title ?? '') ||
      _content.text != (widget.story?.content ?? '') ||
      _category != widget.story?.category ||
      _imageNumber != _initialImageNumber;

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final draft = LifeStoryDraft(
      category: _category!,
      title: _title.text.trim(),
      content: _content.text.trim(),
      imageNumber: _imageNumber,
    );
    final store = ref.read(lifeStoryStoreProvider);
    final story = widget.story;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    final LifeStory saved;
    try {
      saved = story == null
          ? await store.add(widget.profileId, draft)
          : await store.update(widget.profileId, story, draft);
    } on ApiFailure catch (failure) {
      // 쓰던 내용은 그대로 두고 다시 누를 수 있게 한다.
      if (!mounted) return;
      setState(() => _saving = false);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(profileFailureMessage(failure))));
      return;
    }
    if (!mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(story == null ? '이야기를 담았어요.' : '이야기를 고쳤어요.')),
      );
    setState(() => _leaving = true);
    context.pop(saved);
  }

  Future<void> _confirmLeave() async {
    final leave = await showChoiceDialog(
      context,
      title: '작성 중인 내용이 사라져요',
      detail: '지금 나가면 쓰던 내용은 저장되지 않아요.',
      primaryLabel: '나가기',
      secondaryLabel: '계속 쓰기',
    );
    if (!leave || !mounted) return;
    setState(() => _leaving = true);
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _leaving || !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: ScreenBody(
        scrollable: true,
        bottom: PrimaryButton(
          label: _saving
              ? '저장하는 중이에요'
              : widget.story == null
              ? '이야기 담기'
              : '수정 완료',
          onPressed: _filled && !_saving ? _save : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.xl),
            const FieldLabel('분류', required: true),
            const SizedBox(height: AppSpacing.md),
            _CategoryPicker(
              selected: _category,
              onSelected: (c) => setState(() => _category = c),
            ),
            const SizedBox(height: AppSpacing.xxxl),
            AppTextField(
              label: '제목',
              controller: _title,
              required: true,
              maxLength: LifeStoryDraft.titleMaxLength,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: '내용',
              controller: _content,
              required: true,
              keyboardType: TextInputType.multiline,
              minLines: 5,
              maxLines: null,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.xxl),
            const FieldLabel('그림'),
            const SizedBox(height: AppSpacing.md),
            if (_category case final category?)
              _ImagePicker(
                category: category,
                selected: _imageNumber,
                onSelected: (n) => setState(() => _imageNumber = n),
              )
            else
              const Text('분류를 고르면 그림을 고를 수 있어요.', style: AppTypography.sub),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

/// 분류 고르기. 첫 장의 분류 칸처럼 아이콘과 이름을 둔 칸이다.
///
/// 정사각형 여섯 칸을 세 칸씩 두 줄로 두고, `기타` 는 그 오른쪽에 두 줄
/// 높이로 세로로 길게 둔다. 고른 칸은 2px 검정 테두리와 체크다.
class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({required this.selected, required this.onSelected});

  final LifeStoryCategory? selected;
  final ValueChanged<LifeStoryCategory> onSelected;

  static const _gap = AppSpacing.sm;

  static const _rows = [
    [LifeStoryCategory.family, LifeStoryCategory.hobby, LifeStoryCategory.work],
    [
      LifeStoryCategory.hometown,
      LifeStoryCategory.friend,
      LifeStoryCategory.travel,
    ],
  ];

  @override
  Widget build(BuildContext context) {
    // 한 줄에 네 칸이 들어가는 크기라 첫 장의 칸보다 작다. 입력 화면이 높이를
    // 재며 그리므로(`ScreenBody` 의 scrollable) 폭을 재지 않고 비율로 맞춘다.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var col = 0; col < 3; col++) ...[
            if (col > 0) const SizedBox(width: _gap),
            Expanded(
              child: Column(
                children: [
                  AspectRatio(aspectRatio: 1, child: _tile(_rows[0][col])),
                  const SizedBox(height: _gap),
                  AspectRatio(aspectRatio: 1, child: _tile(_rows[1][col])),
                ],
              ),
            ),
          ],
          const SizedBox(width: _gap),
          Expanded(child: _tile(LifeStoryCategory.other)),
        ],
      ),
    );
  }

  Widget _tile(LifeStoryCategory category) {
    final isSelected = category == selected;
    return Semantics(
      button: true,
      selected: isSelected,
      label: category.label,
      excludeSemantics: true,
      child: AppCard(
        onTap: () => onSelected(category),
        selected: isSelected,
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Stack(
          children: [
            // 칸 크기가 정해져 있어 글자를 키우면 칸 안에서 줄인다.
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(category.icon, size: 26, color: AppColors.ink),
                    const SizedBox(height: AppSpacing.xs),
                    Text(category.label, style: AppTypography.bodyStrong),
                  ],
                ),
              ),
            ),
            if (isSelected)
              const Positioned(
                top: 0,
                right: 0,
                child: SelectionMark(selected: true, size: 18),
              ),
          ],
        ),
      ),
    );
  }
}

/// 고른 분류의 기본 이미지 다섯 장. 고른 것은 2px 검정 테두리와 체크다.
class _ImagePicker extends StatelessWidget {
  const _ImagePicker({
    required this.category,
    required this.selected,
    required this.onSelected,
  });

  final LifeStoryCategory category;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var n = 1; n <= lifeStoryImageCount; n++) ...[
          if (n > 1) const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Semantics(
              button: true,
              selected: n == selected,
              label: '그림 $n번',
              excludeSemantics: true,
              child: GestureDetector(
                onTap: () => onSelected(n),
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.image),
                        border: Border.all(
                          color: n == selected ? AppColors.ink : AppColors.line,
                          width: n == selected ? 2 : 1,
                        ),
                      ),
                      padding: const EdgeInsets.all(2),
                      child: LifeStoryImage(category: category, number: n),
                    ),
                    if (n == selected)
                      const Positioned(
                        top: AppSpacing.xs,
                        right: AppSpacing.xs,
                        child: SelectionMark(selected: true, size: 20),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
