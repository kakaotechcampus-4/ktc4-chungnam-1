import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_text_field.dart';
import '../auth/auth_providers.dart';
import 'photo_description_store.dart';

/// 프로필 설정의 갤러리.
///
/// 올린 사진을 세 칸씩 보여준다. 사진을 누르면 그 아래에 AI 가 만든 설명이
/// 펼쳐지고, 보호자가 직접 고쳐 저장할 수 있다. 설명은 AI 가 만든 후보라서 확인된
/// 사실처럼 보이지 않게 출처를 함께 적는다. 분석이 끝나지 않은 사진은 설명 대신
/// 그 상태를 알린다. 분석에 실패한 사진은 실패를 알리고 보호자가 직접 적게 한다.
///
/// 설명 칸은 높이가 늘어나며 아래에서 살짝 떠오르듯 펼쳐진다. 다 펼쳐지면
/// 끝까지 내려 칸을 화면 맨 아래에 붙이고, 이미 끝이면 그대로 둔다. 접으면
/// 펼치기 전 자리로 다시 올라간다. 움직임 줄이기가 켜져 있으면 바로 바꾼다.
class ProfileGallery extends ConsumerStatefulWidget {
  const ProfileGallery({required this.photos, super.key});

  final List<ProfilePhoto> photos;

  @override
  ConsumerState<ProfileGallery> createState() => _ProfileGalleryState();
}

class _ProfileGalleryState extends ConsumerState<ProfileGallery> {
  static const _columns = 3;

  /// 설명 칸이 펼쳐지고 접히는 시간.
  static const _unfold = Duration(milliseconds: 280);

  /// 펼친 칸을 보이는 자리로 끌어오거나 되돌리는 시간.
  static const _scroll = Duration(milliseconds: 350);

  String? _selectedId;

  /// 설명 칸을 담는 영역. 펼친 뒤 보이는 자리로 끌어올 때 쓴다.
  final _panelKey = GlobalKey();

  /// 설명 칸을 열기 전의 스크롤 자리. 접을 때 돌아간다. 닫혀 있으면 `null` 이다.
  double? _offsetBeforeOpen;

  /// 펼치기가 끝나면 칸을 보이는 자리로 끌어온다.
  bool _revealWhenUnfolded = false;
  final _text = TextEditingController();

  /// 입력칸을 마지막으로 채운 설명. 입력칸이 아직 이 값 그대로면 보호자가 쓰지
  /// 않은 것이다.
  String _filled = '';

  /// 저장 결과는 그 사진에만 붙인다. 저장하는 동안 다른 사진을 골라도 그 사진의
  /// 입력칸과 안내가 바뀌지 않게 사진마다 기억한다.
  final _savingIds = <String>{};
  String? _savedId;
  String? _failedId;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  ProfilePhoto? get _selected =>
      widget.photos.where((photo) => photo.photoId == _selectedId).firstOrNull;

  /// 고친 설명을 찾는 자리. 계정과 어르신이 다르면 같은 사진이라도 따로 둔다.
  PhotoDescriptionKey _keyOf(ProfilePhoto photo) => (
    accountId: ref.read(sessionProvider)?.account.accountId,
    profileId: photo.profileId,
    photoId: photo.photoId,
  );

  /// 지금 화면에 보여줄 설명. 보호자가 고친 것이 있으면 그것이다.
  String? _currentDescription(ProfilePhoto photo) =>
      ref.read(editedPhotoDescriptionsProvider)[_keyOf(photo)] ??
      photo.description;

  void _toggle(ProfilePhoto photo) {
    final position = Scrollable.maybeOf(context)?.position;
    final closing = _selectedId == photo.photoId;
    setState(() {
      _savedId = null;
      _failedId = null;
      if (closing) {
        _selectedId = null;
        return;
      }
      // 처음 열 때의 자리만 기억한다. 다른 사진으로 바꿔도 접으면 여기로 온다.
      if (_selectedId == null) _offsetBeforeOpen = position?.pixels;
      _selectedId = photo.photoId;
      _revealWhenUnfolded = true;
      _fill(_currentDescription(photo) ?? '');
    });
    if (closing) _restoreScroll(position);
  }

