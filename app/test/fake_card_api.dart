// 서버 대신 쓰는 대화 카드 API 대역이다.
//
// 앱은 카드를 서버(API 4절)에서만 받는다. 카드 화면, 면회와 소감을 확인하는
// 테스트는 이 대역과 목 묶음(`assets/mock/conversation-cards.json`)을 쓴다.
// 값은 모두 합성이다.

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:saerok/data/card_api.dart';
import 'package:saerok/data/mock_repository.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/data/visit_api.dart';
import 'package:saerok/features/visit/pending_uploads.dart';
import 'package:saerok/features/visit/visit_photos.dart';

import 'fake_pending_uploads.dart';
import 'fake_visit_api.dart';
import 'fake_visit_photos.dart';

/// 4-2 가 차례로 돌려줄 상태를 정해 둔다. 마지막 값은 그 뒤로 계속 돌려준다.
class FakeCardApi implements CardApi {
  FakeCardApi({
    List<CardGenerationStatus> statuses = const [CardGenerationStatus.ready],
    this.onRequest = CardGenerationStatus.running,
  }) : _statuses = [...statuses];

  final List<CardGenerationStatus> _statuses;

  /// 4-1 의 응답.
  final CardGenerationStatus onRequest;

  final calls = <String>[];

  /// 요청에 쓴 프로필 ID.
  final profileIds = <String>[];

  @override
  Future<CardGenerationStatus> requestGeneration(String profileId) async {
    calls.add('request');
    profileIds.add(profileId);
    return onRequest;
  }

  @override
  Future<CardGenerationStatus> status(String profileId) async {
    calls.add('status');
    profileIds.add(profileId);
    return _statuses.length > 1 ? _statuses.removeAt(0) : _statuses.single;
  }

  @override
  Future<CardSet> current(String profileId) async {
    calls.add('current');
    profileIds.add(profileId);
    return const MockRepository().loadCardSet();
  }
}

/// 목 카드 묶음이 준비된 상태로 시작한다. 고른 어르신이 없어도 묶음을 읽는다.
///
/// 녹음을 시작하면 그 묶음으로 회차를 만드는 대역([FakeVisitApi])도 함께 넣는다.
final withMockCards = mockCardsWith();

/// [withMockCards] 와 같다. 회차 요청을 확인하려면 [visitApi] 를 넘긴다.
/// 기기에 남기는 녹음 기록을 확인하려면 [pendingUploads] 를, 면회 사진은
/// [visitPhotos] 를 넘긴다.
List<Override> mockCardsWith({
  FakeVisitApi? visitApi,
  FakePendingUploads? pendingUploads,
  FakeVisitPhotos? visitPhotos,
}) => [
  visitApiProvider.overrideWith((ref) => visitApi ?? FakeVisitApi()),
  pendingUploadsProvider.overrideWith(
    (ref) => pendingUploads ?? FakePendingUploads(),
  ),
  visitPhotosProvider.overrideWith((ref) => visitPhotos ?? FakeVisitPhotos()),
  cardApiProvider.overrideWithValue(FakeCardApi()),
  currentCardSetProvider.overrideWith(
    (ref) => const MockRepository().loadCardSet(),
  ),
];
