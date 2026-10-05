import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import 'photo_picker.dart';
import 'photo_uploader.dart';
import 'setup_steps.dart';

/// 입력 흐름이 모아 둔 값이다. 화면을 오가도 유지된다.
class SetupDraft {
  const SetupDraft({
    this.name = '',
    this.gender,
    this.birthYear,
    this.birthMonth,
    this.birthDay,
    this.stage,
    this.facts = const {},
    this.photos = const [],
  });

  final String name;
  final String? gender;
  final int? birthYear;
  final int? birthMonth;
  final int? birthDay;
  final ConditionStage? stage;

  /// `LifeFact.category` 별로 모은 문장. 건너뛴 항목은 담기지 않는다.
  final Map<String, String> facts;

  /// 앨범에서 고른 사진과 각각의 업로드 상태. 최대 [maxProfilePhotos] 장이다.
  final List<SetupPhoto> photos;

  bool get hasPhoto => photos.isNotEmpty;

  bool get isUploadingPhotos =>
      photos.any((photo) => photo.status == PhotoUploadStatus.uploading);

  bool get allPhotosUploaded =>
      hasPhoto &&
      photos.every((photo) => photo.status == PhotoUploadStatus.uploaded);

  bool get hasFailedPhoto =>
      photos.any((photo) => photo.status == PhotoUploadStatus.failed);

  /// 사진을 더하거나 뺄 수 있는지. 올리는 중이거나 모두 올린 뒤에는 막는다.
  bool get canEditPhotos => !isUploadingPhotos && !allPhotosUploaded;

  bool get basicInfoFilled =>
      name.trim().isNotEmpty &&
      gender != null &&
      birthYear != null &&
      birthMonth != null &&
      birthDay != null &&
      stage != null;

  SetupDraft copyWith({
    String? name,
    String? gender,
    int? birthYear,
    int? birthMonth,
    int? birthDay,
    ConditionStage? stage,
    Map<String, String>? facts,
    List<SetupPhoto>? photos,
  }) => SetupDraft(
    name: name ?? this.name,
    gender: gender ?? this.gender,
    birthYear: birthYear ?? this.birthYear,
    birthMonth: birthMonth ?? this.birthMonth,
    birthDay: birthDay ?? this.birthDay,
    stage: stage ?? this.stage,
    facts: facts ?? this.facts,
    photos: photos ?? this.photos,
  );
}

/// 어느 단계에 있는지와 모은 값을 함께 들고 있다.
class SetupState {
  const SetupState({this.stepIndex = 0, this.draft = const SetupDraft()});

  /// 0 = 기본 정보, 1 ~ 4 = 생애 정보, 5 = 사진.
  final int stepIndex;
  final SetupDraft draft;

  static const _photoIndex = 1 + lifeFactStepCount;

  bool get isBasicInfo => stepIndex == 0;
  bool get isPhoto => stepIndex == _photoIndex;
  bool get isLifeFact => stepIndex > 0 && stepIndex < _photoIndex;

  LifeFactStep? get lifeFactStep =>
      isLifeFact ? lifeFactSteps[stepIndex - 1] : null;

  /// 진행 표시에 쓴다.
  double get progress => (stepIndex + 1) / (_photoIndex + 1);

  /// 사진이 마지막 단계다. 사진에서 태그를 고르던 단계는 없앴다.
  bool get isLast => stepIndex >= _photoIndex;

  SetupState copyWith({int? stepIndex, SetupDraft? draft}) =>
      SetupState(stepIndex: stepIndex ?? this.stepIndex, draft: draft ?? this.draft);
}

const lifeFactStepCount = 4;

class SetupController extends Notifier<SetupState> {
  @override
  SetupState build() => const SetupState();

  void updateDraft(SetupDraft draft) => state = state.copyWith(draft: draft);

