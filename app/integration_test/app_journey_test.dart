// 앱 전체 여정을 연결한 기기나 에뮬레이터에서 돌린다.
//
//     flutter test integration_test/app_journey_test.dart
//
// 여정 본문은 `test/journey/app_journey.dart` 이며 `flutter test` 도 같은 여정을
// 호스트에서 돌린다(`test/app_journey_test.dart`). 서버와 마이크는 기기에서도
// 대역이다. 실제 마이크, STT, 리포트 모델과 운영 서버는 확인하지 않는다.

import 'package:integration_test/integration_test.dart';

import '../test/journey/app_journey.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  defineAppJourneyTests();
}
