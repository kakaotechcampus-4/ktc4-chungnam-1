/// 로그인한 계정의 정보와 선택 동의 API(`docs/architecture/api-spec.md` 1-3,
/// 1-6)를 부른다.
///
/// 로그인과 가입(1-1, 1-2), 로그아웃과 탈퇴(1-4, 1-5)는 [AuthApi] 가 맡는다.
/// 이 두 API 는 로그인한 세션으로 부르므로 [ApiClient] 위에 둔다. 세션이 만료되면
/// 다시 받아 이어간다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'models.dart';

class AccountApi {
  const AccountApi(this._client);

  final ApiClient _client;

  /// 1-3 지금 계정과 가장 최근 동의 이력.
  Future<Account> me() async => _read(await _client.get('/auth/me'));

  /// 1-6 선택 동의를 바꾼다. [changes] 에 담은 항목만 바뀐다.
  ///
  /// 필수 동의(`serviceData`, `sensitiveData`)는 바꿀 수 없어 담지 않는다.
  Future<Account> updateConsents(Map<String, bool> changes) async =>
      _read(await _client.patch('/auth/me/consents', changes));

  /// 성공 응답이 계약과 다르면 성공으로 넘기지 않는다.
  static Account _read(Map<String, dynamic> body) {
    try {
      return Account.fromJson(body);
    } on TypeError catch (error) {
      throw ApiUnexpectedResponseFailure('계정 응답 모양이 다르다: $error');
    }
  }
}

/// 동의 저장 실패를 보호자에게 보여줄 문구로 옮긴다.
///
/// 서버의 `errorCode` 는 명세 1-6 의 값만 구분한다. 모르는 실패는 다시 시도하게
/// 안내하고 원인을 지어내지 않는다.
String consentFailureMessage(ApiFailure failure) => switch (failure) {
  ApiServerFailure(errorCode: 'REQUIRED_CONSENT_NOT_CHANGEABLE') =>
    '필수 동의는 여기서 바꿀 수 없어요.',
  ApiServerFailure(statusCode: 401) ||
  ApiSignedOutFailure() => '로그인이 풀렸어요. 다시 로그인해주세요.',
  ApiNetworkFailure() => '서버에 연결하지 못했어요. 인터넷 연결을 확인하고 다시 시도해주세요.',
  ApiUnexpectedResponseFailure() => '서버 응답을 읽지 못했어요. 잠시 뒤 다시 시도해주세요.',
  ApiServerFailure() => '동의를 저장하지 못했어요. 잠시 뒤 다시 시도해주세요.',
};

final accountApiProvider = Provider<AccountApi>(
  (ref) => AccountApi(ref.watch(apiClientProvider)),
);