  bool get _still => MediaQuery.disableAnimationsOf(context);

  /// 다 펼쳐지면 설명 칸이 화면 맨 아래에 오도록 끝까지 내린다. 갤러리가
  /// 화면의 마지막 구역이라 끝까지 내리면 칸이 바닥에 붙고 사진은 그 위에
  /// 보인다. 이미 끝까지 내려와 있으면 그대로 둔다.
  void _revealPanel() {
    if (!_revealWhenUnfolded) return;
    _revealWhenUnfolded = false;
    final panel = _panelKey.currentContext;
    if (panel == null) return;
    final position = Scrollable.maybeOf(panel)?.position;
    if (position == null) return;
    final end = position.maxScrollExtent;
    if (position.pixels >= end) return;
    if (_still) {
      position.jumpTo(end);
    } else {
      position.animateTo(end, duration: _scroll, curve: Curves.easeOutCubic);
    }
  }

  /// 설명 칸을 접으면 열기 전 자리로 돌아간다.
  void _restoreScroll(ScrollPosition? position) {
    final before = _offsetBeforeOpen;
    _offsetBeforeOpen = null;
    _revealWhenUnfolded = false;
    if (position == null || before == null || position.pixels == before) return;
    final target = before.clamp(0.0, position.maxScrollExtent);
    if (_still) {
      position.jumpTo(target);
    } else {
      position.animateTo(target, duration: _scroll, curve: Curves.easeOutCubic);
    }
  }

  void _fill(String description) {
    _filled = description;
    _text.text = description;
  }

  /// 연 사진의 분석이 끝나 설명이 새로 왔으면 입력칸을 채운다.
  ///
  /// 사진을 열 때만 채우면, 분석 중에 열어 둔 사진은 설명이 와도 빈칸으로
  /// 남는다. 보호자가 그 사이 입력칸에 쓰고 있으면 덮어쓰지 않는다.
  @override
  void didUpdateWidget(ProfileGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selected = _selected;
    if (selected == null) return;
    final description = _currentDescription(selected) ?? '';
    if (description == _filled) return;
    if (_text.text != _filled) return;
    _fill(description);
  }

