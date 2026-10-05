import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/tokens.dart';
import 'photo_picker.dart';

/// B-7 사진 올리기. 선택 항목이며 최대 [maxProfilePhotos] 장을 받는다.
///
/// 기기 앨범에서 고르고, 고른 사진은 X 로 뺄 수 있다. 이 단계에서는 아직 서버에
/// 올리지 않으므로 빼도 남는 것이 없다.
class PhotoUploadStep extends ConsumerStatefulWidget {
  const PhotoUploadStep({
    required this.photos,
    required this.onAdded,
    required this.onRemoved,
    super.key,
  });

  final List<PickedPhoto> photos;
  final ValueChanged<List<PickedPhoto>> onAdded;
  final ValueChanged<int> onRemoved;

  @override
  ConsumerState<PhotoUploadStep> createState() => _PhotoUploadStepState();
}

class _PhotoUploadStepState extends ConsumerState<PhotoUploadStep> {
  /// 앨범이 열려 있다. 두 번 열지 않는다.
  bool _picking = false;

  String? _notice;

  int get _remaining => maxProfilePhotos - widget.photos.length;

  Future<void> _pick() async {
    if (_picking || _remaining < 1) return;
    setState(() {
      _picking = true;
      _notice = null;
    });

    final remaining = _remaining;
    try {
      final picked = await ref
          .read(photoPickerProvider)
          .pick(limit: remaining);
      if (!mounted) return;

      // 기기에 따라 개수 제한이 걸리지 않을 수 있어 여기서 한 번 더 자른다.
      final kept = picked.take(remaining).toList();
      final dropped = picked.length - kept.length;
      setState(() {
        _picking = false;
        if (dropped > 0) {
          _notice =
              '사진은 $maxProfilePhotos장까지 올릴 수 있어요. $dropped장은 빼고 담았어요.';
        }
      });
      if (kept.isNotEmpty) widget.onAdded(kept);
    } on PlatformException {
      // 앨범 접근이 막혔거나 기기가 사진을 넘겨주지 못했다.
      if (!mounted) return;
      setState(() {
        _picking = false;
        _notice = '사진을 불러오지 못했어요. 다시 시도해주세요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    final notice = _notice;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(flex: 2),
        const Text(
          '어르신과 관련된 사진을\n올려주세요',
          style: AppTypography.screenTitle,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.lg),
        const Text(
          '최대 $maxProfilePhotos장까지 올릴 수 있어요. 넣지 않으셔도 괜찮아요.',
          style: AppTypography.sub,
          textAlign: TextAlign.center,
        ),
        const Spacer(flex: 2),

        if (photos.isEmpty)
          _EmptyPicker(onTap: _picking ? null : _pick)
        else ...[
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${photos.length}/$maxProfilePhotos',
              style: AppTypography.sub,
              semanticsLabel:
                  '$maxProfilePhotos장 중 ${photos.length}장을 골랐어요',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _PhotoGrid(
            photos: photos,
            onAdd: _remaining > 0 && !_picking ? _pick : null,
            showAdd: _remaining > 0,
            onRemove: (index) {
              setState(() => _notice = null);
              widget.onRemoved(index);
            },
          ),
        ],

        if (notice != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            notice,
            style: AppTypography.sub.copyWith(color: AppColors.danger),
            textAlign: TextAlign.center,
          ),
        ],

        const Spacer(flex: 3),
      ],
    );
  }
}

/// 아직 한 장도 고르지 않았을 때의 큰 추가 자리다.
class _EmptyPicker extends StatelessWidget {
  const _EmptyPicker({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.image),
      child: Container(
        height: 260,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.image),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_photo_alternate_outlined,
              size: 44,
              color: AppColors.textDisabled,
            ),
            SizedBox(height: AppSpacing.md),
            Text('사진 추가하기', style: AppTypography.sub),
          ],
        ),
      ),
    );
  }
}

/// 고른 사진과 추가 칸을 세 칸씩 놓는다.
///
/// 이 단계는 `IntrinsicHeight` 안에 놓이므로 `GridView` 대신 줄을 직접 짠다.
class _PhotoGrid extends StatelessWidget {
  const _PhotoGrid({
    required this.photos,
    required this.onAdd,
    required this.showAdd,
    required this.onRemove,
  });

  static const _columns = 3;

  final List<PickedPhoto> photos;
  final VoidCallback? onAdd;
  final bool showAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      for (var i = 0; i < photos.length; i++)
        _PhotoTile(
          photo: photos[i],
          number: i + 1,
          onRemove: () => onRemove(i),
        ),
      if (showAdd) _AddTile(onTap: onAdd),
    ];

    final rows = <Widget>[];
    for (var start = 0; start < tiles.length; start += _columns) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: AppSpacing.sm));
      rows.add(
        Row(
          children: [
            for (var col = 0; col < _columns; col++) ...[
              if (col > 0) const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: start + col < tiles.length
                      ? tiles[start + col]
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Column(children: rows);
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.photo,
    required this.number,
    required this.onRemove,
  });

  final PickedPhoto photo;
  final int number;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.image),
          child: Image.file(
            File(photo.path),
            fit: BoxFit.cover,
            semanticLabel: '고른 사진 $number',
            // 파일을 읽지 못해도 칸은 남겨 X 로 뺄 수 있게 한다.
            errorBuilder: (context, error, stackTrace) => const ColoredBox(
              color: AppColors.surface,
              child: Icon(
                Icons.broken_image_outlined,
                color: AppColors.textDisabled,
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: IconButton(
            onPressed: onRemove,
            tooltip: '사진 $number 빼기',
            constraints: const BoxConstraints(
              minWidth: AppSizes.minTouch,
              minHeight: AppSizes.minTouch,
            ),
            icon: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.ink.withValues(alpha: 0.7),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close,
                size: 18,
                color: AppColors.background,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '사진 추가하기',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.image),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.image),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_photo_alternate_outlined,
                size: 32,
                color: AppColors.textDisabled,
              ),
              SizedBox(height: AppSpacing.xs),
              Text('추가', style: AppTypography.caption),
            ],
          ),
        ),
      ),
    );
  }
}
