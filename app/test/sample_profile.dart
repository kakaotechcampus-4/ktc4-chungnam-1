// 어르신 한 분을 등록한 상태로 시작하는 테스트에서 쓴다.
//
// 앱은 빈 목록에서 시작한다. 대화 카드, 면회, 리포트처럼 어르신이 있어야
// 쓰는 화면을 확인할 때 이 상태를 주입한다. 값은 모두 합성이다.

import 'package:saerok/data/models.dart';
import 'package:saerok/data/providers.dart';

const sampleProfileId = 'sample';

const sampleBasicInfo = EnteredBasicInfo(
  name: '김새록',
  gender: 'female',
  birthDate: '1943-03-12',
  stage: ConditionStage.mildDementia,
);

class SampleCareProfiles extends CareProfilesNotifier {
  @override
  CareProfiles build() => const CareProfiles(
    entries: [
      CareProfileEntry(id: sampleProfileId, basicInfo: sampleBasicInfo),
    ],
    selectedId: sampleProfileId,
  );
}

/// 어르신 한 분을 등록하고 고른 상태로 시작한다.
final withSampleProfile = careProfilesProvider.overrideWith(
  SampleCareProfiles.new,
);
