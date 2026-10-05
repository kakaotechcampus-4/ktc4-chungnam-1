import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
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
    this.hasPhoto = false,
  });

  final String name;
  final String? gender;
  final int? birthYear;
  final int? birthMonth;
  final int? birthDay;
  final ConditionStage? stage;

  /// `LifeFact.category` 별로 모은 문장. 건너뛴 항목은 담기지 않는다.
  final Map<String, String> facts;

  final bool hasPhoto;

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
    bool? hasPhoto,
  }) => SetupDraft(
    name: name ?? this.name,
    gender: gender ?? this.gender,
    birthYear: birthYear ?? this.birthYear,
    birthMonth: birthMonth ?? this.birthMonth,
    birthDay: birthDay ?? this.birthDay,
    stage: stage ?? this.stage,
    facts: facts ?? this.facts,
    hasPhoto: hasPhoto ?? this.hasPhoto,
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
  bool back() {
    if (state.stepIndex == 0) return false;
    state = state.copyWith(stepIndex: state.stepIndex - 1);
    return true;
  }

  void recordFact(String category, String text) {
    final facts = Map<String, String>.from(state.draft.facts)
      ..[category] = text;
    updateDraft(state.draft.copyWith(facts: facts));
  }

  void skipFact(String category) {
    final facts = Map<String, String>.from(state.draft.facts)..remove(category);
    updateDraft(state.draft.copyWith(facts: facts));
  }
}

final setupControllerProvider = NotifierProvider<SetupController, SetupState>(
  SetupController.new,
);
