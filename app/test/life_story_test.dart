// 일대기(H) 화면을 확인한다. 이야기는 목 데이터이고 값은 모두 합성이다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/app/router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/life_story/life_story.dart';
import 'package:saerok/widgets/app_surfaces.dart';

import 'sample_profile.dart';

/// 세부 정보 중 하시던 일과 가족만 적은 어르신.
class _ProfileWithDetails extends CareProfilesNotifier {
  @override
  CareProfiles build() => const CareProfiles(
    entries: [
      CareProfileEntry(
        id: sampleProfileId,
        basicInfo: sampleBasicInfo,
        details: EnteredDetails(
          occupation: '수선집을 하셨어요.',
          family: '딸 둘과 아들 하나를 두셨어요.',
        ),
      ),
    ],
    selectedId: sampleProfileId,
  );
}

Profile _profile({String id = 'p1', String? occupation, String? family}) =>
    Profile(
      profileId: id,
      name: '김새록',
      gender: 'female',
      birthDate: '1943-03-12',
      ageRange: '80s',
      stage: null,
      lifeFactIds: const [],
      photoIds: const [],
      occupation: occupation,
      family: family,
    );

LifeStory _story(String id, LifeStoryCategory category, String date) =>
    LifeStory(
      id: id,
      category: category,
      title: id,
      content: '내용',
      imageNumber: 1,
      createdAt: DateTime.parse(date),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('일대기 묶음', () {
    test('세부 정보는 적은 항목만 이야기가 되고 날짜가 없다', () {
      final stories = detailStoriesOf(
        _profile(occupation: '수선집', family: '딸 둘'),
      );

      expect(stories.map((s) => s.title), ['하시던 일', '가족']);
      expect(stories.map((s) => s.category), [
        LifeStoryCategory.work,
        LifeStoryCategory.family,
      ]);
      expect(stories.every((s) => s.createdAt == null), isTrue);
      expect(stories.every((s) => s.isProfileDetail), isTrue);
    });

    test('세부 정보 이야기의 이미지 번호는 늘 같고 1~5 사이다', () {
      for (final field in ['occupation', 'hometown', 'hobby', 'family']) {
        final number = detailImageNumber('p1', field);
        expect(number, inInclusiveRange(1, lifeStoryImageCount));
        expect(detailImageNumber('p1', field), number);
      }
      final numbers = {
        for (var i = 0; i < 20; i++) detailImageNumber('profile-$i', 'family'),
      };
      expect(numbers.length, greaterThan(1), reason: '어르신마다 다르게 나온다');
    });

    test('목차는 세부 정보를 먼저 두고 나머지는 먼저 담은 것부터다', () {
      final book = LifeStoryBook(
        profile: _profile(family: '딸 둘'),
        stories: [
          _story('늦게', LifeStoryCategory.family, '2026-09-20'),
          ...detailStoriesOf(_profile(family: '딸 둘')),
          _story('먼저', LifeStoryCategory.family, '2026-09-01'),
          _story('다른 분류', LifeStoryCategory.travel, '2026-09-05'),
        ],
      );

      expect(book.storiesIn(LifeStoryCategory.family).map((s) => s.title), [
        '가족',
        '먼저',
        '늦게',
      ]);
      expect(book.total, 4);
    });

    test('최근 이야기는 최근 것부터 세 편이고 세부 정보는 넣지 않는다', () {
      final book = LifeStoryBook(
        profile: _profile(family: '딸 둘'),
        stories: [
          ...detailStoriesOf(_profile(family: '딸 둘')),
          _story('1일', LifeStoryCategory.family, '2026-09-01'),
          _story('4일', LifeStoryCategory.hobby, '2026-09-04'),
          _story('3일', LifeStoryCategory.work, '2026-09-03'),
          _story('2일', LifeStoryCategory.other, '2026-09-02'),
        ],
      );

      expect(book.recent().map((s) => s.title), ['4일', '3일', '2일']);
    });
  });

  group('일대기 화면', () {
    Future<void> openAt(
      WidgetTester tester,
      String location, {
      bool reduceMotion = false,
      double textScale = 1,
    }) async {
      tester.view.physicalSize = const Size(1236, 2751);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final router = buildRouter();
      router.go(location);

      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              careProfilesProvider.overrideWith(_ProfileWithDetails.new),
            ],
            child: MaterialApp.router(
              theme: buildAppTheme(),
              routerConfig: router,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: reduceMotion,
                  textScaler: TextScaler.linear(textScale),
                ),
                child: child!,
              ),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();
    }

    Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    double topOf(WidgetTester tester, String text) =>
        tester.getTopLeft(find.text(text)).dy;

    testWidgets('표지에 이름과 담긴 이야기 수를 보여준다', (tester) async {
      await openAt(tester, AppRoutes.album);

      expect(find.text('쌓아온 이야기'), findsOneWidget);
      expect(find.text('책을 눌러 펼쳐 보세요'), findsOneWidget);
      expect(find.text('김새록님의'), findsOneWidget);
      expect(find.text('일대기'), findsOneWidget);
      // 세부 정보 두 편과 목 이야기 열 편.
      expect(find.text('지금까지 12편의 이야기가 담겨 있어요'), findsOneWidget);
    });

    testWidgets('책을 누르면 펼친 장으로 가고 돌아오면 표지가 다시 덮인다', (tester) async {
      await openAt(tester, AppRoutes.album);

      await tapAndSettle(tester, find.bySemanticsLabel('일대기 책 펼치기'));

      expect(find.text('어떤 이야기를 볼까요?'), findsOneWidget);
      expect(find.text('김새록'), findsOneWidget);
      expect(find.text('1943년 3월 12일'), findsOneWidget);

      await tester.tap(find.byTooltip('뒤로'));
      await tester.pumpAndSettle();

      expect(find.text('김새록님의'), findsOneWidget);
    });

    testWidgets('애니메이션 줄이기가 켜져 있으면 표지를 넘기지 않고 바로 간다', (tester) async {
      await openAt(tester, AppRoutes.album, reduceMotion: true);

      await tester.tap(find.bySemanticsLabel('일대기 책 펼치기'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('어떤 이야기를 볼까요?'), findsOneWidget);
    });

    testWidgets('분류 여섯 칸과 기타, 편수를 보여준다', (tester) async {
      await openAt(tester, AppRoutes.albumBook);

      for (final category in LifeStoryCategory.values) {
        expect(find.widgetWithText(AppCard, category.label), findsOneWidget);
      }
      // 가족은 세부 정보 하나와 목 이야기 셋, 일은 세부 정보 하나와 목 이야기 하나.
      expect(find.text('4편'), findsOneWidget);
      expect(find.text('2편'), findsNWidgets(2), reason: '일과 취미');
      expect(
        tester.getTopLeft(find.widgetWithText(AppCard, '기타')).dy,
        greaterThan(tester.getTopLeft(find.widgetWithText(AppCard, '여행')).dy),
        reason: '기타는 여섯 칸 아래에 따로 둔다',
      );
    });

    testWidgets('최근 추가된 이야기는 최근 것부터 세 편이다', (tester) async {
      await openAt(tester, AppRoutes.albumBook);

      expect(find.text('최근 추가된 이야기'), findsOneWidget);
      final first = topOf(tester, '손주를 처음 안아 본 날');
      final second = topOf(tester, '신혼여행은 경주로');
      final third = topOf(tester, '노래교실 친구들');
      expect(first, lessThan(second));
      expect(second, lessThan(third));
      expect(find.text('9월 28일'), findsOneWidget);
    });

    testWidgets('최근 이야기를 누르면 펼치고 뒤로 가면 그 분류의 목차다', (tester) async {
      await openAt(tester, AppRoutes.albumBook);

      await tapAndSettle(tester, find.text('신혼여행은 경주로'));

      expect(find.text('여행 · 1장'), findsOneWidget);

      await tester.tap(find.byTooltip('뒤로'));
      await tester.pumpAndSettle();

      expect(find.text('김새록님의 여행에 대한\n이야기입니다.'), findsOneWidget);
    });

    testWidgets('목차는 세부 정보부터, 나머지는 먼저 담은 것부터다', (tester) async {
      await openAt(tester, AppRoutes.albumCategoryOf('family'));

      expect(find.text('김새록님의 가족에 대한\n이야기입니다.'), findsOneWidget);
      expect(find.text('목차'), findsOneWidget);
      final titles = ['가족', '남편을 처음 만난 날', '첫째 딸이 태어나던 겨울', '손주를 처음 안아 본 날'];
      for (var i = 1; i < titles.length; i++) {
        expect(
          topOf(tester, titles[i - 1]),
          lessThan(topOf(tester, titles[i])),
        );
      }
    });

    testWidgets('이야기가 없는 분류는 비어 있다고 알린다', (tester) async {
      await openAt(tester, AppRoutes.albumCategoryOf('hometown'));
      // 고향 세부 정보를 적지 않았고 목 이야기는 한 편이다.
      expect(find.text('은행나무가 있던 골목'), findsOneWidget);

      await openAt(tester, AppRoutes.albumCategoryOf('unknown'));
      expect(find.text('찾을 수 없는 이야기 묶음이에요.'), findsOneWidget);
    });

    testWidgets('이야기를 이전, 다음으로 넘기고 뒤로 가면 목차다', (tester) async {
      await openAt(tester, AppRoutes.albumCategoryOf('family'));
      await tapAndSettle(tester, find.text('가족'));

      expect(find.text('가족 · 1장'), findsOneWidget);
      expect(find.text('딸 둘과 아들 하나를 두셨어요.'), findsOneWidget);
      expect(
        find.textContaining('년 '),
        findsNothing,
        reason: '세부 정보 이야기는 담은 날짜가 없다',
      );
      final previous = find.widgetWithText(FilledButton, '이전 이야기');
      expect(tester.widget<FilledButton>(previous).onPressed, isNull);

      await tapAndSettle(tester, find.text('다음 이야기'));

      expect(find.text('가족 · 2장'), findsOneWidget);
      expect(find.text('남편을 처음 만난 날'), findsOneWidget);
      expect(find.text('2026년 8월 22일'), findsOneWidget);

      await tapAndSettle(tester, find.text('다음 이야기'));
      await tapAndSettle(tester, find.text('다음 이야기'));

      expect(find.text('가족 · 4장'), findsOneWidget);
      final next = find.widgetWithText(FilledButton, '다음 이야기');
      expect(tester.widget<FilledButton>(next).onPressed, isNull);

      await tester.tap(find.byTooltip('뒤로'));
      await tester.pumpAndSettle();

      expect(find.text('김새록님의 가족에 대한\n이야기입니다.'), findsOneWidget);
    });

    testWidgets('이미지 파일이 없으면 분류와 번호로 자리를 채운다', (tester) async {
      await openAt(tester, AppRoutes.albumStoryOf('family', 'story_demo_001'));
      // asset 을 읽다 실패하는 것도 실제 비동기 처리다.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();

      expect(find.text('가족 2'), findsOneWidget);
    });

    testWidgets('글자를 두 배로 키워도 깨지지 않는다', (tester) async {
      for (final location in [
        AppRoutes.album,
        AppRoutes.albumBook,
        AppRoutes.albumCategoryOf('family'),
        AppRoutes.albumStoryOf('family', 'story_demo_001'),
      ]) {
        await openAt(tester, location, textScale: 2);
        expect(tester.takeException(), isNull, reason: location);
      }
    });
  });
}
