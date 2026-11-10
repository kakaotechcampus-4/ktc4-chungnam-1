/// 화면은 이 provider 들만 본다. 목 데이터인지 서버 응답인지 알지 못한다.
///
/// 데이터 출처를 바꿀 때는 `mockRepositoryProvider` 를 override 한다.
/// 테스트에서 다른 값을 주입할 때도 같은 방법을 쓴다. `ADR-005` 참고.
/// 대화 카드는 서버에서 받으므로 `currentCardSetProvider` 를 override 한다.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_providers.dart';
import 'account_api.dart';
import 'api_client.dart';
import 'card_api.dart';
import 'mock_repository.dart';
import 'models.dart';
import 'profile_api.dart';
import 'profile_birth_input_store.dart';
import 'profile_relationship_store.dart';
import 'report_api.dart';
import 'selected_profile_store.dart';

final mockRepositoryProvider = Provider<MockRepository>(
  (ref) => const MockRepository(),
);

/// 로그인한 계정과 가장 최근 동의 이력(1-3). 로그인하지 않았으면 목 계정이다.
///
/// 계정이 바뀌면 다시 읽는다.
final accountProvider = FutureProvider<Account>((ref) {
  final accountId = ref.watch(
    sessionProvider.select((s) => s?.account.accountId),
  );
  if (accountId == null) {
    return ref.watch(mockRepositoryProvider).loadAccount();
  }
  return ref.watch(accountApiProvider).me();
});

/// 환자 정보 입력에서 받은 기본 정보다.
class EnteredBasicInfo {
  const EnteredBasicInfo({
    required this.name,
    required this.gender,
    required this.birthDate,
    required this.stage,
    this.relationship,
    this.birthByAge = false,
  });

  final String name;

  /// `male` 또는 `female`.
  final String gender;

  /// 보호자와의 관계. "어머니", "아버지"처럼 보호자가 적는 선택 항목이다.
  /// 앱에서 부를 때만 쓰는 별명이라 서버에 보내지 않고 단말에만 둔다
  /// ([ProfileRelationshipStore]). 적지 않았으면 `null` 이다.
  final String? relationship;

  /// 관계만 바꾼 값이다. 서버 응답에는 관계가 없어 단말의 값을 붙일 때 쓴다.
  EnteredBasicInfo withRelationship(String? relationship) => EnteredBasicInfo(
    name: name,
    gender: gender,
    birthDate: birthDate,
    stage: stage,
    relationship: relationship,
    birthByAge: birthByAge,
  );

  /// 나이로 입력했는지만 바꾼 값이다. 서버 응답에는 이 표시가 없어 단말의 값을
  /// 붙일 때 쓴다.
  EnteredBasicInfo withBirthByAge(bool birthByAge) => EnteredBasicInfo(
    name: name,
    gender: gender,
    birthDate: birthDate,
    stage: stage,
    relationship: relationship,
    birthByAge: birthByAge,
  );

  /// `YYYY-MM-DD`. 나이로 입력했으면 오늘에서 그 나이만큼 뺀 날이다
  /// (`birth_date.dart`).
  final String birthDate;

  /// 생년월일 대신 나이로 입력했는지. 서버에 보내지 않고 단말에만 둔다
  /// ([ProfileBirthInputStore]). 화면은 날짜 대신 `82세(나이로 입력)` 로
  /// 보여준다.
  final bool birthByAge;
  final ConditionStage stage;
}

/// 환자 정보 입력에서 받은 세부 정보 네 항목이다(`api-spec.md` 의 Profile).
///
/// 건너뛴 항목은 `null` 이다. 계약이 빈 문자열을 받지 않으므로 비어 있으면
/// `null` 로 둔다.
class EnteredDetails {
  const EnteredDetails({
    this.occupation,
    this.hometown,
    this.hobby,
    this.family,
  });

  /// 입력 흐름이 `category` 별로 모은 문장에서 만든다. 앞뒤 공백을 지우고, 남는
  /// 것이 없으면 `null` 이다.
  factory EnteredDetails.fromFacts(Map<String, String> facts) {
    String? read(String category) {
      final text = facts[category]?.trim();
      return text == null || text.isEmpty ? null : text;
    }

    return EnteredDetails(
      occupation: read('occupation'),
      hometown: read('hometown'),
      hobby: read('hobby'),
      family: read('family'),
    );
  }

  final String? occupation;
  final String? hometown;
  final String? hobby;
  final String? family;

  /// [category] 는 `occupation`, `hometown`, `hobby`, `family` 중 하나다.
  String? of(String category) => switch (category) {
    'occupation' => occupation,
    'hometown' => hometown,
    'hobby' => hobby,
    'family' => family,
    _ => null,
  };
}

/// 보호자가 돌보는 어르신 한 분이다.
///
/// 앱 안에서 등록을 시작한 [pending] 인 분은 [basicInfo] 가 비어 있다. 서버에서
/// 불러온 입력 중인 분은 기본 정보를 함께 들고 온다. 등록을 마친 분은 늘 기본
/// 정보가 있다.
class CareProfileEntry {
  const CareProfileEntry({
    required this.id,
    this.basicInfo,
    this.details = const EnteredDetails(),
    this.pending = false,
    this.remoteId,
  });

  /// 앱 안에서 이 분을 가리키는 값. 서버에서 불러온 분은 [remoteId] 와 같다.
  final String id;

  final EnteredBasicInfo? basicInfo;

  /// 세부 정보 네 항목. 입력하지 않았으면 모두 `null` 이다.
  final EnteredDetails details;

  /// 등록하다 마치지 않고 나간 분이다. 슬롯 하나를 차지하고 `입력 중` 으로
  /// 보이며, 고를 수는 없다. 입력한 값은 입력 흐름이 들고 있다.
  final bool pending;

  /// 서버의 `profileId`(`api-spec.md` 2절). 서버에 저장하지 않은 분은 `null`
  /// 이다. 로그인 없이 들어왔거나, 기본 정보를 마치기 전인 경우다.
  final String? remoteId;

  CareProfileEntry copyWith({
    EnteredBasicInfo? basicInfo,
    EnteredDetails? details,
    bool? pending,
    String? remoteId,
  }) => CareProfileEntry(
    id: id,
    basicInfo: basicInfo ?? this.basicInfo,
    details: details ?? this.details,
    pending: pending ?? this.pending,
    remoteId: remoteId ?? this.remoteId,
  );
}

/// 어르신 목록을 서버에서 불러온 상태다.
enum CareProfilesLoad {
  /// 서버를 쓰지 않는다. 로그인 세션 없이 들어온 경우다.
  local,

  loading,
  loaded,
  failed,
}

/// 등록한 어르신 목록과 지금 보고 있는 어르신이다.
class CareProfiles {
  const CareProfiles({
    required this.entries,
    required this.selectedId,
    this.load = CareProfilesLoad.local,
  });

  /// 한 보호자가 등록할 수 있는 어르신 수. 입력 중인 분도 자리를 차지한다
  /// (`api-spec.md` 2-2).
  static const max = 3;

  /// 전환 화면의 슬롯 순서 그대로다.
  final List<CareProfileEntry> entries;

  /// 고른 분이 없으면 `null` 이다.
  final String? selectedId;

  /// 불러오는 중이거나 실패했으면 [entries] 가 비어 있어도 등록한 분이 없다는
  /// 뜻이 아니다. 화면은 이때 등록 안내 대신 기다림이나 다시 시도를 보여준다.
  final CareProfilesLoad load;

  bool get isLoading => load == CareProfilesLoad.loading;
  bool get loadFailed => load == CareProfilesLoad.failed;

  /// 고를 수 있는 분들이다. 입력 중인 분은 빠진다.
  List<CareProfileEntry> get ready => entries.where((e) => !e.pending).toList();

