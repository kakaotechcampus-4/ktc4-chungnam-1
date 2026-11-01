/// 프로필 API(`docs/architecture/api-spec.md` 2절)를 부른다.
///
/// 요청은 [ApiClient] 가 보내고, 이 파일은 경로, 본문과 응답 모양만 맡는다.
/// 일대기 이야기(`lifeFacts`)도 2절이라 여기서 읽고 담는다(2-3, 2-6, 2-7, 2-9).
/// 사진(`photos`)은 갤러리 작업에서 다루므로 여기서 읽지 않는다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'models.dart';
import 'providers.dart' show EnteredBasicInfo, EnteredDetails;

/// 프로필 입력 상태. 서버가 저장하지 않고 계산한다(2절 머리말).
enum SetupStatus {
  /// 기본 정보만 저장했고 첫 카드 생성 전이다.
  inProgress,

  /// 첫 카드 생성 작업이 있다.
  completed;

  static SetupStatus? parse(String raw) =>
      values.where((v) => v.name == raw).firstOrNull;
}

/// 2-1 목록의 한 줄이다.
class ProfileSummary {
  const ProfileSummary({
    required this.profileId,
    required this.name,
    required this.gender,
    required this.setupStatus,
  });

  factory ProfileSummary.fromJson(Map<String, dynamic> json) => ProfileSummary(
    profileId: json['profileId'] as String,
    name: json['name'] as String,
    gender: json['gender'] as String,
    setupStatus: SetupStatus.parse(json['setupStatus'] as String),
  );

  final String profileId;
  final String name;
  final String gender;

  /// 모르는 값이면 `null` 이다.
  final SetupStatus? setupStatus;
}

/// 2-2, 2-3, 2-4 가 돌려주는 프로필이다(api-spec 의 Profile).
class RemoteProfile {
  const RemoteProfile({
    required this.profileId,
    required this.setupStatus,
    required this.basicInfo,
    required this.details,
    required this.lifeFacts,
    this.symptomNote,
  });

  factory RemoteProfile.fromJson(Map<String, dynamic> json) {
    final condition = json['condition'] as Map<String, dynamic>;
    final stage = ConditionStage.parse(condition['stage'] as String);
    if (stage == null) {
      throw FormatException('모르는 condition.stage: ${condition['stage']}');
    }
    return RemoteProfile(
      profileId: json['profileId'] as String,
      setupStatus: SetupStatus.parse(json['setupStatus'] as String),
      basicInfo: EnteredBasicInfo(
        name: json['name'] as String,
        gender: json['gender'] as String,
        birthDate: json['birthDate'] as String,
        stage: stage,
      ),
      symptomNote: condition['symptomNote'] as String?,
      details: EnteredDetails(
        occupation: json['occupation'] as String?,
        hometown: json['hometown'] as String?,
        hobby: json['hobby'] as String?,
        family: json['family'] as String?,
      ),
      lifeFacts: [
        for (final item in json['lifeFacts'] as List)
          LifeFact.fromJson(item as Map<String, dynamic>),
      ],
    );
  }

  final String profileId;

  /// 모르는 값이면 `null` 이다.
  final SetupStatus? setupStatus;

  final EnteredBasicInfo basicInfo;
  final EnteredDetails details;
  final String? symptomNote;

  /// 일대기에 담긴 이야기. 먼저 담은 것부터다. 일대기 전용 목록 API 는 없어
  /// 2-3 의 이 목록으로 일대기를 그린다.
  final List<LifeFact> lifeFacts;
}

/// 프로필 API 를 부른다. 실패는 [ApiFailure] 로 던진다.
class ProfileApi {
  const ProfileApi(this._client);

  final ApiClient _client;

  static const _base = '/api/v1/profiles';
  static const _lifeFactBase = '/api/v1/life-facts';

  /// 2-1 현재 계정의 프로필 목록. 만든 순서대로다.
  Future<List<ProfileSummary>> list() async {
    final body = await _client.get(_base);
    return _read(
      () => [
        for (final item in body['profiles'] as List)
          ProfileSummary.fromJson(item as Map<String, dynamic>),
      ],
    );
  }

  /// 2-2 기본 정보 입력을 마칠 때 프로필을 만든다.
  Future<RemoteProfile> create(EnteredBasicInfo info) async {
    final body = await _client.post(_base, {
      ..._basicBody(info),
      // 메모는 아직 입력받지 않는다.
      'condition': {'stage': info.stage.name, 'symptomNote': null},
    });
    return _read(() => RemoteProfile.fromJson(body));
  }

  /// 2-3 한 분의 프로필.
  Future<RemoteProfile> get(String profileId) async {
    final body = await _client.get('$_base/$profileId');
    return _read(() => RemoteProfile.fromJson(body));
  }

