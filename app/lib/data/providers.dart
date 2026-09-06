/// 화면은 이 provider 들만 본다. 목 데이터인지 서버 응답인지 알지 못한다.
///
/// 데이터 출처를 바꿀 때는 `mockRepositoryProvider` 를 override 한다.
/// 테스트에서 다른 값을 주입할 때도 같은 방법을 쓴다. `ADR-003` 참고.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mock_repository.dart';
import 'models.dart';

final mockRepositoryProvider = Provider<MockRepository>(
  (ref) => const MockRepository(),
);

final accountProvider = FutureProvider<Account>(
  (ref) => ref.watch(mockRepositoryProvider).loadAccount(),
);

final profileProvider = FutureProvider<ProfileBundle>(
  (ref) => ref.watch(mockRepositoryProvider).loadProfile(),
);

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
class ReportNoticeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// 변경 사항 확인을 마쳤다.
  void dismiss() => state = false;

  /// 리포트가 만들어졌다.
  void show() => state = true;
}

final reportNoticeProvider = NotifierProvider<ReportNoticeNotifier, bool>(
  ReportNoticeNotifier.new,
);
