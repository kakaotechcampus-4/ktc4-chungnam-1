/// 화면은 이 provider 들만 본다. 목 데이터인지 서버 응답인지 알지 못한다.
///
/// 데이터 출처를 바꿀 때는 `mockRepositoryProvider` 를 override 한다.
/// 테스트에서 다른 값을 주입할 때도 같은 방법을 쓴다. `ADR-005` 참고.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mock_repository.dart';
import 'models.dart';

final mockRepositoryProvider = Provider<MockRepository>(
  (ref) => const MockRepository(),
);

final accountProvider = FutureProvider<Account>(
  (ref) => ref.watch(mockRepositoryProvider).loadAccount(),
);

/// 환자 정보 입력에서 받은 기본 정보다.
class EnteredBasicInfo {
  const EnteredBasicInfo({
    required this.name,
    required this.gender,
    required this.birthDate,
    required this.stage,
  });

  final String name;

  /// `male` 또는 `female`.
  final String gender;

  /// `YYYY-MM-DD`.
  final String birthDate;
  final ConditionStage stage;
}

/// 보호자가 돌보는 어르신 한 분이다.
///
/// [basicInfo] 가 `null` 이면 목 데이터 어르신이다. 로그인만 하고 들어온
/// 사용자가 보는 분이며, 기본 정보는 목 데이터 그대로다.
class CareProfileEntry {
  const CareProfileEntry({required this.id, this.basicInfo});

  final String id;
  final EnteredBasicInfo? basicInfo;
}

/// 등록한 어르신 목록과 지금 보고 있는 어르신이다.
class CareProfiles {
  const CareProfiles({required this.entries, required this.selectedId});

  /// 한 보호자가 등록할 수 있는 어르신 수.
  static const max = 3;

  final List<CareProfileEntry> entries;
  final String selectedId;

  CareProfileEntry get selected => entries.firstWhere(
    (e) => e.id == selectedId,
    orElse: () => entries.first,
  );

  bool get isFull => entries.length >= max;
}

/// 어르신 목록을 다룬다.
///
/// 프로필을 서버에 저장하는 API(`docs/architecture/api-spec.md` 2-2)가 아직 없어
/// 앱이 켜져 있는 동안만 기억한다. 단말 보관 범위가 정해지지 않았으므로
/// (`data-contracts.md`, 이슈 18) 단말 저장소에 쓰지 않는다. 앱을 다시 켜거나
/// 로그아웃하면 목 데이터 어르신 한 분으로 돌아간다.
///
/// 계약상 계정당 프로필은 1개다(`api-spec.md` 2-2). 최대 3분은 BE 와 합의 전인
/// 화면 설계이며, 서버를 붙일 때 이 제한을 함께 맞춘다.
class CareProfilesNotifier extends Notifier<CareProfiles> {
  static const _mockId = 'mock';

  int _nextId = 0;

  @override
  CareProfiles build() => const CareProfiles(
    entries: [CareProfileEntry(id: _mockId)],
    selectedId: _mockId,
  );

  /// 회원가입으로 첫 어르신을 입력했다. 목록을 이 분으로 시작한다.
  void startWith(EnteredBasicInfo info) {
    final entry = _entryOf(info);
    state = CareProfiles(entries: [entry], selectedId: entry.id);
  }

  /// 어르신을 더 등록하고 그 분으로 바꾼다. 가득 찼으면 `false` 다.
  bool add(EnteredBasicInfo info) {
    if (state.isFull) return false;
    final entry = _entryOf(info);
    state = CareProfiles(
      entries: [...state.entries, entry],
      selectedId: entry.id,
    );
    return true;
  }

  void select(String id) {
    if (state.entries.every((e) => e.id != id)) return;
    state = CareProfiles(entries: state.entries, selectedId: id);
  }

  /// 목록 순서대로 다음 어르신으로 바꾼다. 마지막이면 처음으로 돌아간다.
  void selectNext() {
    final entries = state.entries;
    final index = entries.indexOf(state.selected);
    select(entries[(index + 1) % entries.length].id);
  }

  CareProfileEntry _entryOf(EnteredBasicInfo info) =>
      CareProfileEntry(id: 'local-${_nextId++}', basicInfo: info);
}

final careProfilesProvider =
    NotifierProvider<CareProfilesNotifier, CareProfiles>(
      CareProfilesNotifier.new,
    );

/// 지금 보고 있는 어르신의 프로필이다.
///
/// 입력받은 어르신이면 목 데이터의 기본 정보를 입력값으로 바꾼다. 세부 정보와
/// 사진은 아직 목 데이터 그대로다.
final profileProvider = FutureProvider<ProfileBundle>((ref) async {
  final bundle = await ref.watch(mockRepositoryProvider).loadProfile();
  final selected = ref.watch(careProfilesProvider.select((p) => p.selected));
  final entered = selected.basicInfo;
  if (entered == null) return bundle;

  final mock = bundle.profile;
  return ProfileBundle(
    profile: Profile(
      profileId: selected.id,
      name: entered.name,
      gender: entered.gender,
      birthDate: entered.birthDate,
      ageRange: ageRangeOf(entered.birthDate, DateTime.now()),
      stage: entered.stage,
      lifeFactIds: mock.lifeFactIds,
      photoIds: mock.photoIds,
    ),
    lifeFacts: bundle.lifeFacts,
    collectionStates: bundle.collectionStates,
    photo: bundle.photo,
    tagCandidates: bundle.tagCandidates,
  );
});

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