  /// 지금 보고 있는 분이다. 등록을 마친 분이 없으면 `null` 이다.
  ///
  /// 이때는 대화 카드, 면회, 리포트를 쓸 수 없고 등록부터 안내한다.
  CareProfileEntry? get selected {
    final ready = this.ready;
    return ready.where((e) => e.id == selectedId).firstOrNull ??
        ready.firstOrNull;
  }

  bool get hasSelected => selected != null;

  bool get isFull => entries.length >= max;

  CareProfileEntry? byId(String id) =>
      entries.where((e) => e.id == id).firstOrNull;

  CareProfiles copyWith({
    List<CareProfileEntry>? entries,
    String? selectedId,
    CareProfilesLoad? load,
  }) => CareProfiles(
    entries: entries ?? this.entries,
    selectedId: selectedId ?? this.selectedId,
    load: load ?? this.load,
  );
}

/// 어르신 목록을 다룬다.
///
/// 로그인 세션이 있으면 서버(`api-spec.md` 2절)가 기준이다. 세션이 생기면
/// 목록을 불러오고, 등록과 수정은 화면이 서버에 저장한 뒤 이 상태에 반영한다.
/// 슬롯 순서는 서버에 저장하지 않으므로 다시 불러오면 만든 순서로 돌아간다.
///
/// 로그인 세션 없이 들어오면(구글 설정이 없는 디버그 빌드의 임시 건너뛰기)
/// 서버를 부르지 않고 앱이 켜져 있는 동안만 기억한다. 단말 보관 범위가 정해지지
/// 않았으므로(`data-contracts.md`, 이슈 18) 목록은 단말 저장소에 쓰지 않는다.
///
/// 고른 분의 서버 ID 하나만 계정마다 단말에 기억해(이슈 144) 앱을 다시 켜면
/// 그 분으로 연다([SelectedProfileStore]). 서버 목록을 불러온 뒤에만 기억하고,
/// 불러오는 중이거나 실패했을 때는 건드리지 않는다.
class CareProfilesNotifier extends Notifier<CareProfiles> {
  int _nextId = 0;

  /// 늦게 도착한 이전 불러오기가 새 결과를 덮지 않게 차례를 센다.
  int _loadRound = 0;

  @override
  CareProfiles build() {
    final accountId = ref.watch(
      sessionProvider.select((s) => s?.account.accountId),
    );
    if (accountId == null) {
      return const CareProfiles(entries: [], selectedId: null);
    }
    listenSelf((previous, next) => _remember(accountId, previous, next));
    // build 안에서는 상태를 바꿀 수 없어 다음 차례에 불러온다.
    Future.microtask(reload);
    return const CareProfiles(
      entries: [],
      selectedId: null,
      load: CareProfilesLoad.loading,
    );
  }

  /// 서버에서 목록을 다시 불러온다(2-1, 2-3). 고른 분은 남아 있으면 그대로 둔다.
  /// 고른 분이 없으면(앱을 막 켰을 때) 이 계정이 마지막으로 고른 분을 연다.
  ///
  /// 기억한 분을 읽은 뒤에 목록을 내보낸다. 첫 분이 잠깐 골라졌다가 바뀌면 그
  /// 사이에 다른 어르신으로 면회를 시작할 수 있다.
  ///
  /// 서버의 `inProgress` 는 첫 카드 생성 전이라는 뜻이라 `입력 중` 으로 둔다.
  Future<void> reload() async {
    final round = ++_loadRound;
    final previous = state.selectedId;
    state = state.copyWith(load: CareProfilesLoad.loading);
    final api = ref.read(profileApiProvider);
    final accountId = ref.read(sessionProvider)?.account.accountId;
    // 서버를 기다리는 동안 함께 읽는다. 저장소는 실패해도 `null` 을 준다.
    final remembered = previous == null && accountId != null
        ? ref.read(selectedProfileStoreProvider).read(accountId)
        : Future<String?>.value();
    try {
      final summaries = await api.list();
      final profiles = await Future.wait([
        for (final summary in summaries) api.get(summary.profileId),
      ]);
      // 관계는 서버에 없고 단말에만 있다. 저장소는 실패해도 `null` 을 준다.
      final relationshipStore = ref.read(profileRelationshipStoreProvider);
      final relationships = accountId == null
          ? <String?>[for (final _ in profiles) null]
          : await Future.wait([
              for (final profile in profiles)
                relationshipStore.read(accountId, profile.profileId),
            ]);
      // 나이로 입력했다는 표시도 단말에만 있다. 실패하면 `false` 다.
      final birthInputStore = ref.read(profileBirthInputStoreProvider);
      final byAge = accountId == null
          ? <bool>[for (final _ in profiles) false]
          : await Future.wait([
              for (final profile in profiles)
                birthInputStore.readByAge(accountId, profile.profileId),
            ]);
      final rememberedId = await remembered;
      if (!ref.mounted || round != _loadRound) return;
      final entries = [
        for (final (i, profile) in profiles.indexed)
          CareProfileEntry(
            id: profile.profileId,
            remoteId: profile.profileId,
            basicInfo: profile.basicInfo
                .withRelationship(relationships[i])
                .withBirthByAge(byAge[i]),
            details: profile.details,
            pending: profile.setupStatus != SetupStatus.completed,
          ),
      ];
      String? readyId(String? id) =>
          entries.where((e) => e.id == id && !e.pending).firstOrNull?.id;
      // 기억한 분이 지워졌거나 입력 중이면 첫 분으로 연다.
      state = CareProfiles(
        entries: entries,
        selectedId: readyId(previous) ?? readyId(rememberedId),
        load: CareProfilesLoad.loaded,
      );
    } on ApiFailure {
      if (!ref.mounted || round != _loadRound) return;
      state = CareProfiles(
        entries: const [],
        selectedId: null,
        load: CareProfilesLoad.failed,
      );
    }
  }

  /// 회원가입으로 첫 어르신을 입력했다. 목록을 이 분으로 시작한다.
  ///
  /// 서버에 저장했으면 [remoteId] 를 넘긴다. 서버에서 불러온 목록에 이미 있는
  /// 분이면 새로 만들지 않고 그 자리를 채운다.
  void startWith(
    EnteredBasicInfo info, {
    EnteredDetails details = const EnteredDetails(),
    String? remoteId,
  }) {
    if (remoteId != null) _rememberLocalInfo(remoteId, info);
    final existing = remoteId == null ? null : state.byId(remoteId);
    if (existing != null) {
      _replace(
        existing.copyWith(basicInfo: info, details: details, pending: false),
        select: true,
      );
      return;
    }
    final entry = CareProfileEntry(
      id: remoteId ?? _newId(),
      remoteId: remoteId,
      basicInfo: info,
      details: details,
    );
    state = state.copyWith(entries: [entry], selectedId: entry.id);
  }

  /// 어르신을 더 등록하기 시작했다. 빈자리가 없으면 `null` 이다.
  ///
  /// 마치기 전까지는 `입력 중` 으로 자리만 차지한다.
  String? beginAdding() {
    if (state.isFull) return null;
    final entry = CareProfileEntry(id: _newId(), pending: true);
    state = state.copyWith(entries: [...state.entries, entry]);
    return entry.id;
  }

  /// 입력 중이던 분이 서버에 저장됐다(2-2). 마치기 전이라 `입력 중` 그대로다.
  void attachRemote(String id, String remoteId) {
    final entry = state.byId(id);
    if (entry == null) return;
    _replace(entry.copyWith(remoteId: remoteId));
  }

  /// 입력 중이던 분의 등록을 마치고 그 분으로 바꾼다. 자리는 그대로다.
  void completeAdding(
    String id,
    EnteredBasicInfo info, {
    EnteredDetails details = const EnteredDetails(),
    String? remoteId,
  }) {
    final entry = state.byId(id);
    if (entry == null) return;
    final savedId = remoteId ?? entry.remoteId;
    if (savedId != null) _rememberLocalInfo(savedId, info);
    _replace(
      entry.copyWith(
        basicInfo: info,
        details: details,
        pending: false,
        remoteId: remoteId,
      ),
      select: true,
    );
  }

