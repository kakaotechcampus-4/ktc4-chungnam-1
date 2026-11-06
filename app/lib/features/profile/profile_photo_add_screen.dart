import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
import '../profile_setup/photo_picker.dart';
import '../profile_setup/photo_steps.dart';
import '../profile_setup/photo_uploader.dart';

/// 등록을 마친 어르신의 사진을 더 올리는 동안의 사진 목록이다.
///
/// 입력 흐름의 사진 단계와 같은 규칙을 따른다. 올리는 중에는 더하거나 빼지
/// 않고, 서버에 올라간 사진은 지울 API 가 없어 빼지 않는다. 화면을 떠나면 잊는다.
class ProfilePhotoAddController extends Notifier<List<SetupPhoto>> {
  @override
  List<SetupPhoto> build() => const [];

  bool get isUploading =>
      state.any((photo) => photo.status == PhotoUploadStatus.uploading);

  bool get allUploaded =>
      state.isNotEmpty &&
      state.every((photo) => photo.status == PhotoUploadStatus.uploaded);

  bool get hasFailed =>
      state.any((photo) => photo.status == PhotoUploadStatus.failed);

  /// 고른 사진을 뒤에 붙인다. 화면이 남은 장수만큼만 고르게 한다.
  void add(List<PickedPhoto> picked) {
    if (isUploading) return;
    state = [...state, for (final photo in picked) SetupPhoto(photo)];
  }

  void remove(int index) {
    if (isUploading) return;
    if (state[index].status == PhotoUploadStatus.uploaded) return;
    state = [...state]..removeAt(index);
  }

  /// 아직 올리지 못한 사진을 지금 어르신의 프로필(3-1)에 차례로 올린다.
  ///
  /// 한 장이라도 올라가면 갤러리가 서버의 사진(2-3)을 다시 읽게 한다.
  Future<void> upload() async {
    if (isUploading) return;
    final profileId = ref.read(careProfilesProvider).selected?.remoteId;
    var uploaded = false;
    await uploadPendingPhotos(
      uploader: ref.read(photoUploaderProvider),
      profileId: profileId,
      current: () => state,
      update: (index, photo) {
        if (photo.status == PhotoUploadStatus.uploaded) uploaded = true;
        state = [...state]..[index] = photo;
      },
      active: () => ref.mounted,
    );
    if (uploaded && ref.mounted) ref.invalidate(serverProfilePhotosProvider);
  }

  /// 올리지 못한 사진을 뺀다.
  void dropFailed() {
    if (isUploading) return;
    state = state
        .where((photo) => photo.status != PhotoUploadStatus.failed)
        .toList();
  }
}

final profilePhotoAddProvider =
    NotifierProvider.autoDispose<ProfilePhotoAddController, List<SetupPhoto>>(
      ProfilePhotoAddController.new,
    );

/// 등록을 마친 뒤 프로필 설정의 갤러리에서 사진을 더 올린다. 피그마 설계가 없어
/// 입력 흐름의 사진 단계(B-7) 화면을 그대로 쓴다.
///
/// [existing] 은 이미 서버에 올린 사진 수다. 합쳐 [maxProfilePhotos] 장까지
/// 고르게 한다. 그래도 서버가 거절하면(`PHOTO_LIMIT_EXCEEDED`) 그 이유를 알린다.
/// 다 올리면 갤러리로 돌아가는 버튼을 둔다. 완료를 보고 직접 돌아가도록 저절로
/// 옮기지 않는다.
class ProfilePhotoAddScreen extends ConsumerWidget {
  const ProfilePhotoAddScreen({required this.existing, super.key});

  final int existing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos = ref.watch(profilePhotoAddProvider);
    final controller = ref.read(profilePhotoAddProvider.notifier);
    final uploading = controller.isUploading;

    return PopScope(
      // 올리는 중에 떠나면 몇 장이 올라갔는지 알 수 없게 된다.
      canPop: !uploading,
      child: Scaffold(
        appBar: AppTopBar(showBack: !uploading),
        body: ScreenBody(
          scrollable: true,
          bottom: _Actions(controller: controller, photos: photos),
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xl),
            child: PhotoUploadStep(
              photos: photos,
              existing: existing,
              canEdit: !uploading,
              onAdded: controller.add,
              onRemoved: controller.remove,
            ),
          ),
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.controller, required this.photos});

  final ProfilePhotoAddController controller;

  /// 상태가 바뀔 때 다시 그리도록 받는다.
  final List<SetupPhoto> photos;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      return const PrimaryButton(label: '올릴 사진을 골라주세요', onPressed: null);
    }
    if (controller.isUploading) {
      return const PrimaryButton(label: '올리는 중이에요', onPressed: null);
    }
    if (controller.allUploaded) {
      return PrimaryButton(label: '갤러리로 돌아가기', onPressed: context.pop);
    }
    if (controller.hasFailed) {
      final retryable = photos.any(
        (photo) =>
            photo.status == PhotoUploadStatus.waiting ||
            (photo.failure?.retryable ?? false),
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (retryable) ...[
            PrimaryButton(label: '다시 올리기', onPressed: controller.upload),
            const SizedBox(height: AppSpacing.sm),
          ],
          SecondaryButton(
            label: '올리지 못한 사진은 빼고 마치기',
            onPressed: () {
              controller.dropFailed();
              context.pop();
            },
          ),
        ],
      );
    }
    return PrimaryButton(label: '마치기', onPressed: controller.upload);
  }
}
