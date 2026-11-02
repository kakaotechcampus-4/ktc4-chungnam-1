/// 일대기 화면이 쓰는 이야기 한 편과 책 한 권이다.
///
/// 화면은 서버 형식(`LifeFact`)을 직접 보지 않고 여기의 [LifeStory] 만 본다.
/// 서버 형식이 바뀌어도 고칠 곳을 [LifeStory.fromLifeFact] 한 군데로 모으려는
/// 것이다.
///
/// 분류(`storyCategory`)와 기본 이미지 번호(`imageNumber`)의 필드 이름은
/// 임시다(api-spec 미정 사항 11).
library;

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../profile_setup/setup_steps.dart';

/// 일대기의 분류. 여섯 칸과 아래의 긴 `기타` 칸이다.
///
/// [name] 은 경로와 기본 이미지 파일 이름에 쓴다.
enum LifeStoryCategory {
  family('가족', Icons.home_outlined),
  hobby('취미', Icons.local_florist_outlined),
  work('일', Icons.work_outline),
  hometown('고향', Icons.landscape_outlined),
  friend('친구', Icons.people_outline),
  travel('여행', Icons.luggage_outlined),
  other('기타', Icons.auto_stories_outlined);

  const LifeStoryCategory(this.label, this.icon);

  final String label;

  /// 흑백 아이콘이다. 화면에 색을 쓰지 않는다(`app/DESIGN.md`).
  final IconData icon;

  static LifeStoryCategory? parse(String raw) =>
      values.where((c) => c.name == raw).firstOrNull;
}

/// 분류마다 미리 만든 기본 이미지 수.
const lifeStoryImageCount = 5;

/// 기본 이미지 파일 경로. 파일이 없으면 화면이 임시 칸을 그린다.
String lifeStoryImageAsset(LifeStoryCategory category, int number) =>
    'assets/images/life-story-${category.name}-$number.webp';

/// 이야기 한 편.
class LifeStory {
  const LifeStory({
    required this.id,
    required this.category,
    required this.title,
    required this.content,
    required this.imageNumber,
    this.createdAt,
    this.detailField,
  });

  /// 일대기에 담긴 이야기를 화면용으로 바꾼다.
  ///
  /// 모르는 분류는 `기타` 에 둔다. 이야기를 숨기지 않고 보호자가 수정에서
  /// 분류를 고를 수 있게 하려는 것이다. 범위 밖 그림 번호도 같은 이유로 1~5
  /// 안으로 맞춘다.
  factory LifeStory.fromLifeFact(LifeFact fact) => LifeStory(
    id: fact.factId,
    category:
        LifeStoryCategory.parse(fact.storyCategory) ?? LifeStoryCategory.other,
    title: fact.title,
    content: fact.content,
    imageNumber: fact.imageNumber.clamp(1, lifeStoryImageCount),
    createdAt: DateTime.parse(fact.createdAt).toLocal(),
  );

  final String id;
  final LifeStoryCategory category;
  final String title;
  final String content;

  /// 기본 이미지 번호. 1부터 [lifeStoryImageCount] 까지다.
  final int imageNumber;

  /// 일대기에 담긴 시각. 세부 정보에서 온 이야기는 날짜가 없어 `null` 이다.
  final DateTime? createdAt;

  /// 세부 정보 네 항목(`occupation`, `hometown`, `hobby`, `family`)에서 온
  /// 이야기면 그 항목 이름이다. 이 이야기는 프로필 수정에서 고친다.
  final String? detailField;

  bool get isProfileDetail => detailField != null;
}

/// 이야기 입력 화면에서 받는 값. 추가(API 2-6)와 수정(2-7)에 같이 쓴다.
class LifeStoryDraft {
  const LifeStoryDraft({
    required this.category,
    required this.title,
    required this.content,
    required this.imageNumber,
  });

  final LifeStoryCategory category;

  /// [titleMaxLength] 자 이하. 계약상 제목과 내용은 비울 수 없다.
  final String title;
  final String content;
  final int imageNumber;

  /// `life_facts.title` 의 상한.
  static const titleMaxLength = 100;
}

/// 세부 정보 항목이 들어갈 분류.
const _detailCategories = {
  'occupation': LifeStoryCategory.work,
  'hometown': LifeStoryCategory.hometown,
  'hobby': LifeStoryCategory.hobby,
  'family': LifeStoryCategory.family,
};

/// 세부 정보 이야기의 기본 이미지 번호.
///
/// 서버에 저장할 칸이 없어서 고르지 않고 계산한다. 같은 어르신의 같은 항목은
/// 늘 같은 번호가 나오고, 어르신마다는 다르게 나온다. `String.hashCode` 는
/// 실행마다 같다는 보장이 없어 직접 계산한다.
int detailImageNumber(String profileId, String field) {
  var hash = 0;
  for (final unit in '$profileId:$field'.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return hash % lifeStoryImageCount + 1;
}

/// 세부 정보 네 항목 중 값이 있는 것을 이야기로 만든다.
List<LifeStory> detailStoriesOf(Profile profile) => [
  for (final step in lifeFactSteps)
    if (profile.detailOf(step.category) case final value?)
      LifeStory(
        id: 'detail-${step.category}',
        category: _detailCategories[step.category]!,
        title: step.label,
        content: value,
        imageNumber: detailImageNumber(profile.profileId, step.category),
        detailField: step.category,
      ),
];

/// 어르신 한 분의 일대기.
class LifeStoryBook {
  const LifeStoryBook({required this.profile, required this.stories});

  final Profile profile;
  final List<LifeStory> stories;

  int get total => stories.length;

  LifeStory? find(String id) => stories.where((s) => s.id == id).firstOrNull;

  /// 목차 순서. 세부 정보 이야기를 먼저 두고, 나머지는 먼저 담은 것부터다.
  ///
  /// 생애 시기순 정렬은 시기를 누가 어떤 단위로 정할지 합의한 뒤 바꾼다.
  List<LifeStory> storiesIn(LifeStoryCategory category) {
    final details = [
      for (final s in stories)
        if (s.category == category && s.isProfileDetail) s,
    ];
    final added = [
      for (final s in stories)
        if (s.category == category && !s.isProfileDetail) s,
    ]..sort((a, b) => a.createdAt!.compareTo(b.createdAt!));
    return [...details, ...added];
  }

  /// 최근에 담은 이야기. 날짜가 없는 세부 정보 이야기는 넣지 않는다.
  List<LifeStory> recent({int limit = 3}) {
    final dated = [
      for (final s in stories)
        if (s.createdAt != null) s,
    ]..sort((a, b) => b.createdAt!.compareTo(a.createdAt!));
    return dated.take(limit).toList();
  }
}

/// `1943-03-12` 를 `1943년 3월 12일` 로 바꾼다.
String birthDateLabel(String isoDate) {
  final date = DateTime.tryParse(isoDate);
  return date == null ? isoDate : fullDateLabel(date);
}

String fullDateLabel(DateTime date) =>
    '${date.year}년 ${date.month}월 ${date.day}일';

String shortDateLabel(DateTime date) => '${date.month}월 ${date.day}일';