  /// 등록을 마친 분의 기본 정보를 고친다. 세부 정보는 그대로 둔다.
  void updateBasicInfo(String id, EnteredBasicInfo info) {
    final entry = state.byId(id);
    if (entry == null || entry.pending) return;
    if (entry.remoteId case final remoteId?) {
      _rememberLocalInfo(remoteId, info);
    }
    _replace(entry.copyWith(basicInfo: info));
  }

  /// 서버에 보내지 않는 기본 정보(관계, 나이로 입력했는지)를 단말에 기억한다.
  void _rememberLocalInfo(String remoteId, EnteredBasicInfo info) {
    rememberRelationship(remoteId, info.relationship);
    rememberBirthByAge(remoteId, byAge: info.birthByAge);
  }

  /// 서버에 저장한 분을 나이로 입력했는지 단말에 기억한다. `false` 면 지운다.
  /// 로그인하지 않았으면 앱이 켜져 있는 동안만 쓴다.
  void rememberBirthByAge(String remoteId, {required bool byAge}) {
    final accountId = ref.read(sessionProvider)?.account.accountId;
    if (accountId == null) return;
    ref
        .read(profileBirthInputStoreProvider)
        .writeByAge(accountId, remoteId, byAge);
  }

  /// 서버에 저장한 분의 관계를 단말에 기억한다. 비었으면 지운다. 로그인하지
  /// 않았으면 앱이 켜져 있는 동안만 쓴다.
  ///
  /// 기본 정보 입력에서 서버에 만든 직후에도 부른다. 마치기 전에 앱을 닫아도
  /// 이어서 입력할 때 관계가 남는다.
  void rememberRelationship(String remoteId, String? relationship) {
    final accountId = ref.read(sessionProvider)?.account.accountId;
    if (accountId == null) return;
    ref
        .read(profileRelationshipStoreProvider)
        .write(accountId, remoteId, relationship);
  }

  /// 등록을 마친 분의 세부 정보 네 항목을 고친다. 기본 정보는 그대로 둔다.
  void updateDetails(String id, EnteredDetails details) {
    final entry = state.byId(id);
    if (entry == null || entry.pending) return;
    _replace(entry.copyWith(details: details));
  }

  void select(String id) {
    if (state.ready.every((e) => e.id != id)) return;
    state = state.copyWith(selectedId: id);
  }

  /// 목록 순서대로 다음 어르신으로 바꾼다. 마지막이면 처음으로 돌아간다.
  /// 입력 중인 분은 건너뛴다.
  void selectNext() {
    final ready = state.ready;
    if (ready.isEmpty) return;
    final index = ready.indexWhere((e) => e.id == state.selected?.id);
    select(ready[(index + 1) % ready.length].id);
  }

  /// 슬롯 순서를 바꾼다. [newIndex] 는 옮긴 뒤의 자리다
  /// (`ReorderableListView.onReorderItem` 과 같다).
  void reorder(int oldIndex, int newIndex) {
    final entries = [...state.entries];
    entries.insert(newIndex, entries.removeAt(oldIndex));
    state = state.copyWith(entries: entries);
  }

  /// 슬롯 하나를 비운다. 보고 있던 분을 지우면 남은 첫 분으로 바꾼다.
  ///
  /// 마지막 분도 지울 수 있다. 프로필 삭제는 계정 탈퇴가 아니므로 계정은
  /// 그대로 두고 빈 목록이 된다. 서버에서 지우는 일(2-8)은 화면이 먼저 한다.
  ///
  /// 그 분의 리포트 알림도 함께 지운다. 입력 중이던 값은 입력 흐름이 지운다.
  void remove(String id) {
    final removed = state.byId(id);
    if (removed == null) return;
    if (removed.remoteId case final remoteId?) {
      rememberRelationship(remoteId, null);
      rememberBirthByAge(remoteId, byAge: false);
    }
    final entries = state.entries.where((e) => e.id != id).toList();
    final selectedId = state.selectedId == id
        ? entries.where((e) => !e.pending).firstOrNull?.id
        : state.selectedId;
    state = CareProfiles(
      entries: entries,
      selectedId: selectedId,
      load: state.load,
    );
    ref.read(_reportNoticesProvider.notifier).dismiss((
      accountId: ref.read(sessionProvider)?.account.accountId,
      profileId: id,
    ));
  }

  void _replace(CareProfileEntry entry, {bool select = false}) {
    state = state.copyWith(
      entries: [for (final e in state.entries) e.id == entry.id ? entry : e],
      selectedId: select ? entry.id : null,
    );
  }

  /// 고른 분이 바뀌면 단말에 기억한다. 남은 분이 없으면 기억을 지운다.
  ///
  /// 서버 목록을 불러온 상태에서만 쓴다. 불러오는 중이거나 실패하면 고른 분이
  /// 비어 보이지만, 그건 지운 게 아니므로 기억을 남긴다.
  void _remember(String accountId, CareProfiles? previous, CareProfiles next) {
    if (next.load != CareProfilesLoad.loaded) return;
    final wasLoaded = previous?.load == CareProfilesLoad.loaded;
    final before = wasLoaded ? previous?.selected : null;
    final selected = next.selected;
    final store = ref.read(selectedProfileStoreProvider);
    if (selected == null) {
      if (!wasLoaded || before != null) store.clear(accountId);
      return;
    }
    // 서버에 저장하기 전인 분은 다시 켜면 목록에 없으므로 기억하지 않는다.
    final remoteId = selected.remoteId;
    if (remoteId == null || remoteId == before?.remoteId) return;
    store.write(accountId, remoteId);
  }

  String _newId() => 'local-${_nextId++}';
}

final careProfilesProvider =
    NotifierProvider<CareProfilesNotifier, CareProfiles>(
      CareProfilesNotifier.new,
    );

/// 전환 화면의 슬롯 하나에 보여줄 어르신이다.
class CareProfileSummary {
  const CareProfileSummary({
    required this.id,
    required this.profileId,
    required this.name,
    required this.gender,
    required this.selected,
    required this.pending,
    this.relationship,
  });

  final String id;

  /// [Profile.profileId] 와 같은 값. 서버에 저장한 분은 서버 ID 다. 이 기기에
  /// 둔 사진을 찾는 데 쓴다(`LocalPhotos`).
  final String profileId;

  /// 입력 중인 분은 비어 있다. 이름은 입력 흐름이 들고 있다.
  final String name;
  final String gender;

  /// 보호자와의 관계. 받기 전에 등록한 분과 입력 중인 분은 `null` 이다.
  final String? relationship;

  /// 지금 보고 있는 어르신인지.
  final bool selected;

  /// 등록하다 마치지 않은 분인지.
  final bool pending;
}

/// 등록한 어르신들을 슬롯 순서대로 요약한다.
final careProfileSummariesProvider = FutureProvider<List<CareProfileSummary>>((
  ref,
) async {
  final profiles = ref.watch(careProfilesProvider);
  return [
    for (final entry in profiles.entries)
      CareProfileSummary(
        id: entry.id,
        profileId: entry.remoteId ?? entry.id,
        name: entry.basicInfo?.name ?? '',
        gender: entry.basicInfo?.gender ?? '',
        relationship: entry.basicInfo?.relationship,
        selected: entry.id == profiles.selected?.id,
        pending: entry.pending,
      ),
  ];
});

/// 입력 흐름이 쓰는 목 데이터 묶음이다. 음성 입력 예시와 목 사진을 여기서
/// 읽는다.
///
/// 첫 분을 입력하는 동안에는 고른 어르신이 없으므로 [profileProvider] 를 쓰지
/// 않는다.
final profileSampleProvider = FutureProvider<ProfileBundle>(
  (ref) => ref.watch(mockRepositoryProvider).loadProfile(),
);

