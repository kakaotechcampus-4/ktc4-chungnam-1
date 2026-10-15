/// 화면은 이 provider 들만 본다. 목 데이터인지 서버 응답인지 알지 못한다.
///
/// 데이터 출처를 바꿀 때는 `mockRepositoryProvider` 를 override 한다.
/// 테스트에서 다른 값을 주입할 때도 같은 방법을 쓴다. `ADR-005` 참고.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_providers.dart';
import 'api_client.dart';
import 'mock_repository.dart';
import 'models.dart';
import 'profile_api.dart';
import 'report_api.dart';

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
/// 않았으므로(`data-contracts.md`, 이슈 18) 단말 저장소에는 쓰지 않는다.
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
    // build 안에서는 상태를 바꿀 수 없어 다음 차례에 불러온다.
    Future.microtask(reload);
    return const CareProfiles(
      entries: [],
      selectedId: null,
      load: CareProfilesLoad.loading,
    );
  }

  /// 서버에서 목록을 다시 불러온다(2-1, 2-3). 고른 분은 남아 있으면 그대로 둔다.
  ///
  /// 서버의 `inProgress` 는 첫 카드 생성 전이라는 뜻이라 `입력 중` 으로 둔다.
  Future<void> reload() async {
    final round = ++_loadRound;
    final previous = state.selectedId;
    state = state.copyWith(load: CareProfilesLoad.loading);
    final api = ref.read(profileApiProvider);
    try {
      final summaries = await api.list();
      final profiles = await Future.wait([
        for (final summary in summaries) api.get(summary.profileId),
      ]);
      if (!ref.mounted || round != _loadRound) return;
      final entries = [
        for (final profile in profiles)
          CareProfileEntry(
            id: profile.profileId,
            remoteId: profile.profileId,
            basicInfo: profile.basicInfo,
            details: profile.details,
            pending: profile.setupStatus != SetupStatus.completed,
          ),
      ];
      state = CareProfiles(
        entries: entries,
        selectedId: entries.any((e) => e.id == previous && !e.pending)
            ? previous
            : null,
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
    _replace(entry.copyWith(basicInfo: info));
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
    if (state.entries.every((e) => e.id != id)) return;
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
      entries: [
        for (final e in state.entries) e.id == entry.id ? entry : e,
      ],
      selectedId: select ? entry.id : null,
    );
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
    required this.name,
    required this.gender,
    required this.selected,
    required this.pending,
  });

  final String id;

  /// 입력 중인 분은 비어 있다. 이름은 입력 흐름이 들고 있다.
  final String name;
  final String gender;

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
        name: entry.basicInfo?.name ?? '',
        gender: entry.basicInfo?.gender ?? '',
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
/// 데이터 그대로다. 사진은 목 사진을 이 분의 `photos[]` 로 붙인다. 업로드 API(3-1)가 연결되면 이 분이
/// 올린 사진으로 바뀐다.
final profileProvider = FutureProvider<ProfileBundle?>((ref) async {
  final bundle = await ref.watch(profileSampleProvider.future);
  final selected = ref.watch(careProfilesProvider.select((p) => p.selected));
  final entered = selected?.basicInfo;
  if (selected == null || entered == null) return null;

  final mock = bundle.profile;
  final details = selected.details;
  return ProfileBundle(
    profile: Profile(
      // 서버에 저장한 분은 서버의 profileId 를 쓴다. 카드 생성(4-1)이 이 값을 쓴다.
      profileId: selected.remoteId ?? selected.id,
      name: entered.name,
      gender: entered.gender,
      birthDate: entered.birthDate,
      ageRange: ageRangeOf(entered.birthDate, DateTime.now()),
      stage: entered.stage,
      lifeFactIds: mock.lifeFactIds,
      photoIds: mock.photoIds,
      occupation: details.occupation,
      hometown: details.hometown,
      hobby: details.hobby,
      family: details.family,
    ),
    lifeFacts: bundle.lifeFacts,
    collectionStates: bundle.collectionStates,
    photos: [for (final photo in bundle.photos) photo.forProfile(selected.id)],
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

  /// 만들지 못했다(`failed`). 다시 만드는 방법은 아직 정하지 않았다.
  failed,

  /// 서버에 회차 상태를 묻지 못했다. 알릴 것이 없는 것과 구분해, 눌러서 다시
  /// 묻게 한다.
  checkFailed,
}

/// 알림 하나와 그 알림이 가리키는 리포트다.
class ReportNoticeInfo {
  const ReportNoticeInfo(
    this.notice, {
    this.reportId,
    this.visitDate,
    this.fromServer = false,
  });

  final ReportNotice notice;

  /// 서버의 회차로 정한 알림이다. 아니면 목 데이터의 알림이고, 화면이 목
  /// 리포트를 가리킨다.
  final bool fromServer;

  /// 눌러서 열 리포트. 서버에서는 회차 ID 다. 목 데이터의 알림은 `null` 이고
  /// 화면이 목 리포트를 연다.
  final String? reportId;

  /// 면회한 날. 모르면 `null` 이다.
  final String? visitDate;
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

  /// 이 자리를 아직 서버에 묻지 않았으면 가장 최근 회차로 알림을 정한다.
  void syncOnce(_NoticeKey key, String remoteProfileId) {
    if (!_synced.add(key)) return;
    unawaited(_follow(key, _nextRound(key), remoteProfileId));
  }

  /// 묻지 못했던 자리를 다시 묻는다. 묻는 동안에는 알림을 비운다.
  void retry(_NoticeKey key, String remoteProfileId) {
    _synced.add(key);
    final round = _nextRound(key);
    _set(key, null);
    unawaited(_follow(key, round, remoteProfileId));
  }

  /// 가장 최근 회차를 읽어 알림을 정하고, 만드는 중이면 끝날 때까지 묻는다.
  ///
  /// 만드는 중에 서버에 닿지 못하면 잠시 뒤 다시 묻는다. 띄운 알림이 없을 때
  /// 묻지 못하면 [ReportNotice.checkFailed] 를 띄운다. 이미 띄운 알림은 그대로
  /// 둔다.
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
        if (_retryable(failure) &&
            state[key]?.notice == ReportNotice.generating) {
          continue;
        }
        if (state[key] == null) {
          _set(
            key,
            const ReportNoticeInfo(ReportNotice.checkFailed, fromServer: true),
          );
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
  /// 찾지 못해 회차부터 다시 물어야 하면 `false` 다.
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

      final AnalysisStatus? status;
      try {
        status = await api.analysis(analysisId);
      } on ApiFailure catch (failure) {
        if (_stale(key, round)) return true;
        if (_retryable(failure)) continue;
        if (failure is ApiServerFailure && failure.statusCode == 404) {
          return false;
        }
        return true;
      }
      if (_stale(key, round)) return true;

      switch (status) {
        case AnalysisStatus.completed:
          _set(key, _noticeOf(session, VisitStatus.completed));
          return true;
        case AnalysisStatus.failed:
          _set(key, _noticeOf(session, VisitStatus.failed));
          return true;
        default:
          continue;
      }
    }
  }

  /// 서버에 닿지 못했거나 서버가 다시 시도해도 된다고 알렸다.
  static bool _retryable(ApiFailure failure) =>
      failure is ApiNetworkFailure ||
      (failure is ApiServerFailure && failure.retryable);

  /// 회차 상태를 홈 알림으로 옮긴다. 모르는 상태와 확인을 마친 리포트는
  /// `null` 이다.
  ReportNoticeInfo? _noticeOf(VisitProgress session, VisitStatus? status) {
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
      visitDate: session.visitDate,
      fromServer: true,
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
