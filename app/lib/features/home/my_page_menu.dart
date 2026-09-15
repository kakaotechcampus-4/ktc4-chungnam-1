import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../design/tokens.dart';

/// 하단 탭의 `마이페이지` 를 누르면 뜨는 메뉴다.
///
/// 이 탭은 화면으로 바로 가지 않고 두 곳으로 갈라진다. 프로필 설정과 리포트
/// 기록이다.
Future<void> showMyPageMenu(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.background,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MenuRow(
              icon: Icons.person_outline,
              label: '프로필 설정',
              detail: '어르신 정보와 사진을 확인해요',
              onTap: () {
                Navigator.pop(sheetContext);
                context.push(AppRoutes.profile);
              },
            ),
            const Divider(indent: AppSpacing.screen, endIndent: AppSpacing.screen),
            _MenuRow(
              icon: Icons.description_outlined,
              label: '리포트 기록',
              detail: '지난 면회 리포트를 다시 볼 수 있어요',
              onTap: () {
                Navigator.pop(sheetContext);
                context.push(AppRoutes.reports);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screen,
          vertical: AppSpacing.lg,
        ),
        child: Row(
          children: [
            Icon(icon, size: 26, color: AppColors.ink),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTypography.bodyStrong),
                  const SizedBox(height: AppSpacing.xs),
                  Text(detail, style: AppTypography.sub),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSub),
          ],
        ),
      ),
    );
  }
}
