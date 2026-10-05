import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'models.dart';

/// `assets/mock/` 의 합성 목 데이터를 읽는다.
///
/// 원본은 `docs/architecture/mock/` 이며 여기는 사본이다. Flutter 가 패키지 루트
/// 밖을 asset 으로 읽지 못해 복사해 둔 것이고, `test/mock_data_sync_test.dart`
/// 가 두 벌이 같은지 확인한다.
///
/// 서버 연동이 붙으면 이 클래스와 같은 자리를 다른 구현이 대신한다. 화면은
/// provider 만 보므로 화면 코드를 고치지 않아도 된다.
class MockRepository {
  const MockRepository();

  static const _dir = 'assets/mock';

  Future<Map<String, dynamic>> _read(String fileName) async {
    final raw = await rootBundle.loadString('$_dir/$fileName');
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<Account> loadAccount() async {
    final json = await _read('account.json');
    return Account.fromJson(json['account'] as Map<String, dynamic>);
  }

  /// 목 사진의 `imageUrl` 은 계약 예시 주소라 열리지 않는다. 화면에서 볼 수
  /// 있도록 앱에 든 합성 그림으로 바꿔 끼운다. 공동 목 데이터는 계약 형식대로
  /// 두고 이 사본을 읽을 때만 바꾼다.
  static const _demoPhotoImages = {
    'profile_photo_demo_001': 'asset:assets/images/family.webp',
    'profile_photo_demo_002': 'asset:assets/images/visitation.webp',
    'profile_photo_demo_003': 'asset:assets/images/patient.webp',
  };

  Future<ProfileBundle> loadProfile() async {
    final json = await _read('profile.json');
    for (final photo in json['photos'] as List? ?? const []) {
      final map = photo as Map<String, dynamic>;
      final image = _demoPhotoImages[map['photoId']];
      if (image != null) map['imageUrl'] = image;
    }
    return ProfileBundle.fromJson(json);
  }

  Future<List<ConversationCard>> loadConversationCards() async {
    final json = await _read('conversation-cards.json');
    final cards = json['conversationCards'] as Map<String, dynamic>;
    return (cards['cards'] as List)
        .map((e) => ConversationCard.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<VisitSession> loadVisitSession() async {
    final json = await _read('visit-session.json');
    return VisitSession.fromJson(json['visitSession'] as Map<String, dynamic>);
  }

  Future<VisitReport> loadVisitReport() async {
    final json = await _read('visit-report.json');
    return VisitReport.fromJson(json['visitReport'] as Map<String, dynamic>);
  }

  Future<CaregiverEvaluation> loadCaregiverEvaluation() async {
    final json = await _read('caregiver-evaluation.json');
    return CaregiverEvaluation.fromJson(
      json['caregiverEvaluation'] as Map<String, dynamic>,
    );
  }

  /// 리포트가 다 만들어지기를 기다린다.
  ///
  /// 목 데이터는 정해진 시간을 센다. 실제 분석 시간은 AI 영역이 정하고, 서버를
  /// 붙이면 이 자리가 알림 구독이나 조회로 바뀐다. 화면과 알림 상태는 그대로
  /// 둔다.
  Future<void> awaitReportReady() => Future<void>.delayed(reportDelay);

  /// 목 데이터에서 리포트가 만들어지기까지 걸리는 시간.
  static const reportDelay = Duration(seconds: 5);

  Future<ChangeProposal> loadChangeProposal() async {
    final json = await _read('caregiver-evaluation.json');
    return ChangeProposal.fromJson(
      json['changeProposal'] as Map<String, dynamic>,
    );
  }
}