/// 지금 보고 있는 어르신의 프로필이다. 등록을 마친 분이 없으면 `null` 이다.
///
/// 기본 정보와 세부 정보 네 항목은 입력한 값이다. 그 밖의 생애 정보는 아직 목
/// 데이터 그대로다.
///
/// 서버에 저장한 분의 사진은 여기 담지 않는다. 갤러리가
/// [serverProfilePhotosProvider] 로 따로 읽는다. 사진을 읽지 못해도 이름과 정보는
/// 보여야 해서다. 로그인 없이 들어온 분은 목 사진을 이 분의 `photos[]` 로 붙인다.
final profileProvider = FutureProvider<ProfileBundle?>((ref) async {
  final bundle = await ref.watch(profileSampleProvider.future);
  final selected = ref.watch(careProfilesProvider.select((p) => p.selected));
  final entered = selected?.basicInfo;
  if (selected == null || entered == null) return null;

  final online = ref.watch(sessionProvider.select((s) => s != null));
  final onServer = online && selected.remoteId != null;
  final mock = bundle.profile;
  final details = selected.details;
  return ProfileBundle(
    profile: Profile(
      // 서버에 저장한 분은 서버의 profileId 를 쓴다. 카드 생성(4-1)이 이 값을 쓴다.
      profileId: selected.remoteId ?? selected.id,
      name: entered.name,
      gender: entered.gender,
      relationship: entered.relationship,
      birthDate: entered.birthDate,
      birthByAge: entered.birthByAge,
      ageRange: ageRangeOf(entered.birthDate, DateTime.now()),
      stage: entered.stage,
      lifeFactIds: mock.lifeFactIds,
      photoIds: onServer ? const [] : mock.photoIds,
      occupation: details.occupation,
      hometown: details.hometown,
      hobby: details.hobby,
      family: details.family,
    ),
    lifeFacts: bundle.lifeFacts,
    collectionStates: bundle.collectionStates,
    photos: onServer
        ? const []
        : [for (final photo in bundle.photos) photo.forProfile(selected.id)],
  );
});

/// 사진 분석(3-2)이 끝났는지 다시 묻는 간격. 테스트는 짧게 바꾼다.
///
/// 명세는 간격을 정하지 않는다. 리포트 상태를 묻는 간격과 같게 둔다.
final photoAnalysisPollIntervalProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 5),
);

/// 지금 계정이 AI 사진 분석(선택 동의 `photoAnalysis`)에 동의했는지. 계정을 읽는
/// 중이거나 읽지 못했으면 `null` 이다.
///
/// 동의하지 않은 계정의 사진은 사진 분석 worker 가 가져가지 않아 `pending` 으로
/// 남는다. 갤러리는 이때 "분석 중"을 보이지 않고 보호자가 바로 설명을 적게 하며,
/// 사진 상태도 다시 묻지 않는다.
final photoAnalysisWantedProvider = Provider<bool?>((ref) {
  final account = ref.watch(accountProvider).value;
  if (account == null) return null;
  return account.consent['photoAnalysis']?.granted ?? false;
});

/// 서버에 저장한 지금 어르신의 프로필 사진(2-3). 올린 순서대로다.
///
/// 로그인하지 않았거나 서버에 저장하지 않은 분이면 `null` 이고, 갤러리는
/// [profileProvider] 의 목 사진을 쓴다.
///
/// 분석이 끝나지 않은 사진(`pending`, `processing`)은 3-2 로 끝날 때까지 묻고 그
/// 자리를 바꾼다. 묻지 못하면 다음 차례에 다시 묻는다. 갤러리를 떠나면 묻지
/// 않고, 다시 열면 처음부터 읽는다. `imageUrl` 은 수명이 짧아 다시 열 때 새로
/// 받는다.
class ServerProfilePhotosNotifier extends AsyncNotifier<List<ProfilePhoto>?> {
  /// 읽을 때마다 올라간다. 지난 읽기의 폴링은 버린다.
  int _round = 0;

  @override
  Future<List<ProfilePhoto>?> build() async {
    final round = ++_round;
    final online = ref.watch(sessionProvider.select((s) => s != null));
    final remoteId = ref.watch(
      careProfilesProvider.select((p) => p.selected?.remoteId),
    );
    if (!online || remoteId == null) return null;

    final photos = (await ref.watch(profileApiProvider).get(remoteId)).photos;
    // 읽는 동안 갤러리를 떠났으면 늦게 온 응답으로 묻기 시작하지 않는다.
    // 분석에 동의하지 않은 계정의 사진은 끝나지 않으므로 묻지 않는다.
    if (!_stale(round) &&
        photos.any(_analyzing) &&
        ref.read(photoAnalysisWantedProvider) != false) {
      // 상태를 돌려준 뒤에 묻기 시작한다.
      Future<void>(() => _poll(round));
    }
    return photos;
  }

  static bool _analyzing(ProfilePhoto photo) => switch (photo.analysisStatus) {
    PhotoAnalysisStatus.completed || PhotoAnalysisStatus.failed => false,
    _ => true,
  };

  bool _stale(int round) => !ref.mounted || round != _round;

  Future<void> _poll(int round) async {
    if (_stale(round)) return;
    final interval = ref.read(photoAnalysisPollIntervalProvider);
    final api = ref.read(profileApiProvider);
    while (true) {
      await Future<void>.delayed(interval);
      if (_stale(round)) return;
      final photos = state.value;
      if (photos == null || !photos.any(_analyzing)) return;
      // 묻는 사이 동의를 거뒀으면 그만 묻는다.
      if (ref.read(photoAnalysisWantedProvider) == false) return;

      final next = [...photos];
      for (var i = 0; i < next.length; i++) {
        if (!_analyzing(next[i])) continue;
        try {
          next[i] = await api.photo(next[i].photoId);
        } on ApiFailure {
          // 이번에는 묻지 못했다. 다음 차례에 다시 묻는다.
        }
        if (_stale(round)) return;
      }
      state = AsyncData(next);
    }
  }
}

final serverProfilePhotosProvider =
    AsyncNotifierProvider.autoDispose<
      ServerProfilePhotosNotifier,
      List<ProfilePhoto>?
    >(ServerProfilePhotosNotifier.new);

/// 사진 카드의 사진 주소를 다시 읽는 여유. 가장 먼저 만료되는 주소보다 이만큼
/// 먼저 다시 읽고, 읽은 지 이만큼 지나지 않았으면 다시 읽지 않는다. 테스트는
/// 바꾼다.
final cardPhotoUrlMarginProvider = Provider<Duration>(
  (ref) => const Duration(minutes: 1),
);

/// 사진에서 나온 카드(`evidenceSource: photo`)에 그 사진을 붙이려고 읽는 지금
/// 어르신의 프로필 사진 주소다. 사진 ID → `imageUrl` 이다.
///
/// 서버에 저장한 분이면 2-3 으로 읽는다. 갤러리의 [serverProfilePhotosProvider]
/// 와 달리 분석 상태는 묻지 않는다. 보는 화면이 없으면 버리고 다음에 새로 읽는다.
/// 카드 화면은 녹음 화면 아래에 열린 채 남고 녹음 화면도 이 주소를 들고 있어
/// 면회(60~90분) 내내 들고 있는다. 주소는 수명이 짧아(`imageUrlExpiresAt`, 서버
/// 기본 15분) 가장 먼저 만료되는 주소보다 [cardPhotoUrlMarginProvider] 만큼 먼저
/// 다시 읽는다. 휴대폰 시계가 어긋나 이미 지났다고 나와도 그 간격보다 자주 읽지
/// 않는다. 연결이 끊겨 읽지 못했으면 같은 간격 뒤에 다시 읽는다. 다시 읽는
/// 동안과 다시 읽지 못했을 때 화면은 이미 받은 주소를 쓰고, 처음부터 받지
/// 못했으면 사진 없이 그린다. 그림을 열지 못하면 [imageFailed] 로 한 번 다시
/// 읽는다. 로그인하지 않았으면 목 사진이다.
class CardPhotoUrlsNotifier extends AsyncNotifier<Map<String, String>> {
  /// 지금 주소를 받은 때. 받지 못했거나 다시 읽는 중이면 `null` 이다.
  DateTime? _readAt;

