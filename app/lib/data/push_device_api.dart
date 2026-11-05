/// 리포트 완료 푸시를 받을 이 기기의 등록과 해제(`api-spec.md` 1-7, 1-8).
///
/// 경로에 FCM 등록 ID(FID)를 싣는다. 둘 다 본문 없이 `204` 다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

class PushDeviceApi {
  const PushDeviceApi(this._client);

  final ApiClient _client;

  /// 1-7. 알림 수신에 동의하지 않은 계정이면 서버가 403
  /// (`PUSH_NOTIFICATION_CONSENT_REQUIRED`)으로 거절한다.
  Future<void> register(String fid) =>
      _client.put('/auth/me/push-devices/${Uri.encodeComponent(fid)}');

  /// 1-8. 등록하지 않은 FID 여도 `204` 다.
  Future<void> unregister(String fid) =>
      _client.delete('/auth/me/push-devices/${Uri.encodeComponent(fid)}');
}

final pushDeviceApiProvider = Provider<PushDeviceApi>(
  (ref) => PushDeviceApi(ref.watch(apiClientProvider)),
);