final conversationCardsProvider = FutureProvider<List<ConversationCard>>(
  (ref) => ref.watch(mockRepositoryProvider).loadConversationCards(),
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

/// 홈 화면의 리포트 도착 알림 상태다.
///
/// 리포트가 만들어진 뒤에만 뜬다. 회원가입하고 처음 들어온 사용자에게는
/// 보이지 않는다. 계약상 `VisitReport.reportStatus` 가 `ready` 가 되는 시점에
/// 해당한다.
///
/// 리포트를 읽는 것만으로는 사라지지 않고, 변경 사항까지 확인해야 사라진다.
/// 홈 화면에 띄우는 리포트 알림이다.
///
/// 계약의 `ReportStatus` 중 홈에서 보여줄 둘만 쓴다. 새 어휘를 만들지 않는다.
enum ReportNotice {
  /// 만드는 중. 소감을 제출한 뒤부터 도착까지다.
  generating,

  /// 다 만들어졌다. 눌러서 리포트로 들어간다.
  ready,
}

/// 어르신마다의 리포트 알림이다.
///
/// 리포트를 기다리는 동안 다른 어르신으로 바꿔도, 도착은 기다리던 어르신에게
/// 남는다. 화면은 이것을 직접 보지 않고 [reportNoticeProvider] 를 본다.
class _ReportNoticesNotifier extends Notifier<Map<String, ReportNotice>> {
  /// 어르신마다 지금 기다리는 회차. 지우거나 다시 시작하면 올라가고, 지난
  /// 기다림의 결과는 버린다.
  final _rounds = <String, int>{};

  bool _gone = false;

  @override
  Map<String, ReportNotice> build() {
    ref.onDispose(() => _gone = true);
    return const {};
  }

  int _nextRound(String profileId) =>
      _rounds[profileId] = (_rounds[profileId] ?? 0) + 1;

  void _set(String profileId, ReportNotice? notice) {
    final next = Map<String, ReportNotice>.from(state);
    notice == null ? next.remove(profileId) : next[profileId] = notice;
    state = next;
  }

  void dismiss(String profileId) {
    _nextRound(profileId);
    _set(profileId, null);
  }

  void arrive(String profileId) {
    _nextRound(profileId);
    _set(profileId, ReportNotice.ready);
  }

  void startGenerating(String profileId) {
    final round = _nextRound(profileId);
    _set(profileId, ReportNotice.generating);

    unawaited(
      ref.read(mockRepositoryProvider).awaitReportReady().then((_) {
        // 그 사이 지웠거나 다시 시작했으면 지난 기다림의 결과다.
        if (_gone || _rounds[profileId] != round) return;
        _set(profileId, ReportNotice.ready);
      }),
    );
  }
}

final _reportNoticesProvider =
    NotifierProvider<_ReportNoticesNotifier, Map<String, ReportNotice>>(
      _ReportNoticesNotifier.new,
    );

/// 지금 보고 있는 어르신의 리포트 알림이다.
///
/// 다른 어르신의 리포트가 도착해도 이 어르신의 홈에는 띄우지 않는다. 다른
/// 어르신의 알림을 어떻게 알릴지는 PM 확인 전이다.
class ReportNoticeNotifier extends Notifier<ReportNotice?> {
  @override
  ReportNotice? build() {
    final profileId = ref.watch(
      careProfilesProvider.select((p) => p.selected.id),
    );
    return ref.watch(_reportNoticesProvider.select((m) => m[profileId]));
  }

  /// 부르는 순간의 어르신이다. 기다리는 동안 어르신을 바꿔도 도착은 이 어르신
  /// 에게 남는다.
  String get _profileId => ref.read(careProfilesProvider).selected.id;

  _ReportNoticesNotifier get _notices =>
      ref.read(_reportNoticesProvider.notifier);

  /// 변경 사항 확인을 마쳤다.
  void dismiss() => _notices.dismiss(_profileId);

  /// 리포트가 만들어졌다.
  void arrive() => _notices.arrive(_profileId);

  /// 리포트를 만들기 시작했다. 다 되면 스스로 도착으로 바뀐다.
  ///
  /// 얼마나 걸리는지도, 어떻게 알아내는지도 여기서 정하지 않는다. 저장소에
  /// 맡기므로 서버를 붙일 때 `mockRepositoryProvider` 만 갈아 끼우면 된다
  /// (`ADR-005`). 기다림을 화면이 아니라 이 상태가 안고 있어, 사용자가 홈을
  /// 떠나 다른 화면을 보고 있어도 도착은 알려진다.
  void startGenerating() => _notices.startGenerating(_profileId);
}

final reportNoticeProvider =
    NotifierProvider<ReportNoticeNotifier, ReportNotice?>(
      ReportNoticeNotifier.new,
    );