  @override
  Future<Map<String, String>> build() async {
    _readAt = null;
    final online = ref.watch(sessionProvider.select((s) => s != null));
    final remoteId = ref.watch(
      careProfilesProvider.select((p) => p.selected?.remoteId),
    );
    if (!online || remoteId == null) {
      final bundle = await ref.watch(profileProvider.future);
      return {
        for (final photo in bundle?.photos ?? const <ProfilePhoto>[])
          photo.photoId: photo.imageUrl,
      };
    }

    final margin = ref.watch(cardPhotoUrlMarginProvider);
    final List<ProfilePhoto> photos;
    try {
      photos = (await ref.watch(profileApiProvider).get(remoteId)).photos;
    } on ApiFailure catch (failure) {
      final retryable =
          failure is ApiNetworkFailure ||
          (failure is ApiServerFailure && failure.retryable);
      if (retryable && ref.mounted) _readAgainAfter(margin);
      rethrow;
    }
    final urls = {for (final photo in photos) photo.photoId: photo.imageUrl};
    // 읽는 동안 다시 읽기 시작했으면 이 응답은 버려진다.
    if (!ref.mounted) return urls;

    _readAt = DateTime.now();
    DateTime? earliest;
    for (final photo in photos) {
      final at = DateTime.tryParse(photo.imageUrlExpiresAt ?? '');
      if (at != null && (earliest == null || at.isBefore(earliest))) {
        earliest = at;
      }
    }
    if (earliest != null) {
      final wait = earliest.difference(DateTime.now()) - margin;
      _readAgainAfter(wait < margin ? margin : wait);
    }
    return urls;
  }

  void _readAgainAfter(Duration wait) {
    final timer = Timer(wait, ref.invalidateSelf);
    ref.onDispose(timer.cancel);
  }

  /// 이미 [imageFailed] 로 알린 주소. 화면이 다시 그려질 때마다 같은 실패를
  /// 다시 알려도 한 번만 본다.
  final _failedUrls = <String>{};

  /// 사진 카드의 그림을 [url] 로 열지 못했다. 휴대폰이 잠들어 다시 읽을 때를
  /// 놓쳤으면 주소가 만료됐을 수 있어 다시 읽는다. 받은 지
  /// [cardPhotoUrlMarginProvider] 가 지나지 않은 주소로도 열지 못했으면(지운
  /// 사진, 끊긴 연결) 다시 읽어도 같아 읽지 않는다. 여러 장이 함께 실패해도 한
  /// 번만 읽는다.
  void imageFailed(String url) {
    if (!_failedUrls.add(url)) return;
    final readAt = _readAt;
    if (readAt == null) return;
    final margin = ref.read(cardPhotoUrlMarginProvider);
    if (DateTime.now().difference(readAt) < margin) return;
    _readAt = null;
    ref.invalidateSelf();
  }
}

final cardPhotoUrlsProvider =
    AsyncNotifierProvider.autoDispose<
      CardPhotoUrlsNotifier,
      Map<String, String>
    >(CardPhotoUrlsNotifier.new, retry: (_, _) => null);

/// 생년월일로 `80s` 같은 연령대를 만든다. 생일이 지나지 않았으면 한 살 뺀다.
String ageRangeOf(String birthDate, DateTime today) {
  final birth = DateTime.parse(birthDate);
  var age = today.year - birth.year;
  if (today.month < birth.month ||
      (today.month == birth.month && today.day < birth.day)) {
    age--;
  }
  return '${age ~/ 10 * 10}s';
}

/// 고른 어르신의 지금 쓸 카드 묶음(API 4-3).
///
/// 서버에서만 받는다. 목 묶음은 테스트가 이 provider 를 override 해서 쓴다.
/// 자동 재시도는 끈다. 쓸 묶음이 없다는 거절은 다시 물어도 같고, 다시 받기는
/// 화면의 버튼으로 한다.
final currentCardSetProvider = FutureProvider<CardSet>((ref) async {
  final profileId = await ref.watch(serverProfileIdProvider.future);
  if (profileId == null) throw StateError('고른 어르신이 없다');
  return ref.watch(cardApiProvider).current(profileId);
}, retry: (_, _) => null);

/// 서버 API 에 보낼, 고른 어르신의 `profileId`. 고른 분이 없으면 `null` 이다.
///
/// 앱 안에서 어르신을 가리키는 값(`careProfilesProvider` 의 `id`)이 아니라
/// [profileProvider] 의 `profileId` 를 쓴다. 이번 실행에서 새로 등록한 분은 앱
/// 안의 값과 서버가 준 값이 다를 수 있고, [profileProvider] 가 서버에 저장한
/// 분이면 서버의 값을 알려준다.
final serverProfileIdProvider = FutureProvider<String?>(
  (ref) async => (await ref.watch(profileProvider.future))?.profile.profileId,
);

final conversationCardsProvider = FutureProvider<List<ConversationCard>>(
  (ref) async => (await ref.watch(currentCardSetProvider.future)).cards,
);

final visitSessionProvider = FutureProvider<VisitSession>(
  (ref) => ref.watch(mockRepositoryProvider).loadVisitSession(),
);

final visitReportProvider = FutureProvider<VisitReport>(
  (ref) => ref.watch(mockRepositoryProvider).loadVisitReport(),
);

final caregiverEvaluationProvider = FutureProvider<CaregiverEvaluation>(
  (ref) => ref.watch(mockRepositoryProvider).loadCaregiverEvaluation(),
);

final changeProposalProvider = FutureProvider<ChangeProposal>(
  (ref) => ref.watch(mockRepositoryProvider).loadChangeProposal(),
);

/// 로그인해 서버와 이어진 상태다. 아니면 목 데이터를 쓴다(구글 설정이 없는
/// 디버그 빌드의 임시 건너뛰기).
bool _online(Ref ref) => ref.watch(sessionProvider.select((s) => s != null));

/// 리포트 하나. [reportId] 는 서버에서는 회차 ID 다(7-2).
final reportProvider = FutureProvider.autoDispose.family<VisitReport, String>((
  ref,
  reportId,
) {
  if (_online(ref)) return ref.watch(reportApiProvider).report(reportId);
  return ref.watch(visitReportProvider.future);
});

/// 리포트 회차에서 보호자가 카드마다 남긴 답(6-4).
final reportCardReviewsProvider = FutureProvider.autoDispose
    .family<List<CardReview>, String>((ref, reportId) async {
      if (_online(ref)) {
        return ref.watch(reportApiProvider).cardReviews(reportId);
      }
      final evaluation = await ref.watch(caregiverEvaluationProvider.future);
      return evaluation.cardReviews;
    });

/// 리포트 회차에 고른 카드(5-4). 모르면 `null` 이다.
///
/// 서버에 저장하지 않은 분이거나 최근 회차 목록에 없으면 모른다.
final reportSelectedCardIdsProvider = FutureProvider.autoDispose
    .family<List<String>?, String>((ref, reportId) async {
      if (_online(ref)) {
        final profileId = ref.watch(
          careProfilesProvider.select((p) => p.selected?.remoteId),
        );
        if (profileId == null) return null;
        return ref
            .watch(reportApiProvider)
            .selectedCardIds(profileId, reportId);
      }
      final session = await ref.watch(visitSessionProvider.future);
      return session.selectedCardIds;
    });

/// 리포트 회차의 변경 제안(7-3).
final reportProposalsProvider = FutureProvider.autoDispose
    .family<ChangeProposal, String>((ref, reportId) {
      if (_online(ref)) return ref.watch(reportApiProvider).proposals(reportId);
      return ref.watch(changeProposalProvider.future);
    });

