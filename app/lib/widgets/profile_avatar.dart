import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// 어르신의 원형 프로필 사진이다.
///
/// 아직 사진을 고르는 기능이 없어 성별에 맞는 기본 사진을 쓴다. 계약상 성별은
/// `male`, `female` 둘뿐이다.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({required this.gender, required this.size, super.key});

  final String gender;
  final double size;

  @override
  Widget build(BuildContext context) {
    // 사진의 투명한 바탕이 회색 면 위에서 비치지 않게 흰 원을 먼저 깐다.
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: AppColors.background,
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: Image.asset(
          gender == 'female'
              ? 'assets/images/patient-female.webp'
              : 'assets/images/patient-male.webp',
          width: size,
          height: size,
          fit: BoxFit.cover,
          // 옆에 이름이 함께 놓인다.
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}
