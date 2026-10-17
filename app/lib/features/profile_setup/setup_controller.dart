import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../data/card_api.dart';
import '../../data/models.dart';
import '../../data/profile_api.dart';
import '../../data/providers.dart';
import '../auth/auth_providers.dart';
import '../life_story/life_story_providers.dart';
import '../profile/photo_description_store.dart';
import '../visit/visit_camera.dart';
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

  /// 이름은 50자 이하다(`data-contracts.md` 의 Profile).
  static const maxNameLength = 50;

  bool get nameTooLong => name.trim().length > maxNameLength;

  bool get basicInfoFilled =>
      name.trim().isNotEmpty &&
      !nameTooLong &&
      gender != null &&
      birthYear != null &&
      birthMonth != null &&
      birthDay != null &&
      stage != null;

  /// 등록을 마친 분의 기본 정보로 채운다. 프로필 설정에서 고칠 때 쓴다.
  factory SetupDraft.fromBasicInfo(EnteredBasicInfo info) {
    final birth = DateTime.parse(info.birthDate);
    return SetupDraft(
      name: info.name,
      gender: info.gender,
      birthYear: birth.year,
      birthMonth: birth.month,
      birthDay: birth.day,
      stage: info.stage,
    );
  }

  /// 기본 정보를 저장할 모양으로 바꾼다. 다 채우지 않았으면 `null` 이다.
  EnteredBasicInfo? toBasicInfo() {
    if (!basicInfoFilled) return null;
    String two(int value) => value.toString().padLeft(2, '0');
    return EnteredBasicInfo(
      name: name.trim(),
      gender: gender!,
      birthDate: '$birthYear-${two(birthMonth!)}-${two(birthDay!)}',
      stage: stage!,
    );
  }

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
  const SetupState({
    this.stepIndex = 0,
    this.draft = const SetupDraft(),
    this.reachedIndex = 0,
    this.remoteId,
  });

  /// 서버에서 불러온 입력 중인 분을 이어서 입력할 때 쓴다. 서버에 저장된 기본
  /// 정보와 세부 정보로 채우고, 기본 정보는 이미 마쳤으므로 세부 정보부터 연다.
  factory SetupState.resumeOf(CareProfileEntry entry) {
    final info = entry.basicInfo;
    if (info == null) return SetupState(remoteId: entry.remoteId);
    return SetupState(
      draft: SetupDraft.fromBasicInfo(info).copyWith(
        facts: {
          for (final step in lifeFactSteps)
            step.category: ?entry.details.of(step.category),
        },
      ),
      reachedIndex: 1,
      remoteId: entry.remoteId,
    );
  }

  /// 기본 정보를 마칠 때 서버가 만든 `profileId`(2-2). 로그인 없이 들어왔거나
  /// 아직 기본 정보를 마치지 않았으면 `null` 이다. 있으면 다시 만들지 않고
  /// 고친다(2-4).
  final String? remoteId;

  /// 0 = 기본 정보, 1 ~ 4 = 생애 정보, 5 = 사진.
  final int stepIndex;
  final SetupDraft draft;

  /// 지금까지 가 본 가장 먼 단계. 화면을 나가려면 뒤로 가기로 기본 정보까지
  /// 돌아와야 하므로, 나갈 때의 [stepIndex] 는 늘 0 이다. 이어서 입력할 때는
  /// 이 값으로 연다.
  final int reachedIndex;

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

  /// 이어서 입력할 때 열 단계. 가 본 가장 먼 단계지만, 기본 정보를 비웠으면
  /// 마칠 수 없으므로 기본 정보부터 연다.
  int get resumeIndex {
    if (!draft.basicInfoFilled) return 0;
    return math.min(math.max(stepIndex, reachedIndex), _photoIndex);
  }

  SetupState copyWith({int? stepIndex, SetupDraft? draft, String? remoteId}) {
    final step = stepIndex ?? this.stepIndex;
    return SetupState(
      stepIndex: step,
      draft: draft ?? this.draft,
      reachedIndex: math.max(reachedIndex, step),
      remoteId: remoteId ?? this.remoteId,
    );
  }
}

const lifeFactStepCount = 4;

class SetupController extends Notifier<SetupState> {
  @override
  SetupState build() => const SetupState();

  void updateDraft(SetupDraft draft) => state = state.copyWith(draft: draft);

  /// 로그인 세션이 있으면 서버에 저장한다. 없으면(임시 건너뛰기) 앱 안에만 둔다.
  bool get _online => ref.read(sessionProvider) != null;