  /// 다음 단계로 간다.
  ///
  /// 마지막 단계에서는 아무것도 하지 않는다. 화면이 흐름을 끝낸다.
  void next() {
    if (state.isLast) return;
    state = state.copyWith(stepIndex: state.stepIndex + 1);
  }

  /// 이전 단계로 간다. 첫 단계면 `false` 를 돌려준다.
  ///
  /// 사진을 올리는 중에는 움직이지 않는다. 화면을 벗어나면 몇 장이 올라갔는지
  /// 알 수 없게 된다.
  bool back() {
    if (state.draft.isUploadingPhotos) return true;
    if (state.stepIndex == 0) return false;
    state = state.copyWith(stepIndex: state.stepIndex - 1);
    return true;
  }

  void recordFact(String category, String text) {
    final facts = Map<String, String>.from(state.draft.facts)
      ..[category] = text;
    updateDraft(state.draft.copyWith(facts: facts));
  }

  /// 고른 사진을 뒤에 붙인다. 최대 장수를 넘는 것은 버린다.
  void addPhotos(List<PickedPhoto> picked) {
    if (!state.draft.canEditPhotos) return;
    final photos = [
      ...state.draft.photos,
      for (final photo in picked) SetupPhoto(photo),
    ].take(maxProfilePhotos);
    updateDraft(state.draft.copyWith(photos: photos.toList()));
  }

  /// 사진을 뺀다. 서버에 올라간 사진은 지울 API 가 없어 빼지 않는다.
  void removePhoto(int index) {
    if (state.draft.isUploadingPhotos) return;
    if (state.draft.photos[index].status == PhotoUploadStatus.uploaded) return;
    final photos = [...state.draft.photos]..removeAt(index);
    updateDraft(state.draft.copyWith(photos: photos));
  }

  /// 아직 올리지 못한 사진을 한 장씩 차례로 올린다.
  ///
  /// 이미 올라간 사진은 건너뛴다. 그래서 일부가 실패한 뒤 다시 부르면 실패한
  /// 사진만 다시 올린다.
  Future<void> uploadPhotos() async {
    if (state.draft.isUploadingPhotos) return;
    final uploader = ref.read(photoUploaderProvider);

    for (var i = 0; i < state.draft.photos.length; i++) {
      final photo = state.draft.photos[i];
      if (photo.status == PhotoUploadStatus.uploaded) continue;

      _setPhoto(i, photo.withStatus(PhotoUploadStatus.uploading));
      try {
        await uploader.upload(photo.picked);
        if (!ref.mounted) return;
        _setPhoto(i, photo.withStatus(PhotoUploadStatus.uploaded));
      } on PhotoUploadFailure catch (failure) {
        if (!ref.mounted) return;
        _setPhoto(
          i,
          photo.withStatus(PhotoUploadStatus.failed, failure: failure),
        );
      } catch (_) {
        if (!ref.mounted) return;
        _setPhoto(
          i,
          photo.withStatus(
            PhotoUploadStatus.failed,
            failure: const PhotoUploadFailure(
              PhotoUploadFailure.networkError,
              retryable: true,
            ),
          ),
        );
      }
    }
  }

  /// 올리지 못한 사진을 뺀다. 사진은 선택이라 실패한 사진 없이도 마칠 수 있다.
  void dropFailedPhotos() {
    if (state.draft.isUploadingPhotos) return;
    final photos = state.draft.photos
        .where((photo) => photo.status != PhotoUploadStatus.failed)
        .toList();
    updateDraft(state.draft.copyWith(photos: photos));
  }

  void _setPhoto(int index, SetupPhoto photo) {
    final photos = [...state.draft.photos]..[index] = photo;
    updateDraft(state.draft.copyWith(photos: photos));
  }

  void skipFact(String category) {
    final facts = Map<String, String>.from(state.draft.facts)..remove(category);
    updateDraft(state.draft.copyWith(facts: facts));
  }
}

final setupControllerProvider = NotifierProvider<SetupController, SetupState>(
  SetupController.new,
);