/// 지금 보고 있는 어르신의 리포트 기록(7-1). 최근 면회부터다.
///
/// 서버에 저장하지 않은 분이면 빈 목록이다. 목 데이터에는 리포트가 하나뿐이다.
final reportHistoryProvider = FutureProvider.autoDispose<List<ReportListItem>>((
  ref,
) async {
  if (_online(ref)) {
    final profileId = ref.watch(
      careProfilesProvider.select((p) => p.selected?.remoteId),
    );
    if (profileId == null) return const [];
    return ref.watch(reportApiProvider).reports(profileId);
  }
  final report = await ref.watch(visitReportProvider.future);
  return [
    ReportListItem(
      reportId: report.reportId,
      title: report.title,
      visitDate: report.visitDate,
      mood: report.mood,
      photoId: report.photoId,
      photoUrl: report.photoUrl,
    ),
  ];
});

/// 리포트를 만드는 동안 서버에 상태를 묻는 간격. 테스트는 짧게 바꾼다.
///
/// 명세는 폴링 간격을 정하지 않는다. 목 데이터가 리포트를 만드는 시간과 같게
/// 둔다.
final reportPollIntervalProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 5),
);

/// 홈 화면에 띄우는 리포트 알림이다.
///
/// 리포트가 만들어지는 중이거나 만들어진 뒤에만 뜬다. 회원가입하고 처음 들어온
/// 사용자에게는 보이지 않는다. 리포트를 읽는 것만으로는 사라지지 않고, 변경
/// 사항까지 확인해야 사라진다.
///
/// 서버의 회차 상태(5-4)를 홈 표시로 옮긴 것이다. 평가 전과 음성 접수 전은
/// 앱을 다시 켠 뒤 면회 흐름을 이어가게 한다. 이어가는 화면은 면회 흐름이 맡는다.
enum ReportNotice {
  /// 평가 전에 앱을 떠났다(`evaluationPending`). 눌러서 평가를 이어서 한다.
  evaluationPending,

  /// 평가 뒤 음성을 보내지 못했다(`audioPending`). 눌러서 음성을 다시 보낸다.
  audioPending,

  /// 만드는 중. 음성을 보낸 뒤부터 도착까지다(`processing`).
  generating,

  /// 다 만들어졌다. 눌러서 리포트로 들어간다(`completed`).
  ready,

  /// 만들지 못했다(`failed`). 눌러서 저장된 전사나 기기 녹음으로 다시 요청한다.
  failed,

  /// 서버에 회차 상태를 묻지 못했다. 알릴 것이 없는 것과 구분해, 눌러서 다시
  /// 묻게 한다. 만드는 중에 다시 시도할 수 없는 실패로 묻기를 멈췄을 때도 이
  /// 알림이다. 만드는 중 배너가 끝없이 돌지 않게 한다. 다시 묻는 동안에는
  /// [ReportNoticeInfo.rechecking] 으로 남는다.
  checkFailed,
}

/// 알림 하나와 그 알림이 가리키는 리포트다.
class ReportNoticeInfo {
  const ReportNoticeInfo(
    this.notice, {
    this.reportId,
    this.analysisId,
    this.visitDate,
    this.fromServer = false,
    this.failureCode,
    this.rechecking = false,
  });

  final ReportNotice notice;

  /// [ReportNotice.checkFailed] 를 눌러 다시 묻는 중이다. 묻는 동안 배너를
  /// 지우면 사라졌다가 최대 15초 뒤 다시 나타났다(2026-11-10 UX 점검 17번).
  final bool rechecking;

  /// 서버의 회차로 정한 알림이다. 아니면 목 데이터의 알림이고, 화면이 목
  /// 리포트를 가리킨다.
  final bool fromServer;

  /// 눌러서 열 리포트. 서버에서는 회차 ID 다. 목 데이터의 알림은 `null` 이고
  /// 화면이 목 리포트를 연다.
  final String? reportId;
  final String? analysisId;

  /// 면회한 날. 모르면 `null` 이다.
  final String? visitDate;

  /// [ReportNotice.failed] 일 때 분석 작업(6-3)의 `errorCode`. 회차 목록(5-4)은
  /// 이유를 주지 않아 6-3 으로 한 번 더 묻는다. 모르면 `null` 이다
  /// ([analysisFailureReason]).
  final String? failureCode;
}

/// 알림 하나가 속한 자리. 같은 휴대폰을 쓰는 계정마다 따로 둔다.
///
/// [accountId] 가 `null` 이면 서버 세션 없이 들어온 경우다(구글 설정이 없는
/// 디버그 빌드의 임시 건너뛰기).
typedef _NoticeKey = ({String? accountId, String profileId});

