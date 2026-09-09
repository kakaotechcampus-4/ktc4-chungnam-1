/// 환자 정보 최초 입력(B-2 ~ B-8)의 단계 정의다.
///
/// 생애 정보 항목은 `docs/architecture/data-contracts.md` 의 `LifeFact.category`
/// 와 `LifeFactCollectionState` 를 따른다. 계약에 없는 항목을 만들지 않는다.
/// 질문 문구는 피그마 B-3 ~ B-6 에서 옮겼다.
library;

class LifeFactStep {
  const LifeFactStep({
    required this.category,
    required this.question,
    required this.examples,
  });

  /// `LifeFact.category` 값.
  final String category;

  /// 화면 제목으로 쓰는 질문.
  final String question;

  /// 어떻게 답하면 되는지 보여주는 예시 두 줄.
  final List<String> examples;
}

const lifeFactSteps = <LifeFactStep>[
  LifeFactStep(
    category: 'occupation',
    question: '어르신은 예전에\n어떤 일을 하셨나요?',
    examples: [
      '"30년 동안 초등학교 선생님을 하셨어요."',
      '"동네에서 작은 슈퍼마켓을 운영하셨어요."',
    ],
  ),
  LifeFactStep(
    category: 'hometown',
    question: '고향이나 사셨던\n동네는 어디인가요?',
    examples: [
      '"태어나신 곳은 부산 영도구예요."',
      '"젊은 시절은 주로 대전에서 보내셨어요."',
    ],
  ),
  LifeFactStep(
    category: 'hobby',
    question: '즐겨 하셨던 취미나\n관심사는 무엇인가요?',
    examples: [
      '"주말마다 등산을 즐겨 하셨어요."',
      '"화초 가꾸는 걸 참 좋아하셨어요."',
    ],
  ),
  LifeFactStep(
    category: 'family',
    question: '가족들에 대해 자세히\n이야기해 주세요.',
    examples: [
      '"자녀는 2남 1녀를 두셨어요."',
      '"스물다섯에 중매로 만나 결혼하셨어요."',
    ],
  ),
];

/// 입력 흐름 전체의 단계. 진행 표시의 분모가 된다.
enum SetupStage {
  basicInfo,
  lifeFacts,
  photo,
  photoTags;

  /// 진행 표시에 쓰는 전체 단계 수. 생애 정보는 항목마다 한 단계씩 센다.
  static int get total => 2 + lifeFactSteps.length + 1;
}
