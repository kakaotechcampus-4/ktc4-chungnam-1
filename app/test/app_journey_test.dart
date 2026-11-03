// 앱 전체 여정을 호스트에서 화면 없이 돌린다. 여정 본문은 `journey/app_journey.dart`
// 에 있고 `integration_test/app_journey_test.dart` 가 기기에서 같은 여정을 돈다.

import 'journey/app_journey.dart';

void main() => defineAppJourneyTests();