  Future<void> _save(ProfilePhoto photo) async {
    final description = _text.text.trim();
    // 저장을 누른 때의 계정과 어르신에 남긴다. 기다리는 동안 바뀌어도 그대로다.
    final key = _keyOf(photo);
    setState(() {
      _savingIds.add(photo.photoId);
      _savedId = null;
      _failedId = null;
    });

    try {
      await ref
          .read(photoDescriptionStoreProvider)
          .save(photoId: photo.photoId, description: description);
      if (!mounted) return;
      ref.read(editedPhotoDescriptionsProvider.notifier).put(key, description);
      setState(() {
        _savingIds.remove(photo.photoId);
        // 그 사이 다른 사진을 골랐으면 지금 입력칸은 그 사진의 것이다.
        if (_selectedId == photo.photoId) {
          _savedId = photo.photoId;
          _fill(description);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _savingIds.remove(photo.photoId);
        if (_selectedId == photo.photoId) _failedId = photo.photoId;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    // 고친 설명이 저장되거나 계정이 바뀌면 표시를 다시 그린다.
    final edited = ref.watch(editedPhotoDescriptionsProvider);
    ref.watch(sessionProvider.select((s) => s?.account.accountId));

    if (photos.isEmpty) {
      return Text('아직 올린 사진이 없어요.', style: AppTypography.sub);
    }

    final rows = <Widget>[];
    for (var start = 0; start < photos.length; start += _columns) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: AppSpacing.md));
      rows.add(
        Row(
          children: [
            for (var col = 0; col < _columns; col++) ...[
              if (col > 0) const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: start + col < photos.length
                      ? _GalleryTile(
                          photo: photos[start + col],
                          number: start + col + 1,
                          edited:
                              edited.containsKey(_keyOf(photos[start + col])) ||
                              photos[start + col].descriptionSource ==
                                  'caregiver',
                          selected: photos[start + col].photoId == _selectedId,
                          onTap: () => _toggle(photos[start + col]),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ],
        ),
      );
    }

    final selected = _selected;
    final unfold = _still ? Duration.zero : _unfold;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...rows,
        // 높이가 늘고 줄며 펼치고 접는다. 다 펼쳐지면 보이는 자리로 끌어온다.
        AnimatedSize(
          // 사진을 바꾸는 동안 앞뒤 설명 칸이 함께 있어 표식은 바깥 한 곳에 둔다.
          key: _panelKey,
          duration: unfold,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          // 끝났다는 알림은 마지막 높이를 그리기 전에 온다. 그 장면을 다 그린
          // 뒤에 끝 위치를 재야 칸이 바닥에 딱 붙는다.
          onEnd: () => WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _revealPanel();
          }),
          child: AnimatedSwitcher(
            duration: unfold,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topCenter,
              children: [...previous, ?current],
            ),
            // 아래에서 살짝 떠오르며 나타난다.
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.06),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: selected == null
                ? const SizedBox(
                    key: ValueKey('closed'),
                    width: double.infinity,
                  )
                : Column(
                    key: ValueKey(selected.photoId),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: AppSpacing.lg),
                      _DescriptionPanel(
                        photo: selected,
                        edited:
                            edited.containsKey(_keyOf(selected)) ||
                            selected.descriptionSource == 'caregiver',
                        controller: _text,
                        current: _currentDescription(selected) ?? '',
                        saving: _savingIds.contains(selected.photoId),
                        saved: _savedId == selected.photoId,
                        saveFailed: _failedId == selected.photoId,
                        onChanged: () => setState(() {
                          _savedId = null;
                          _failedId = null;
                        }),
                        onSave: () => _save(selected),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _GalleryTile extends StatelessWidget {
  const _GalleryTile({
    required this.photo,
    required this.number,
    required this.edited,
    required this.selected,
    required this.onTap,
  });

  final ProfilePhoto photo;
  final int number;

  /// 보호자가 설명을 저장했는지. 저장했으면 분석 결과와 관계없이 표시를 떼어낸다.
  final bool edited;

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = photo.analysisStatus;
    final badge = switch (status) {
      _ when edited => null,
      PhotoAnalysisStatus.completed => null,
      PhotoAnalysisStatus.failed => '분석 실패',
      // 모르는 값도 끝나지 않은 것으로 다룬다.
      _ => '분석 중',
    };

    return Semantics(
      button: true,
      selected: selected,
      label: '사진 $number${badge == null ? '' : ', $badge'}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.image),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.image),
              child: ProfilePhotoImage(url: photo.imageUrl),
            ),
            if (selected)
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.image),
                  border: Border.all(color: HomeColors.accent, width: 3),
                ),
              ),
            if (badge != null)
              Positioned(
                left: AppSpacing.xs,
                bottom: AppSpacing.xs,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: status == PhotoAnalysisStatus.failed
                        ? AppColors.danger
                        : AppColors.ink.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    badge,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.background,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 고른 사진 아래에 펼쳐지는 설명 확인과 수정 자리다.
class _DescriptionPanel extends StatelessWidget {
  const _DescriptionPanel({
    required this.photo,
    required this.edited,
    required this.controller,
    required this.current,
    required this.saving,
    required this.saved,
    required this.saveFailed,
    required this.onChanged,
    required this.onSave,
  });

  final ProfilePhoto photo;

  /// 보호자가 고쳐 저장한 적이 있는지.
  final bool edited;

  final TextEditingController controller;

  /// 저장된 설명. 입력이 이것과 같으면 저장할 것이 없다.
  final String current;

  final bool saving;
  final bool saved;
  final bool saveFailed;
  final VoidCallback onChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final status = photo.analysisStatus;
    final failed = status == PhotoAnalysisStatus.failed;
    if (status != PhotoAnalysisStatus.completed && !failed && !edited) {
      return const _PanelNotice('사진 설명을 만들고 있어요. 잠시 뒤 다시 확인해주세요.');
    }

    // 보호자가 적은 설명이 있으면 AI 설명이 아니다. 실패한 사진은 처음부터
    // 보호자가 적는다.
    final fromAi = !edited && !failed;
    final text = controller.text.trim();
    final canSave = !saving && text.isNotEmpty && text != current;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (failed && !edited) ...[
          const _PanelNotice('AI가 설명을 만들지 못했어요. 직접 적어주셔도 돼요.', danger: true),
          const SizedBox(height: AppSpacing.lg),
        ],
        // 안내는 이름표 바로 아래, 입력칸 위에 둔다. 무엇을 확인할지 먼저 읽고
        // 고치게 한다.
        AppTextField(
          borderColor: HomeColors.outline,
          focusColor: HomeColors.accent,
          label: fromAi ? 'AI가 만든 설명' : '사진에 대한 설명',
          description: fromAi
              ? 'AI가 사진을 보고 만든 설명이에요. 사실과 다르면 고쳐주세요.'
              : edited
              ? '직접 적은 설명이에요. 다시 고칠 수 있어요.'
              : null,
          controller: controller,
          maxLines: null,
          hintText: '어떤 사진인지 적어주세요',
          // 저장된 설명을 지웠을 때만 알린다. 처음부터 빈칸이면 오류가 아니다.
          errorText: text.isEmpty && current.isNotEmpty
              ? '설명을 비워둘 수 없어요.'
              : null,
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(
          color: HomeColors.accent,
          loadingColor: HomeColors.accentLoading,
          label: saving ? '저장하는 중이에요' : '저장하기',
          onPressed: canSave ? onSave : null,
        ),
        if (saved) ...[
          const SizedBox(height: AppSpacing.sm),
          const Text(
            '설명을 저장했어요.',
            style: AppTypography.sub,
            textAlign: TextAlign.center,
          ),
        ],
        if (saveFailed) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            '저장하지 못했어요. 잠시 뒤 다시 시도해주세요.',
            style: AppTypography.sub.copyWith(color: AppColors.danger),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

class _PanelNotice extends StatelessWidget {
  const _PanelNotice(this.message, {this.danger = false});

  final String message;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: AppTypography.sub.copyWith(
        color: danger ? AppColors.danger : AppColors.textSub,
      ),
    );
  }
}

/// 프로필 사진 한 장을 그린다.
///
/// 서버의 `imageUrl` 은 수명이 짧은 주소라 읽지 못할 수 있다. 그래도 칸은 남겨
/// 설명을 볼 수 있게 한다. 목 데이터는 `asset:` 으로 앱 안의 그림을 가리킨다.
class ProfilePhotoImage extends StatelessWidget {
  const ProfilePhotoImage({required this.url, super.key});

  static const _assetScheme = 'asset:';

  final String url;

  @override
  Widget build(BuildContext context) {
    Widget fallback(BuildContext context, Object error, StackTrace? stack) =>
        const ColoredBox(
          color: HomeColors.bubble,
          child: Icon(Icons.broken_image_outlined, color: HomeColors.accent),
        );

    if (url.startsWith(_assetScheme)) {
      return Image.asset(
        url.substring(_assetScheme.length),
        fit: BoxFit.cover,
        errorBuilder: fallback,
      );
    }
    return Image.network(url, fit: BoxFit.cover, errorBuilder: fallback);
  }
}
