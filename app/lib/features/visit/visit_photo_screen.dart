import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';

/// D-1 면회 전 사진 촬영.
///
/// 사진은 선택이다. 남기지 않고도 면회를 시작할 수 있다.
/// 실제 카메라 연결은 아직 붙이지 않았고 목 데이터의 사진으로 자리를 채운다.
class VisitPhotoScreen extends ConsumerStatefulWidget {
  const VisitPhotoScreen({super.key});

  @override
  ConsumerState<VisitPhotoScreen> createState() => _VisitPhotoScreenState();
}

class _VisitPhotoScreenState extends ConsumerState<VisitPhotoScreen> {
  /// 촬영 전후로 자리 크기가 같아야 화면이 튀지 않는다.
  static const _photoBoxHeight = 260.0;

  bool _captured = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppTopBar(),
      body: ScreenBody(
        scrollable: true,
        bottom: _captured
            ? PrimaryButton(
                label: '이 사진으로 시작하기',
                onPressed: () => context.push(AppRoutes.visitRecord),
              )
            : SecondaryButton(
                label: '사진 없이 시작할게요',
                onPressed: () => context.push(AppRoutes.visitRecord),
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
                child: _captured
                    ? Image.asset(
                        'assets/images/visitation.webp',
                        fit: BoxFit.cover,
                      )
                    : Container(
                        color: AppColors.surface,
                        child: const Icon(
                          Icons.photo_camera_outlined,
                          size: 48,
                          color: AppColors.textDisabled,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: AppSpacing.xxl),

            Center(
              child: Column(
                children: [
                  _ShutterButton(
                    captured: _captured,
                    onTap: () => setState(() => _captured = !_captured),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _captured ? '다시 찍기' : '눌러서 촬영하기',
                    style: AppTypography.sub,
                  ),
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

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.captured, required this.onTap});

  final bool captured;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
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
    );
  }
}
