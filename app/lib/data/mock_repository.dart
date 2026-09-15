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

  Future<ProfileBundle> loadProfile() async {
    return ProfileBundle.fromJson(await _read('profile.json'));
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

  Future<ChangeProposal> loadChangeProposal() async {
    final json = await _read('caregiver-evaluation.json');
    return ChangeProposal.fromJson(
      json['changeProposal'] as Map<String, dynamic>,
    );
  }
}
