import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/tokens.dart';
import '../features/local_photos/local_photos.dart';

/// 어르신의 원형 프로필 사진이다.
///
/// 보호자가 프로필 설정에서 고른 사진이 있으면 그것을 쓴다. 이 기기에만 둔
/// 사진이다([LocalPhotos]). 없거나 읽지 못하면 성별에 맞는 기본 사진을 쓴다.
/// 계약상 성별은 `male`, `female` 둘뿐이다.
class ProfileAvatar extends ConsumerWidget {
  const ProfileAvatar({
    required this.gender,
    required this.size,
    this.profileId,
    super.key,
  });

  final String gender;
  final double size;

  /// 고른 사진을 찾을 어르신. `null` 이면 늘 기본 사진이다(입력 중인 분).
  final String? profileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photo = profileId == null
        ? null
        : ref.watch(
            localPhotoPathProvider(
              localPhotoKey(profileId!, LocalPhotoSlot.avatar),
            ),
          );
    final fallback = Image.asset(
      gender == 'female'
          ? 'assets/images/patient-female.webp'
          : 'assets/images/patient-male.webp',
      width: size,
      height: size,
      fit: BoxFit.cover,
      // 옆에 이름이 함께 놓인다.
      excludeFromSemantics: true,
    );

    // 사진의 투명한 바탕이 회색 면 위에서 비치지 않게 흰 원을 먼저 깐다.
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: AppColors.background,
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: photo == null
            ? fallback
            : Image.file(
                File(photo),
                width: size,
                height: size,
                fit: BoxFit.cover,
                // 앨범 사진은 크다. 원 크기에 맞춰 줄여 풀어 기억을 아낀다.
                // 가로 사진도 높이가 모자라 흐려지지 않게 폭을 두 배로 둔다.
                cacheWidth: (size * 2 * MediaQuery.devicePixelRatioOf(context))
                    .round(),
                excludeFromSemantics: true,
                errorBuilder: (context, error, stackTrace) => fallback,
              ),
      ),
    );
  }
}
