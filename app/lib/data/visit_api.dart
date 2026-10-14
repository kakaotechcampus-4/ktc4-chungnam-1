/// 면회 회차 API(`docs/architecture/api-spec.md` 5절).
///
/// 회차는 녹음을 시작할 때 고른 카드로 만든다(5-1). 녹음 일시정지와 종료는
/// 단말에서 처리하고 서버에 알리지 않는다. 면회 중 보충 카드는 5-3 으로 더한다.
/// 면회를 마치면 보호자 평가를 6-1 로 저장하고 녹음을 6-2 로 보낸다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'models.dart';

abstract interface class VisitApi {
  /// 5-1. 회차를 만든다. 응답의 `sessionStatus` 는 `evaluationPending` 이다.
  ///
  /// [selectedCardIds] 는 묶음의 `position` 1~9 에서 중복 없이 1~9개다.
  Future<VisitSession> createSession({
    required String setId,
    required List<String> selectedCardIds,
  });

  /// 5-3. 면회 중 꺼낸 보충 카드를 회차에 더한다.
  ///
  /// [cardIds] 는 `position` 10~12 에서 1~3개다. 이미 더한 카드는 서버가
  /// 무시하므로 같은 요청을 다시 보내도 결과가 같다.
  Future<VisitSession> addCards(String sessionId, List<String> cardIds);

  /// 6-1. 보호자 평가를 저장한다. 저장하면 회차는 `audioPending` 이 된다.
  ///
  /// 이미 저장했다는 거절(`EVALUATION_ALREADY_SUBMITTED`)은 성공으로 본다.
  /// 저장했는데 응답을 받지 못해 다시 보낸 경우다.
  Future<void> submitEvaluation(
    String sessionId,
    EvaluationSubmission evaluation,
  );

  /// 6-2. 녹음 파일과 참여자 수를 보내고 음성 분석 작업 ID 를 받는다.
  ///
  /// 평가(6-1)를 저장한 회차만 받는다. [participantCount] 는 녹음을 끝낼 때
  /// 보호자가 확인한 1~8 이다.
  Future<String> submitAudio(
    String sessionId, {
    required String audioPath,
    required int participantCount,
  });
}

class ServerVisitApi implements VisitApi {
  const ServerVisitApi(this._client);

  final ApiClient _client;

  @override
  Future<VisitSession> createSession({
    required String setId,
    required List<String> selectedCardIds,
  }) async => _session(
    await _client.post('/api/v1/visit-sessions', {
      'setId': setId,
      'selectedCardIds': selectedCardIds,
    }),
  );

  @override
  Future<VisitSession> addCards(String sessionId, List<String> cardIds) async =>
      _session(
        await _client.patch(
          '/api/v1/visit-sessions/${Uri.encodeComponent(sessionId)}/cards',
          {'cardIds': cardIds},
        ),
      );

  @override
  Future<void> submitEvaluation(
    String sessionId,
    EvaluationSubmission evaluation,
  ) async {
    try {
      await _client.post(
        '/api/v1/visit-sessions/${Uri.encodeComponent(sessionId)}/evaluation',
        evaluation.toJson(),
      );
    } on ApiServerFailure catch (failure) {
      if (failure.statusCode == 409 &&
          failure.errorCode == 'EVALUATION_ALREADY_SUBMITTED') {
        return;
      }
      rethrow;
    }
  }

  @override
  Future<String> submitAudio(
    String sessionId, {
    required String audioPath,
    required int participantCount,
  }) async {
    final body = await _client.postMultipart(
      '/api/v1/visit-sessions/${Uri.encodeComponent(sessionId)}/speech-analyses',
      fields: {'participantCount': '$participantCount'},
      files: [await http.MultipartFile.fromPath('audio', audioPath)],
    );
    final analysisId = body['analysisId'];
    if (analysisId is! String || analysisId.isEmpty) {
      throw const ApiUnexpectedResponseFailure('analysisId 가 없다');
    }
    return analysisId;
  }

  static VisitSession _session(Map<String, dynamic> body) {
    try {
      return VisitSession.fromJson(body);
    } on TypeError {
      throw const ApiUnexpectedResponseFailure('회차 형식이 다르다');
    }
  }
}

/// 6-2 가 이미 끝났거나 실패로 끝난 회차라고 거절했는지. 다시 보내도 받지
/// 않으므로 기기의 녹음을 지우고 마친다.
bool isClosedAnalysis(ApiServerFailure failure) =>
    failure.statusCode == 409 &&
    (failure.errorCode == 'ANALYSIS_ALREADY_COMPLETED' ||
        failure.errorCode == 'ANALYSIS_ALREADY_FAILED');

/// 테스트는 이 provider 를 override 해 가짜 [VisitApi] 를 넣는다(`ADR-005`).
final visitApiProvider = Provider<VisitApi>(
  (ref) => ServerVisitApi(ref.watch(apiClientProvider)),
);
