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
class ProfileGallery extends ConsumerStatefulWidget {
  const ProfileGallery({required this.photos, super.key});

  final List<ProfilePhoto> photos;

  @override
  ConsumerState<ProfileGallery> createState() => _ProfileGalleryState();
}

class _ProfileGalleryState extends ConsumerState<ProfileGallery> {
  static const _columns = 3;

  String? _selectedId;
  final _text = TextEditingController();

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
    setState(() {
      _savedId = null;
      _failedId = null;
      if (_selectedId == photo.photoId) {
        _selectedId = null;
        return;
      }
      _selectedId = photo.photoId;
      _text.text = _currentDescription(photo) ?? '';
    });
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
          _text.text = description;
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
      return Text(
        '아직 올린 사진이 없어요.',
        style: AppTypography.sub.copyWith(color: AppColors.textDisabled),
      );
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
                          edited: edited.containsKey(
                            _keyOf(photos[start + col]),
                          ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...rows,
        if (selected != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _DescriptionPanel(
            photo: selected,
            edited: edited.containsKey(_keyOf(selected)),
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
                  border: Border.all(color: AppColors.ink, width: 3),
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
    if (status != PhotoAnalysisStatus.completed && !failed) {
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
          const _PanelNotice(
            'AI가 설명을 만들지 못했어요. 직접 적어주셔도 돼요.',
            danger: true,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        AppTextField(
          label: fromAi ? 'AI가 만든 설명' : '사진에 대한 설명',
          controller: controller,
          maxLines: null,
          hintText: '어떤 사진인지 적어주세요',
          // 저장된 설명을 지웠을 때만 알린다. 처음부터 빈칸이면 오류가 아니다.
          errorText: text.isEmpty && current.isNotEmpty
              ? '설명을 비워둘 수 없어요.'
              : null,
          onChanged: (_) => onChanged(),
        ),
        if (fromAi || edited) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            fromAi
                ? 'AI가 사진을 보고 만든 설명이에요. 사실과 다르면 고쳐주세요.'
                : '직접 적은 설명이에요. 다시 고칠 수 있어요.',
            style: AppTypography.caption,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(
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
          color: AppColors.surface,
          child: Icon(Icons.broken_image_outlined, color: AppColors.textDisabled),
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
