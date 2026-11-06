import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
import 'visit_camera.dart';
import 'visit_gallery.dart';

/// D-1 면회 전 사진 촬영.
///
/// 사진은 선택이다. 남기지 않고도 면회를 시작할 수 있다. 찍은 사진은 원본을
/// 갤러리에 남기고([VisitGallery]), 사본을 [visitPhotoProvider] 에 기기 안
/// 경로로 들고 있다. 서버 업로드(5-2)는 회차가 만들어진 뒤에 한다.
class VisitPhotoScreen extends ConsumerStatefulWidget {
  const VisitPhotoScreen({super.key});

  @override
  ConsumerState<VisitPhotoScreen> createState() => _VisitPhotoScreenState();
}

class _VisitPhotoScreenState extends ConsumerState<VisitPhotoScreen> {
  /// 촬영 전후로 자리 크기가 같아야 화면이 튀지 않는다.
  static const _photoBoxHeight = 210.0;

  /// 사진 자리의 가장 큰 폭. 4:3 에 가깝게 둔다.
  static const _photoBoxWidth = 280.0;

  /// 카메라가 열려 있는 동안 셔터를 다시 누르지 못하게 한다.
  bool _capturing = false;

  /// 찍지 못한 이유를 알리는 문구. 다시 누르면 지운다.
  String? _problem;

  Future<void> _capture() async {
    setState(() {
      _capturing = true;
      _problem = null;
    });
    // 카메라가 열린 사이 화면을 떠나도 찍은 사진을 갤러리에 남기도록 미리 잡아 둔다.
    final gallery = ref.read(visitGalleryProvider);
    try {
      final path = await ref.read(visitCameraProvider).capture();
      // 찍지 않고 나오면 앞에 찍은 사진을 그대로 둔다.
      if (path == null) return;

      // 원본을 먼저 갤러리에 남긴다. 화면을 떠났어도 보호자의 사진이다.
      final inGallery = await gallery.save(path);
      // 화면을 떠났으면 이번 면회에 쓰지 않는다.
      if (!mounted) return;
      await ref
          .read(visitPhotoProvider.notifier)
          .replace(path, inGallery: inGallery);
      if (!inGallery && mounted) {
        setState(() => _problem = '사진을 갤러리에 저장하지 못했어요.\n리포트에는 그대로 담아요.');
      }
    } on VisitCameraUnavailable {
      if (mounted) {
        setState(() => _problem = '카메라를 열지 못했어요.\n사진 없이 시작해도 괜찮아요.');
      }
    } on FileSystemException {
      if (mounted) {
        setState(() => _problem = '사진을 저장하지 못했어요.\n다시 찍거나 사진 없이 시작해도 괜찮아요.');
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photoPath = ref.watch(visitPhotoProvider);
    final captured = photoPath != null;

    // 홈과 같은 세이지 색감이다(`HomeColors`).
    return Scaffold(
      backgroundColor: HomeColors.background,
      appBar: const AppTopBar(backgroundColor: HomeColors.background),
      body: ScreenBody(
        scrollable: true,
        bottom: captured
            ? PrimaryButton(
                label: '이 사진으로 시작하기',
                color: HomeColors.accent,
                loadingColor: HomeColors.accentLoading,
                onPressed: _capturing
                    ? null
                    : () => context.push(AppRoutes.visitRecord),
              )
            : SecondaryButton(
                label: '사진 없이 시작할게요',
                // 오프화이트 바탕에서 보이도록 진한 테두리다.
                borderColor: HomeColors.outline,
                onPressed: _capturing
                    ? null
                    : () => context.push(AppRoutes.visitRecord),
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 녹음 안내 화면의 제목과 같은 자리다.
            const SizedBox(height: AppSpacing.visitTitleTop),
            const Text(
              '오늘의 만남 사진을\n한 장 남겨볼까요?',
              style: AppTypography.screenTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              '리포트에 함께 담아드려요.',
              style: AppTypography.sub,
              textAlign: TextAlign.center,
            ),
            // 안내 글과 사진 자리 사이, 사진 자리와 셔터 사이를 같게(64) 둔다.
            const SizedBox(height: AppSpacing.xxl * 2),

            Center(
              child: Container(
                height: _photoBoxHeight,
                width: _photoBoxWidth,
                // 회색 칸이 오프화이트 바탕에 묻히지 않게 테두리를 둔다. 사진을
                // 찍은 뒤에도 같은 테두리다.
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.image),
                  border: Border.all(color: HomeColors.outline),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.image),
                  child: captured
                      ? Image.file(
                          File(photoPath),
                          fit: BoxFit.cover,
                          semanticLabel: '찍은 면회 사진',
                          errorBuilder: (context, error, stackTrace) =>
                              const _PhotoPlaceholder(
                                icon: Icons.broken_image_outlined,
                              ),
                        )
                      : const _PhotoPlaceholder(
                          icon: Icons.photo_camera_outlined,
                        ),
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.xxl * 2),

            Center(
              child: Column(
                children: [
                  _ShutterButton(
                    captured: captured,
                    onTap: _capturing ? null : _capture,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    captured ? '다시 찍기' : '눌러서 촬영하기',
                    style: AppTypography.sub,
                  ),
                  if (_problem case final problem?) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      problem,
                      style: AppTypography.sub.copyWith(
                        color: AppColors.danger,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),

            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: Icon(icon, size: 48, color: HomeColors.accent),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.captured, required this.onTap});

  final bool captured;

  /// `null` 이면 카메라가 열려 있는 중이라 누를 수 없다.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: captured ? '사진 다시 찍기' : '사진 찍기',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: HomeColors.accent, width: 2),
          ),
          child: Center(
            child: captured
                ? const Icon(Icons.refresh, size: 32, color: HomeColors.accent)
                : Container(
                    width: 60,
                    height: 60,
                    decoration: const BoxDecoration(
                      color: HomeColors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