  /// 2-4 기본 정보를 고친다. 메모(`symptomNote`)는 보내지 않아 그대로 둔다.
  Future<RemoteProfile> updateBasicInfo(
    String profileId,
    EnteredBasicInfo info,
  ) async {
    final body = await _client.patch('$_base/$profileId', {
      ..._basicBody(info),
      'condition': {'stage': info.stage.name},
    });
    return _read(() => RemoteProfile.fromJson(body));
  }

  /// 2-4 세부 정보 네 항목을 고친다. 비운 항목은 `null` 로 보내 지운다.
  Future<RemoteProfile> updateDetails(
    String profileId,
    EnteredDetails details,
  ) async {
    final body = await _client.patch('$_base/$profileId', {
      'occupation': details.occupation,
      'hometown': details.hometown,
      'hobby': details.hobby,
      'family': details.family,
    });
    return _read(() => RemoteProfile.fromJson(body));
  }

  /// 2-8 프로필 하나를 지운다.
  Future<void> delete(String profileId) => _client.delete('$_base/$profileId');

  /// 2-6 일대기에 이야기를 담는다. 서버가 만든 `factId` 를 돌려받는다.
  Future<LifeFact> createLifeFact(
    String profileId, {
    required String storyCategory,
    required String title,
    required String content,
    required int imageNumber,
  }) async {
    final body = await _client.post('$_base/$profileId/life-facts', {
      'storyCategory': storyCategory,
      'title': title,
      'content': content,
      'imageNumber': imageNumber,
    });
    return _read(() => LifeFact.fromJson(body));
  }

  /// 2-7 담은 이야기를 고친다. 수정 화면은 네 항목을 모두 보낸다.
  /// 담은 날짜(`createdAt`)는 바뀌지 않는다.
  Future<LifeFact> updateLifeFact(
    String factId, {
    required String storyCategory,
    required String title,
    required String content,
    required int imageNumber,
  }) async {
    final body = await _client.patch('$_lifeFactBase/$factId', {
      'storyCategory': storyCategory,
      'title': title,
      'content': content,
      'imageNumber': imageNumber,
    });
    return _read(() => LifeFact.fromJson(body));
  }

  /// 2-9 담은 이야기를 지운다. 되돌릴 수 없다.
  Future<void> deleteLifeFact(String factId) =>
      _client.delete('$_lifeFactBase/$factId');

  static Map<String, Object?> _basicBody(EnteredBasicInfo info) => {
    'name': info.name,
    'gender': info.gender,
    'birthDate': info.birthDate,
  };

  /// 성공 응답이 계약과 다르면 성공으로 넘기지 않는다.
  static T _read<T>(T Function() parse) {
    try {
      return parse();
    } on TypeError catch (error) {
      throw ApiUnexpectedResponseFailure('프로필 응답 모양이 다르다: $error');
    } on FormatException catch (error) {
      throw ApiUnexpectedResponseFailure(error.message);
    }
  }
}

/// 프로필 저장과 불러오기 실패를 보호자에게 보여줄 문구로 옮긴다.
///
/// 서버의 `errorCode` 는 명세 2절의 값만 구분한다. 모르는 실패는 다시 시도하게
/// 안내하고 원인을 지어내지 않는다.
String profileFailureMessage(ApiFailure failure) => switch (failure) {
  ApiServerFailure(errorCode: 'PROFILE_LIMIT_EXCEEDED') =>
    '어르신은 세 분까지 등록할 수 있어요.',
  ApiServerFailure(errorCode: 'PROFILE_NOT_FOUND') =>
    '어르신 정보를 찾지 못했어요. 목록을 다시 불러와 주세요.',
  ApiServerFailure(errorCode: 'LIFE_FACT_NOT_FOUND') =>
    '이야기를 찾지 못했어요. 이미 지운 이야기일 수 있어요.',
  // 카드를 만드는 동안 카드에 쓰는 정보를 고치거나 지우면 거절된다(2-4, 2-7,
  // 2-9). 다 만들면 다시 고칠 수 있다.
  ApiServerFailure(errorCode: 'CARD_GENERATION_IN_PROGRESS') =>
    '대화 카드를 만드는 중이라 지금은 바꿀 수 없어요. 카드가 준비된 뒤 다시 시도해주세요.',
  ApiServerFailure(statusCode: 401) || ApiSignedOutFailure() =>
    '로그인이 풀렸어요. 다시 로그인해주세요.',
  ApiNetworkFailure() => '서버에 연결하지 못했어요. 인터넷 연결을 확인하고 다시 시도해주세요.',
  ApiUnexpectedResponseFailure() => '서버 응답을 읽지 못했어요. 잠시 뒤 다시 시도해주세요.',
  ApiServerFailure() => '처리하지 못했어요. 잠시 뒤 다시 시도해주세요.',
};

final profileApiProvider = Provider<ProfileApi>(
  (ref) => ProfileApi(ref.watch(apiClientProvider)),
);