  /// 기본 정보를 마치고 다음 단계로 간다.
  ///
  /// 로그인했으면 서버에 프로필을 만든다(2-2). 이미 만들었으면 고친다(2-4).
  /// 실패하면 [ApiFailure] 를 던지고 이 단계에 남는다. [addingId] 는 어르신을
  /// 더 등록하는 `입력 중` 슬롯이다.
  Future<void> submitBasicInfo({String? addingId}) async {
    final info = state.draft.toBasicInfo();
    if (info == null) return;
    if (_online) {
      final api = ref.read(profileApiProvider);
      final id = state.remoteId;
      final saved = id == null
          ? await api.create(info)
          : await api.updateBasicInfo(id, info);
      if (!ref.mounted) return;
      state = state.copyWith(remoteId: saved.profileId);
      if (addingId != null) {
        ref
            .read(careProfilesProvider.notifier)
            .attachRemote(addingId, saved.profileId);
      }
    }
    next();
  }

  /// 입력 중이던 분의 입력을 가 본 가장 먼 단계부터 다시 연다
  /// ([SetupState.resumeIndex]). 앞 단계로는 뒤로 가기로 돌아갈 수 있다.
  void restore(SetupState saved) =>
      state = saved.copyWith(stepIndex: saved.resumeIndex);

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

  /// 입력을 마친다. 입력한 어르신을 목록에 넣고 그 분으로 바꾼다.
  ///
  /// 회원가입에서 온 첫 입력이면 목록을 이 분으로 시작한다. [addingId] 가
  /// 있으면 그 `입력 중` 슬롯을 등록을 마친 분으로 채운다. 기본 정보와 세부
  /// 정보 네 항목을 넘긴다. 사진은 아직 넘기지 않는다.
  ///
  /// 로그인했으면 세부 정보 네 항목을 서버에 저장한 뒤(2-4) 목록에 넣는다.
  /// 실패하면 [ApiFailure] 를 던지고 목록은 그대로다.
  ///
  /// 세부 정보를 저장하면 첫 카드 생성(4-1)을 요청한다. 서버는 이 요청이
  /// 있어야 등록을 마친 것(`completed`)으로 센다. 요청이 실패해도 등록은
  /// 마친다. 카드 화면에 들어가면 상태(4-2)를 보고 다시 요청한다.
  Future<void> finish({String? addingId}) async {
    final draft = state.draft;
    final info = draft.toBasicInfo();
    if (info == null) return;
    var remoteId = state.remoteId;
    if (_online) {
      final api = ref.read(profileApiProvider);
      // 기본 정보에서 저장하지 못한 채로 왔으면 지금 만든다.
      remoteId ??= (await api.create(info)).profileId;
      await api.updateDetails(remoteId, EnteredDetails.fromFacts(draft.facts));
      if (!ref.mounted) return;
      try {
        await ref.read(cardApiProvider).requestGeneration(remoteId);
      } on ApiFailure {
        // 카드 화면이 다시 요청한다.
      }
      if (!ref.mounted) return;
    }
    final details = EnteredDetails.fromFacts(draft.facts);
    final profiles = ref.read(careProfilesProvider.notifier);
    if (addingId == null) {
      profiles.startWith(info, details: details, remoteId: remoteId);
      return;
    }
    profiles.completeAdding(
      addingId,
      info,
      details: details,
      remoteId: remoteId,
    );
    ref.read(pendingSetupsProvider.notifier).remove(addingId);
  }
}

final setupControllerProvider = NotifierProvider<SetupController, SetupState>(
  SetupController.new,
);

/// `입력 중` 인 분마다 입력하던 값과 단계다.
///
/// 입력 화면은 한 번에 한 분만 다루므로, 화면을 떠나도 그 분의 입력이 남도록
/// 여기에 옮겨 둔다. 다시 열면 [SetupController.restore] 로 되살린다.
/// 앱이 켜져 있는 동안만 기억한다.
class PendingSetups extends Notifier<Map<String, SetupState>> {
  @override
  Map<String, SetupState> build() => const {};

  void save(String id, SetupState setup) => state = {...state, id: setup};

  void remove(String id) => state = {...state}..remove(id);
}

final pendingSetupsProvider =
    NotifierProvider<PendingSetups, Map<String, SetupState>>(PendingSetups.new);

/// 앱만 기억하던 어르신 정보와 입력값을 지운다. 로그아웃과 탈퇴 뒤에 부른다.
///
/// 같은 휴대폰으로 다른 사람이 로그인해도 앞사람의 어르신 정보가 보이지 않게
/// 한다. 어르신 번호는 다시 1 부터 매겨지므로, 어르신마다 고친 사진 설명과
/// 일대기에서 바꾼 이야기도 함께 지워야 다음 사람의 같은 번호 어르신에 남지
/// 않는다. 찍어 두고 올리지 않은 면회 사진도 기기에서 지운다.
void forgetCareProfiles(WidgetRef ref) {
  ref
    ..invalidate(careProfilesProvider)
    ..invalidate(setupControllerProvider)
    ..invalidate(pendingSetupsProvider)
    ..invalidate(editedPhotoDescriptionsProvider)
    ..invalidate(lifeStoryEditsProvider)
    ..invalidate(visitPhotoProvider);
}
