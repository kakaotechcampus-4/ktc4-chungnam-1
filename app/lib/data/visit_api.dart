/// 면회 회차 API(`docs/architecture/api-spec.md` 5절).
///
/// 회차는 녹음을 시작할 때 고른 카드로 만든다(5-1). 녹음 일시정지와 종료는
/// 단말에서 처리하고 서버에 알리지 않는다. 면회 중 보충 카드는 5-3 으로 더한다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  static VisitSession _session(Map<String, dynamic> body) {
    try {
      return VisitSession.fromJson(body);
    } on TypeError {
      throw const ApiUnexpectedResponseFailure('회차 형식이 다르다');
    }
  }
}

/// 테스트는 이 provider 를 override 해 가짜 [VisitApi] 를 넣는다(`ADR-005`).
final visitApiProvider = Provider<VisitApi>(
  (ref) => ServerVisitApi(ref.watch(apiClientProvider)),
);
