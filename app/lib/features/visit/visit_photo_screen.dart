import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
import 'visit_camera.dart';

/// D-1 면회 전 사진 촬영.
///
/// 사진은 선택이다. 남기지 않고도 면회를 시작할 수 있다. 찍은 사진은
/// [visitPhotoProvider] 에 기기 안 경로로만 들고 있다. 서버 업로드(5-2)는
/// 회차가 만들어진 뒤에 한다.
class VisitPhotoScreen extends ConsumerStatefulWidget {
  const VisitPhotoScreen({super.key});

  @override
  ConsumerState<VisitPhotoScreen> createState() => _VisitPhotoScreenState();
}

class _VisitPhotoScreenState extends ConsumerState<VisitPhotoScreen> {
  /// 촬영 전후로 자리 크기가 같아야 화면이 튀지 않는다.
  static const _photoBoxHeight = 260.0;

  /// 카메라가 열려 있는 동안 셔터를 다시 누르지 못하게 한다.
  bool _capturing = false;

  /// 카메라를 열지 못했는지. 다시 누르면 지운다.
  bool _cameraFailed = false;

  Future<void> _capture() async {
    setState(() {
      _capturing = true;
      _cameraFailed = false;
    });
    try {
      final path = await ref.read(visitCameraProvider).capture();
      // 찍지 않고 나오면 앞에 찍은 사진을 그대로 둔다.
      if (path != null) {
        await ref.read(visitPhotoProvider.notifier).replace(path);
      }
    } on VisitCameraUnavailable {
      if (mounted) setState(() => _cameraFailed = true);
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photoPath = ref.watch(visitPhotoProvider);
    final captured = photoPath != null;

    return Scaffold(
      appBar: const AppTopBar(),
      body: ScreenBody(
        scrollable: true,
        bottom: captured
            ? PrimaryButton(
                label: '이 사진으로 시작하기',
                onPressed: _capturing
                    ? null
                    : () => context.push(AppRoutes.visitRecord),
              )
            : SecondaryButton(
                label: '사진 없이 시작할게요',
                onPressed: _capturing
                    ? null
                    : () => context.push(AppRoutes.visitRecord),
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(flex: 2),
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
            const Spacer(flex: 2),

            SizedBox(
              height: _photoBoxHeight,
              width: double.infinity,
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

            const SizedBox(height: AppSpacing.xxl),

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
                  if (_cameraFailed) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      '카메라를 열지 못했어요.\n사진 없이 시작해도 괜찮아요.',
                      style: AppTypography.sub.copyWith(
                        color: AppColors.danger,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),

            const Spacer(flex: 3),
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
      child: Icon(icon, size: 48, color: AppColors.textDisabled),
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
            border: Border.all(color: AppColors.ink, width: 2),
          ),
          child: Center(
            child: captured
                ? const Icon(Icons.refresh, size: 32, color: AppColors.ink)
                : Container(
                    width: 60,
                    height: 60,
                    decoration: const BoxDecoration(
                      color: AppColors.ink,
                      shape: BoxShape.circle,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
