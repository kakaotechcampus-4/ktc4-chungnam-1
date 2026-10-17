// 서버 대신 쓰는 면회 회차 API 대역이다. 값은 모두 합성이다.

import 'package:saerok/data/api_client.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/visit_api.dart';

class FakeVisitApi implements VisitApi {
  FakeVisitApi({
    this.failCreate = false,
    this.failAdd = false,
    this.failEvaluation = false,
    this.audioFailure,
  });

  /// 5-1 이 연결 실패로 끝나게 한다.
  bool failCreate;

  /// 5-3 이 연결 실패로 끝나게 한다.
  bool failAdd;

  /// 6-1 이 연결 실패로 끝나게 한다.
  bool failEvaluation;

  /// 6-2 가 이 실패로 끝나게 한다.
  Object? audioFailure;

  /// 6-2 로 보낸 녹음.
  ({String sessionId, String audioPath, int participantCount})? audio;

  static const analysisId = 'analysis_test_001';

  /// 6-1 로 저장한 평가.
  ({String sessionId, EvaluationSubmission evaluation})? evaluated;

  final calls = <String>[];

  /// 마지막 5-1 요청.
  ({String setId, List<String> selectedCardIds})? created;

  /// 5-3 으로 더한 카드.
  final added = <String>[];

  static const sessionId = 'session_test_001';

  @override
  Future<VisitSession> createSession({
    required String setId,
    required List<String> selectedCardIds,
  }) async {
    calls.add('create');
    if (failCreate) throw const ApiNetworkFailure();
    created = (setId: setId, selectedCardIds: selectedCardIds);
    return _session(setId, selectedCardIds);
  }

  @override
  Future<VisitSession> addCards(String sessionId, List<String> cardIds) async {
    calls.add('add');
    if (failAdd) throw const ApiNetworkFailure();
    added.addAll(cardIds);
    return _session(created?.setId ?? 'set', [
      ...?created?.selectedCardIds,
      ...added,
    ]);
  }

  @override
  Future<void> submitEvaluation(
    String sessionId,
    EvaluationSubmission evaluation,
  ) async {
    calls.add('evaluation');
    if (failEvaluation) throw const ApiNetworkFailure();
    evaluated = (sessionId: sessionId, evaluation: evaluation);
  }

  @override
  Future<String> submitAudio(
    String sessionId, {
    required String audioPath,
    required int participantCount,
  }) async {
    calls.add('audio');
    final failure = audioFailure;
    if (failure != null) throw failure;
    audio = (
      sessionId: sessionId,
      audioPath: audioPath,
      participantCount: participantCount,
    );
    return analysisId;
  }

  static VisitSession _session(String setId, List<String> cardIds) =>
      VisitSession(
        sessionId: sessionId,
        profileId: 'profile_test_001',
        setId: setId,
        selectedCardIds: cardIds,
        sessionStatus: SessionStatus.evaluationPending,
        startedAt: '2026-10-13T14:00:00+09:00',
      );
}