/// 계정과 어르신마다의 리포트 알림이다.
///
/// 리포트를 기다리는 동안 다른 어르신으로 바꿔도, 도착은 기다리던 어르신에게
/// 남는다. 계정도 마찬가지다. 로그아웃해도 지우지 않고, 다른 계정에는 보이지
/// 않다가 그 계정으로 다시 들어오면 다시 보인다. 화면은 이것을 직접 보지 않고
/// [reportNoticeProvider] 를 본다.
///
/// 로그인했으면 서버의 가장 최근 회차(5-4)로 알림을 정하고, 만드는 중이면 분석
/// 작업(6-3)을 다 될 때까지 묻는다. 그래서 앱을 다시 켜도 같은 알림이 뜬다.
/// 로그인하지 않았으면 목 데이터가 정한 시간을 센다.
class _ReportNoticesNotifier
    extends Notifier<Map<_NoticeKey, ReportNoticeInfo>> {
  /// 자리마다 지금 기다리는 회차. 지우거나 다시 시작하면 올라가고, 지난
  /// 기다림의 결과는 버린다.
  final _rounds = <_NoticeKey, int>{};

  /// 서버에 한 번 물어본 자리. 같은 자리를 화면이 다시 그릴 때마다 묻지 않는다.
  final _synced = <_NoticeKey>{};

  /// 이번 실행에서 변경 사항 확인을 마친 리포트. 서버가 확인 여부를 저장하지
  /// 않아(api-spec 미정 사항 2) 다시 물어도 도착으로 띄우지 않도록 기억한다.
  /// 앱을 다시 켜면 잊는다.
  final _acknowledged = <String>{};

  bool _gone = false;

  @override
  Map<_NoticeKey, ReportNoticeInfo> build() {
    ref.onDispose(() => _gone = true);
    return const {};
  }

  int _nextRound(_NoticeKey key) => _rounds[key] = (_rounds[key] ?? 0) + 1;

  bool _stale(_NoticeKey key, int round) => _gone || _rounds[key] != round;

  void _set(_NoticeKey key, ReportNoticeInfo? notice) {
    final next = Map<_NoticeKey, ReportNoticeInfo>.from(state);
    notice == null ? next.remove(key) : next[key] = notice;
    state = next;
  }

  void dismiss(_NoticeKey key, {String? reportId}) {
    for (final id in [reportId, state[key]?.reportId]) {
      if (id != null) _acknowledged.add(id);
    }
    _nextRound(key);
    _set(key, null);
  }

  /// [reportId] 를 확인했다. 지금 알림이 그 리포트의 도착이면 지운다. 다른
  /// 리포트(리포트 기록에서 연 지난 리포트)의 알림이면 남긴다. 목 데이터의 도착
  /// 알림은 가리키는 리포트가 없어 목 리포트를 열면 지운다.
  void acknowledge(_NoticeKey key, String reportId) {
    _acknowledged.add(reportId);
    final notice = state[key];
    if (notice == null || notice.notice != ReportNotice.ready) return;
    if (notice.reportId != null && notice.reportId != reportId) return;
    _nextRound(key);
    _set(key, null);
  }

  void arrive(_NoticeKey key) {
    _nextRound(key);
    _set(key, const ReportNoticeInfo(ReportNotice.ready));
  }

  /// 목 데이터로 리포트를 기다린다. 정해진 시간이 지나면 도착한다.
  void startMockGenerating(_NoticeKey key) {
    final round = _nextRound(key);
    _set(key, const ReportNoticeInfo(ReportNotice.generating));

    unawaited(
      ref.read(mockRepositoryProvider).awaitReportReady().then((_) {
        // 그 사이 지웠거나 다시 시작했으면 지난 기다림의 결과다.
        if (_stale(key, round)) return;
        _set(key, const ReportNoticeInfo(ReportNotice.ready));
      }),
    );
  }

  /// 서버에 리포트를 만들기 시작했다. 다 될 때까지 서버에 묻는다.
  void startGenerating(
    _NoticeKey key,
    String remoteProfileId, {
    String? analysisId,
  }) {
    _synced.add(key);
    final round = _nextRound(key);
    _set(
      key,
      const ReportNoticeInfo(ReportNotice.generating, fromServer: true),
    );
    unawaited(_follow(key, round, remoteProfileId, analysisId: analysisId));
  }

  /// 녹음을 시작해 서버에 회차가 생겼다(5-1). 서버의 가장 최근 회차가 평가
  /// 전인 이 회차가 되므로, 5-4 를 다시 묻지 않고 같은 알림으로 바꾼다. 앞
  /// 회차를 기다리던 흐름은 끊는다.
  void visitStarted(_NoticeKey key, String sessionId, String startedAt) {
    _synced.add(key);
    _nextRound(key);
    String? visitDate;
    try {
      visitDate = VisitProgress(
        sessionId: sessionId,
        status: VisitStatus.evaluationPending,
        startedAt: startedAt,
      ).visitDate;
    } on FormatException {
      // 날짜를 읽지 못해도 이어서 할 회차는 알린다. 배너는 날짜 없이 뜬다.
    }
    _set(
      key,
      ReportNoticeInfo(
        ReportNotice.evaluationPending,
        reportId: sessionId,
        visitDate: visitDate,
        fromServer: true,
      ),
    );
  }

  /// 이 자리를 아직 서버에 묻지 않았으면 가장 최근 회차로 알림을 정한다.
  void syncOnce(_NoticeKey key, String remoteProfileId) {
    if (!_synced.add(key)) return;
    unawaited(_follow(key, _nextRound(key), remoteProfileId));
  }

  /// 묻지 못했던 자리를 다시 묻는다. 묻는 동안에는 알림을 지우지 않고 다시
  /// 묻는 중([ReportNoticeInfo.rechecking])으로 둔다.
  void retry(_NoticeKey key, String remoteProfileId) {
    _synced.add(key);
    final round = _nextRound(key);
    _set(key, _checkFailed(state[key], rechecking: true));
    unawaited(_follow(key, round, remoteProfileId));
  }

  /// 묻지 못했다는 알림. 만드는 중이던 회차를 알면 날짜와 회차를 그대로 둔다.
  static ReportNoticeInfo _checkFailed(
    ReportNoticeInfo? shown, {
    bool rechecking = false,
  }) => ReportNoticeInfo(
    ReportNotice.checkFailed,
    reportId: shown?.reportId,
    analysisId: shown?.analysisId,
    visitDate: shown?.visitDate,
    fromServer: true,
    rechecking: rechecking,
  );

  /// 가장 최근 회차를 읽어 알림을 정하고, 만드는 중이면 끝날 때까지 묻는다.
  ///
  /// 만드는 중에 서버에 닿지 못하면 잠시 뒤 다시 묻는다. 띄운 알림이 없거나,
  /// 만드는 중이었거나, 다시 묻던 중에 묻지 못하면 [ReportNotice.checkFailed] 를
  /// 띄운다. 그 밖에 이미 띄운 알림은 그대로 둔다.
  Future<void> _follow(
    _NoticeKey key,
    int round,
    String remoteProfileId, {
    String? analysisId,
  }) async {
    final api = ref.read(reportApiProvider);
    final interval = ref.read(reportPollIntervalProvider);
    var first = true;

    while (true) {
      if (!first) {
        await Future<void>.delayed(interval);
        if (_stale(key, round)) return;
      }
      first = false;

      final VisitProgress? latest;
      try {
        latest = await api.latestSession(remoteProfileId);
      } on ApiFailure catch (failure) {
        if (_stale(key, round)) return;
        final shown = state[key];
        if (_retryable(failure) && shown?.notice == ReportNotice.generating) {
          continue;
        }
        if (shown == null ||
            shown.notice == ReportNotice.generating ||
            shown.notice == ReportNotice.checkFailed) {
          _set(key, _checkFailed(shown));
        }
        return;
      }
      if (_stale(key, round)) return;

      if (latest == null) {
        _set(key, null);
        return;
      }

      if (latest.status != VisitStatus.processing) {
        _set(key, _noticeOf(latest, latest.status));
        if (latest.status == VisitStatus.failed) {
          await _addFailureCode(key, round, latest);
        }
        return;
      }

      _set(
        key,
        ReportNoticeInfo(
          ReportNotice.generating,
          reportId: latest.sessionId,
          visitDate: latest.visitDate,
          fromServer: true,
        ),
      );

      // 만드는 중이면 분석 작업(6-3)을 묻는다. 작업 ID 를 모르면 회차를 다시
      // 묻는다.
      final id = analysisId ?? latest.analysisId;
      if (id == null) continue;
      final done = await _pollAnalysis(key, round, id, latest);
      if (done) return;
      // 작업을 찾지 못했다. 회차부터 다시 묻는다.
      analysisId = null;
    }
  }

  /// 분석 작업이 끝날 때까지 묻는다. 끝났거나 그만 물어야 하면 `true`, 작업을
  /// 찾지 못해 회차부터 다시 물어야 하면 `false` 다. 다시 시도할 수 없는
  /// 실패로 그만 물으면 만드는 중 배너를 [ReportNotice.checkFailed] 로 바꾼다.
  Future<bool> _pollAnalysis(
    _NoticeKey key,
    int round,
    String analysisId,
    VisitProgress session,
  ) async {
    final api = ref.read(reportApiProvider);
    final interval = ref.read(reportPollIntervalProvider);

    while (true) {
      await Future<void>.delayed(interval);
      if (_stale(key, round)) return true;

      final AnalysisProgress progress;
      try {
        progress = await api.analysis(analysisId);
      } on ApiFailure catch (failure) {
        if (_stale(key, round)) return true;
        if (_retryable(failure)) continue;
        if (failure is ApiServerFailure && failure.statusCode == 404) {
          return false;
        }
        _set(key, _checkFailed(state[key]));
        return true;
      }
      if (_stale(key, round)) return true;

      switch (progress.status) {
        case AnalysisStatus.completed:
          _set(key, _noticeOf(session, VisitStatus.completed));
          return true;
        case AnalysisStatus.failed:
          _set(
            key,
            _noticeOf(
              session,
              VisitStatus.failed,
              failureCode: progress.errorCode,
            ),
          );
          return true;
        default:
          continue;
      }
    }
  }

  /// 회차 목록(5-4)이 실패라고 했을 때 그 분석 작업(6-3)의 실패 이유를 한 번
  /// 물어 알림에 붙인다. 묻지 못하면 이유 없이 둔다. 실패 배너는 그 전에 이미
  /// 띄웠다.
  Future<void> _addFailureCode(
    _NoticeKey key,
    int round,
    VisitProgress session,
  ) async {
    final analysisId = session.analysisId;
    if (analysisId == null) return;
    final AnalysisProgress progress;
    try {
      progress = await ref.read(reportApiProvider).analysis(analysisId);
    } on ApiFailure {
      return;
    }
    if (_stale(key, round) || progress.status != AnalysisStatus.failed) return;
    if (progress.errorCode == null) return;
    _set(
      key,
      _noticeOf(session, VisitStatus.failed, failureCode: progress.errorCode),
    );
  }

  /// 서버에 닿지 못했거나 서버가 다시 시도해도 된다고 알렸다.
  ///
  /// 5xx 를 공통 `ErrorResponse` 없이 받은 것(본문 없는 502, 504 등)도 다시
  /// 묻는다. 앞단 프록시가 앱 서버의 응답을 받지 못한 것이라 서버가 `retryable`
  /// 을 알릴 수 없었다. 여기서는 상태를 읽기만 하므로 다시 물어도 탈이 없다.
  static bool _retryable(ApiFailure failure) =>
      failure is ApiNetworkFailure ||
      (failure is ApiServerFailure &&
          (failure.retryable ||
              failure.statusCode >= 500 && failure.errorCode == null));

  /// 회차 상태를 홈 알림으로 옮긴다. 모르는 상태와 확인을 마친 리포트는
  /// `null` 이다.
  ReportNoticeInfo? _noticeOf(
    VisitProgress session,
    VisitStatus? status, {
    String? failureCode,
  }) {
    final notice = switch (status) {
      VisitStatus.evaluationPending => ReportNotice.evaluationPending,
      VisitStatus.audioPending => ReportNotice.audioPending,
      VisitStatus.processing => ReportNotice.generating,
      VisitStatus.completed =>
        _acknowledged.contains(session.sessionId) ? null : ReportNotice.ready,
      VisitStatus.failed => ReportNotice.failed,
      null => null,
    };
    if (notice == null) return null;
    return ReportNoticeInfo(
      notice,
      reportId: session.sessionId,
      analysisId: session.analysisId,
      visitDate: session.visitDate,
      fromServer: true,
      failureCode: notice == ReportNotice.failed ? failureCode : null,
    );
  }

  /// 계정 하나의 알림을 모두 지운다. 기다리던 리포트가 늦게 와도 버린다.
  void forgetAccount(String accountId) {
    final keys = {
      ...state.keys,
      ..._rounds.keys,
    }.where((k) => k.accountId == accountId).toList();
    for (final key in keys) {
      _nextRound(key);
    }
    _synced.removeWhere((k) => k.accountId == accountId);
    state = {
      for (final e in state.entries)
        if (e.key.accountId != accountId) e.key: e.value,
    };
  }
}

