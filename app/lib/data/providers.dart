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
/// 계약상 `VisitReport.reportStatus` 가 `ready` 이면 알림을 표시하고, 사용자가
/// 리포트를 확인하면 사라진다. 스켈레톤에서는 이 값으로 흉내낸다.
class ReportNoticeNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void dismiss() => state = false;

  void show() => state = true;
}

final reportNoticeProvider = NotifierProvider<ReportNoticeNotifier, bool>(
  ReportNoticeNotifier.new,
);
