/// 일대기 목 이야기다. 값은 모두 합성이다.
///
/// 분류와 이미지 번호가 서버 명세에 없어 `assets/mock/profile.json` 대신 여기에
/// 둔다. `LifeFact` 를 새 명세로 바꾸는 단계에서 목 데이터 원본으로 옮긴다.
/// 대화 카드와 리포트처럼 목 데이터 한 벌을 모든 어르신이 함께 쓴다.
library;

import 'life_story.dart';

final sampleLifeStories = <LifeStory>[
  _story(
    'story_demo_001',
    LifeStoryCategory.family,
    '남편을 처음 만난 날',
    '시장 골목 끝 국숫집에서 처음 만나셨대요.\n비가 와서 우산을 같이 쓰고 돌아오셨다고 해요.',
    2,
    '2026-08-22T10:00:00+09:00',
  ),
  _story(
    'story_demo_002',
    LifeStoryCategory.family,
    '첫째 딸이 태어나던 겨울',
    '눈이 많이 오던 해였대요.\n연탄을 넉넉히 들여놓고 아기를 기다리셨다고 해요.',
    4,
    '2026-09-03T19:20:00+09:00',
  ),
  _story(
    'story_demo_003',
    LifeStoryCategory.family,
    '손주를 처음 안아 본 날',
    '손이 떨려서 한참을 앉아서만 안으셨대요.',
    1,
    '2026-09-28T15:40:00+09:00',
  ),
  _story(
    'story_demo_004',
    LifeStoryCategory.hobby,
    '베란다 화분 이야기',
    '고추와 상추를 화분에 길러 이웃과 나눠 드셨대요.',
    3,
    '2026-08-30T09:10:00+09:00',
  ),
  _story(
    'story_demo_005',
    LifeStoryCategory.hobby,
    '노래교실 친구들',
    '수요일마다 노래교실에 가셨어요.\n끝나면 친구들과 꼭 차를 한잔하고 오셨대요.',
    5,
    '2026-09-21T11:30:00+09:00',
  ),
  _story(
    'story_demo_006',
    LifeStoryCategory.work,
    '내 가게를 연 날',
    '작은 수선집 간판을 직접 고르셨대요.',
    2,
    '2026-09-10T14:00:00+09:00',
  ),
  _story(
    'story_demo_007',
    LifeStoryCategory.hometown,
    '은행나무가 있던 골목',
    '집 앞 은행나무 아래에서 동네 아이들과 놀았다고 하셨어요.',
    1,
    '2026-09-05T16:45:00+09:00',
  ),
  _story(
    'story_demo_008',
    LifeStoryCategory.friend,
    '오래된 계모임',
    '한 달에 한 번 모여 밥을 먹는 모임을 오래 이어 오셨대요.',
    3,
    '2026-09-14T13:15:00+09:00',
  ),
  _story(
    'story_demo_009',
    LifeStoryCategory.travel,
    '신혼여행은 경주로',
    '기차를 타고 가서 불국사 앞에서 사진을 찍으셨대요.',
    4,
    '2026-09-25T18:00:00+09:00',
  ),
  _story(
    'story_demo_010',
    LifeStoryCategory.other,
    '좋아하시던 국수',
    '멸치 국물에 김가루를 듬뿍 올린 국수를 좋아하셨어요.',
    2,
    '2026-09-18T12:20:00+09:00',
  ),
];

LifeStory _story(
  String id,
  LifeStoryCategory category,
  String title,
  String content,
  int imageNumber,
  String createdAt,
) => LifeStory(
  id: id,
  category: category,
  title: title,
  content: content,
  imageNumber: imageNumber,
  createdAt: DateTime.parse(createdAt).toLocal(),
);