final _reportNoticesProvider =
    NotifierProvider<_ReportNoticesNotifier, Map<_NoticeKey, ReportNoticeInfo>>(
      _ReportNoticesNotifier.new,
    );

/// 지금 로그인한 계정과 보고 있는 어르신의 리포트 알림과 그 리포트다.
///
/// 다른 어르신의 리포트가 도착해도 이 어르신의 홈에는 띄우지 않는다. 다른
/// 어르신의 알림을 어떻게 알릴지는 PM 확인 전이다. 다른 계정의 알림은 띄우지
/// 않는다.
///
/// 서버에 저장한 분을 처음 보면 서버에 가장 최근 회차를 묻는다.
final reportNoticeInfoProvider = Provider<ReportNoticeInfo?>((ref) {
  final accountId = ref.watch(
    sessionProvider.select((s) => s?.account.accountId),
  );
  final selected = ref.watch(
    careProfilesProvider.select(
      (p) => (id: p.selected?.id, remoteId: p.selected?.remoteId),
    ),
  );
  final profileId = selected.id;
  if (profileId == null) return null;
  final key = (accountId: accountId, profileId: profileId);
  final remoteId = selected.remoteId;
  if (accountId != null && remoteId != null) {
    // 화면을 그리는 중에 상태를 바꾸지 않도록 미룬다.
    Future.microtask(() {
      if (ref.mounted) {
        ref.read(_reportNoticesProvider.notifier).syncOnce(key, remoteId);
      }
    });
  }
  return ref.watch(_reportNoticesProvider.select((m) => m[key]));
});

/// 지금 보고 있는 어르신의 리포트 알림이다. [reportNoticeInfoProvider] 의
/// 알림 종류만 본다.
class ReportNoticeNotifier extends Notifier<ReportNotice?> {
  @override
  ReportNotice? build() => ref.watch(reportNoticeInfoProvider)?.notice;

  _ReportNoticesNotifier get _notices =>
      ref.read(_reportNoticesProvider.notifier);

  /// 변경 사항 확인을 마쳤다. [reportId] 는 확인한 리포트다. 서버가 그 회차를
  /// 계속 `completed` 로 주어도 이번 실행에서는 다시 띄우지 않는다.
  void dismiss({String? reportId}) {
    final key = _currentNoticeKey(ref);
    if (key != null) _notices.dismiss(key, reportId: reportId);
  }

  /// 확인할 제안이 없는 리포트를 열었다. 지금 알림이 그 리포트의 도착이면
  /// 지운다. 서버가 그 회차를 계속 `completed` 로 주어도 이번 실행에서는 다시
  /// 띄우지 않는다.
  void acknowledge(String reportId) {
    final key = _currentNoticeKey(ref);
    if (key != null) _notices.acknowledge(key, reportId);
  }

  /// 리포트가 만들어졌다.
  void arrive() {
    final key = _currentNoticeKey(ref);
    if (key != null) _notices.arrive(key);
  }

  /// 리포트를 만들기 시작했다. 다 되면 스스로 도착이나 실패로 바뀐다.
  ///
  /// 서버에 저장한 분이면 음성을 보낸 뒤(6-2) 부른다. [analysisId] 는 6-2 가
  /// 돌려준 작업이며, 모르면 서버의 가장 최근 회차(5-4)에서 찾는다. 로그인하지
  /// 않았으면 목 데이터의 시간을 센다. 기다림을 화면이 아니라 이 상태가 안고
  /// 있어, 사용자가 홈을 떠나 다른 화면을 보고 있어도 도착은 알려진다.
  ///
  /// 고른 어르신이 없으면 아무것도 하지 않는다. 면회는 어르신을 고른 뒤에만
  /// 할 수 있다.
  void startGenerating({String? analysisId}) {
    final key = _currentNoticeKey(ref);
    if (key == null) return;
    final remoteId = ref.read(careProfilesProvider).selected?.remoteId;
    if (key.accountId != null && remoteId != null) {
      _notices.startGenerating(key, remoteId, analysisId: analysisId);
    } else {
      _notices.startMockGenerating(key);
    }
  }

  /// 녹음을 시작해 회차를 만들었다(5-1). 홈에 `평가 이어서 하기` 를 띄운다.
  ///
  /// 홈은 서버의 회차(5-4)를 어르신마다 앱을 켠 뒤 한 번만 묻는다. 그래서
  /// 면회 중 녹음 화면을 떠나 홈에 오면, 앱을 다시 켜기 전에는 이어갈 배너가
  /// 없었다(#234). [startedAt] 은 5-1 이 준 `startedAt` 이다.
  void visitStarted({required String sessionId, required String startedAt}) {
    final key = _currentNoticeKey(ref);
    if (key != null) _notices.visitStarted(key, sessionId, startedAt);
  }

  /// 회차 상태를 묻지 못했을 때 다시 묻는다. 서버에 저장한 분일 때만 묻는다.
  void retry() {
    final key = _currentNoticeKey(ref);
    final remoteId = ref.read(careProfilesProvider).selected?.remoteId;
    if (key == null || key.accountId == null || remoteId == null) return;
    _notices.retry(key, remoteId);
  }

  /// 탈퇴한 계정의 알림을 지운다. 세션이 지워진 뒤에 부르므로 계정을 받는다.
  void forgetAccount(String accountId) => _notices.forgetAccount(accountId);
}

/// 부르는 순간의 계정과 어르신이다. 기다리는 동안 어르신이나 계정을 바꿔도
/// 도착은 이 자리에 남는다. 고른 어르신이 없으면 `null` 이다.
_NoticeKey? _currentNoticeKey(Ref ref) {
  final profileId = ref.read(careProfilesProvider).selected?.id;
  if (profileId == null) return null;
  return (
    accountId: ref.read(sessionProvider)?.account.accountId,
    profileId: profileId,
  );
}

final reportNoticeProvider =
    NotifierProvider<ReportNoticeNotifier, ReportNotice?>(
      ReportNoticeNotifier.new,
    );
