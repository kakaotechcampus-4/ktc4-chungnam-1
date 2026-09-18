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
/// 홈 화면에 띄우는 리포트 알림이다.
///
/// 계약의 `ReportStatus` 중 홈에서 보여줄 둘만 쓴다. 새 어휘를 만들지 않는다.
enum ReportNotice {
  /// 만드는 중. 소감을 제출한 뒤부터 도착까지다.
  generating,

  /// 다 만들어졌다. 눌러서 리포트로 들어간다.
  ready,
}

class ReportNoticeNotifier extends Notifier<ReportNotice?> {
  /// 지금 기다리는 회차. 지우거나 다시 시작하면 올라가고, 지난 기다림의 결과는
  /// 버린다.
  int _round = 0;

  bool _gone = false;

  @override
  ReportNotice? build() {
    ref.onDispose(() => _gone = true);
    return null;
  }

  /// 변경 사항 확인을 마쳤다.
  void dismiss() {
    _round++;
    state = null;
  }

  /// 리포트가 만들어졌다.
  void arrive() {
    _round++;
    state = ReportNotice.ready;
  }

  /// 리포트를 만들기 시작했다. 다 되면 스스로 도착으로 바뀐다.
  ///
  /// 얼마나 걸리는지도, 어떻게 알아내는지도 여기서 정하지 않는다. 저장소에
  /// 맡기므로 서버를 붙일 때 `mockRepositoryProvider` 만 갈아 끼우면 된다
  /// (`ADR-005`). 기다림을 화면이 아니라 이 상태가 안고 있어, 사용자가 홈을
  /// 떠나 다른 화면을 보고 있어도 도착은 알려진다.
  void startGenerating() {
    final round = ++_round;
    state = ReportNotice.generating;

    unawaited(
      ref.read(mockRepositoryProvider).awaitReportReady().then((_) {
        // 그 사이 지웠거나 다시 시작했으면 지난 기다림의 결과다.
        if (_gone || _round != round) return;
        state = ReportNotice.ready;
      }),
    );
  }
}

final reportNoticeProvider =
    NotifierProvider<ReportNoticeNotifier, ReportNotice?>(
      ReportNoticeNotifier.new,
    );
