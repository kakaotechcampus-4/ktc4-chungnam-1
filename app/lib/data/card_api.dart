/// 대화 카드 API(`docs/architecture/api-spec.md` 4절).
///
/// 카드 생성은 비동기 작업이다. 4-1 로 요청하고 4-2 로 상태를 확인하다가,
/// `ready` 나 `inVisit` 이면 4-3 으로 묶음을 받는다. 세 요청 모두 프로필은
/// 경로의 `profileId` 로 정하고 요청 본문은 없다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'models.dart';

/// 4-2 의 `status`. 홈의 `오늘의 대화카드 받기` 를 이 값으로 정한다.
enum CardGenerationStatus {
  /// 작업이 없거나, 최근 묶음이 평가까지 끝난 회차에 쓰였다.
  none,

  /// 만드는 중이다.
  running,

  /// 다 만들었고 아직 쓰지 않았다.
  ready,

  /// 평가 전 회차(면회 중이거나 중간에 나감)가 쓰는 중이다.
  inVisit,

  /// 실패했다. 4-2 는 실패 이유를 주지 않는다.
  failed,

  /// 다 만들었지만 받은 뒤 프로필이나 일대기를 고쳤다. 서버는 `ready` 에
  /// `needsRefresh: true` 를 붙여 주고, 앱은 따로 가른다. 카드는 볼 수 있지만
  /// 이 묶음으로 면회를 시작할 수 없고 4-1 로 다시 만든다.
  needsRefresh;

  /// 모르는 값이면 성공으로 넘기지 않는다. [needsRefresh] 는 서버의 `status`
  /// 값이 아니므로 받지 않는다.
  static CardGenerationStatus parse(Object? raw, {bool needsRefresh = false}) {
    for (final value in values) {
      if (value == CardGenerationStatus.needsRefresh) continue;
      if (value.name != raw) continue;
      return value == CardGenerationStatus.ready && needsRefresh
          ? CardGenerationStatus.needsRefresh
          : value;
    }
    throw ApiUnexpectedResponseFailure('모르는 카드 생성 status: $raw');
  }
}

abstract interface class CardApi {
  /// 4-1. 카드를 만들어 달라고 요청한다.
  ///
  /// 받아들이면 `running` 이다. 서버가 이미 쓸 묶음이 있다고 거절하면 그 상태를
  /// 돌려준다(`CARD_SET_READY` 는 `ready`, `VISIT_IN_PROGRESS` 는 `inVisit`).
  Future<CardGenerationStatus> requestGeneration(String profileId);

  /// 4-2. 가장 최근 작업의 상태다. `needsRefresh` 가 없으면 `false` 로 본다.
  Future<CardGenerationStatus> status(String profileId);

  /// 4-3. 지금 쓸 카드 묶음이다. 쓸 묶음이 없으면 `CARD_GENERATION_NOT_FOUND`
  /// 로 거절된다.
  Future<CardSet> current(String profileId);
}

class ServerCardApi implements CardApi {
  const ServerCardApi(this._client);

  final ApiClient _client;

  static String _base(String profileId) =>
      '/api/v1/profiles/${Uri.encodeComponent(profileId)}/card-generations';

  @override
  Future<CardGenerationStatus> requestGeneration(String profileId) async {
    try {
      final body = await _client.post(_base(profileId));
      return CardGenerationStatus.parse(body['status']);
    } on ApiServerFailure catch (failure) {
      // 새로 만들 수 없는 까닭이 이미 쓸 묶음이 있어서라면 실패가 아니다.
      if (failure.statusCode == 409) {
        switch (failure.errorCode) {
          case 'CARD_SET_READY':
            return CardGenerationStatus.ready;
          case 'VISIT_IN_PROGRESS':
            return CardGenerationStatus.inVisit;
        }
      }
      rethrow;
    }
  }

  @override
  Future<CardGenerationStatus> status(String profileId) async {
    final body = await _client.get('${_base(profileId)}/status');
    return CardGenerationStatus.parse(
      body['status'],
      needsRefresh: body['needsRefresh'] == true,
    );
  }

  @override
  Future<CardSet> current(String profileId) async {
    final body = await _client.get('${_base(profileId)}/current');
    try {
      return CardSet.fromJson(body);
    } on TypeError {
      throw const ApiUnexpectedResponseFailure('카드 묶음 형식이 다르다');
    }
  }
}

/// 테스트는 이 provider 를 override 해 가짜 [CardApi] 를 넣는다(`ADR-005`).
final cardApiProvider = Provider<CardApi>(
  (ref) => ServerCardApi(ref.watch(apiClientProvider)),
);
