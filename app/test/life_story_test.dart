// 일대기(H) 화면을 확인한다. 이야기는 목 데이터이고 값은 모두 합성이다.

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/app/router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/life_story/life_story.dart';
import 'package:saerok/features/life_story/life_story_image.dart';
import 'package:saerok/features/life_story/life_story_providers.dart';
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

/// 새 이야기의 그림을 늘 3번으로 미리 고른다.
class _FixedRandom implements Random {
  @override
  int nextInt(int max) => 2;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
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

/// 화면에 [asset] 그림이 놓였는지 본다.
bool showsAsset(WidgetTester tester, String asset) => tester
    .widgetList<Image>(find.byType(Image))
    .any(
      (image) =>
          image.image is AssetImage &&
          (image.image as AssetImage).assetName == asset,
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

LifeFact _fact({String storyCategory = 'family', int imageNumber = 1}) =>
    LifeFact(
      factId: 'fact_001',
      storyCategory: storyCategory,
      title: '경주 여행',
      content: '불국사에 가셨대요.',
      imageNumber: imageNumber,
      createdAt: '2026-09-01T10:00:00+09:00',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('일대기 묶음', () {
    test('분류마다 기본 그림 다섯 장이 앱에 들어 있다', () {
      for (final category in LifeStoryCategory.values) {
        for (var n = 1; n <= lifeStoryImageCount; n++) {
          final path = lifeStoryImageAsset(category, n);
          expect(File(path).existsSync(), isTrue, reason: path);
        }
      }
    });

    test('담은 이야기는 분류, 제목, 내용, 그림 번호와 날짜를 그대로 쓴다', () {
      final story = LifeStory.fromLifeFact(
        _fact(storyCategory: 'travel', imageNumber: 4),
      );

      expect(story.id, 'fact_001');
      expect(story.category, LifeStoryCategory.travel);
      expect(story.title, '경주 여행');
      expect(story.content, '불국사에 가셨대요.');
      expect(story.imageNumber, 4);
      expect(
        story.createdAt!.isAtSameMomentAs(DateTime.utc(2026, 9, 1, 1)),
        isTrue,
      );
      expect(story.isProfileDetail, isFalse);
    });

    test('모르는 분류는 기타에, 범위 밖 그림 번호는 1~5 안에 둔다', () {
      final unknown = LifeStory.fromLifeFact(
        _fact(storyCategory: 'school', imageNumber: 9),
      );
      final zero = LifeStory.fromLifeFact(_fact(imageNumber: 0));

      expect(unknown.category, LifeStoryCategory.other);
      expect(unknown.imageNumber, lifeStoryImageCount);
      expect(zero.imageNumber, 1);
    });

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
              lifeStoryRandomProvider.overrideWithValue(_FixedRandom()),
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
      await tester.pumpAndSettle();
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

    testWidgets('이야기 위에 그 분류와 번호의 그림을 놓는다', (tester) async {
      await openAt(tester, AppRoutes.albumStoryOf('family', 'fact_demo_001'));

      expect(
        showsAsset(tester, 'assets/images/life-story-family-2.webp'),
        isTrue,
      );
    });

    testWidgets('그림 파일이 없는 번호는 분류와 번호로 자리를 채운다', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LifeStoryImage(category: LifeStoryCategory.family, number: 9),
        ),
      );
      // asset 을 읽다 실패하는 것도 실제 비동기 처리다.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();

      expect(find.text('가족 9'), findsOneWidget);
    });

    testWidgets('글자를 두 배로 키워도 깨지지 않는다', (tester) async {
      for (final location in [
        AppRoutes.album,
        AppRoutes.albumBook,
        AppRoutes.albumCategoryOf('family'),
        AppRoutes.albumStoryOf('family', 'fact_demo_001'),
      ]) {
        await openAt(tester, location, textScale: 2);
        expect(tester.takeException(), isNull, reason: location);
      }
    });

    group('이야기 추가, 수정, 삭제', () {
      Future<void> openAdd(WidgetTester tester) async {
        await openAt(tester, AppRoutes.albumBook);
        await tapAndSettle(tester, find.text('이야기 추가하기'));
      }

      FilledButton saveButton(WidgetTester tester, String label) =>
          tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));

      Future<void> fill(
        WidgetTester tester,
        String title,
        String content,
      ) async {
        await tester.enterText(find.byType(TextField).at(0), title);
        await tester.enterText(find.byType(TextField).at(1), content);
        await tester.pump();
      }

      Future<void> waitForImages(WidgetTester tester) async {
        // asset 을 읽다 실패하는 것도 실제 비동기 처리다.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pumpAndSettle();
      }

      testWidgets('분류, 제목, 내용을 모두 채워야 담을 수 있다', (tester) async {
        await openAdd(tester);

        expect(find.text('분류를 고르면 그림을 고를 수 있어요.'), findsOneWidget);
        expect(saveButton(tester, '이야기 담기').onPressed, isNull);

        await fill(tester, '첫 기차 여행', '부산까지 기차를 타고 가셨대요.');
        expect(
          saveButton(tester, '이야기 담기').onPressed,
          isNull,
          reason: '분류가 없다',
        );

        await tapAndSettle(tester, find.text('여행'));
        expect(saveButton(tester, '이야기 담기').onPressed, isNotNull);

        await fill(tester, '   ', '부산까지 기차를 타고 가셨대요.');
        expect(
          saveButton(tester, '이야기 담기').onPressed,
          isNull,
          reason: '빈칸뿐인 제목',
        );
      });

      testWidgets('담은 이야기는 최근 이야기에 바로 보이고 미리 고른 그림이 붙는다', (tester) async {
        await openAdd(tester);
        await tapAndSettle(tester, find.text('여행'));
        await fill(tester, '첫 기차 여행', '부산까지 기차를 타고 가셨대요.');
        await tapAndSettle(tester, find.text('이야기 담기'));

        expect(find.text('이야기를 담았어요.'), findsOneWidget);
        expect(find.text('어떤 이야기를 볼까요?'), findsOneWidget);
        expect(
          topOf(tester, '첫 기차 여행'),
          lessThan(topOf(tester, '손주를 처음 안아 본 날')),
          reason: '가장 최근에 담았다',
        );

        await tapAndSettle(tester, find.text('첫 기차 여행'));
        await waitForImages(tester);

        expect(find.text('여행 · 2장'), findsOneWidget, reason: '목차 맨 뒤');
        expect(
          showsAsset(tester, 'assets/images/life-story-travel-3.webp'),
          isTrue,
        );
      });

      testWidgets('그림을 바꿔 고를 수 있다', (tester) async {
        await openAdd(tester);
        await tapAndSettle(tester, find.text('가족'));
        await tapAndSettle(tester, find.bySemanticsLabel('그림 5번'));
        await fill(tester, '새 이야기', '내용');
        await tapAndSettle(tester, find.text('이야기 담기'));
        await tapAndSettle(tester, find.text('새 이야기'));
        await waitForImages(tester);

        expect(
          showsAsset(tester, 'assets/images/life-story-family-5.webp'),
          isTrue,
        );
      });

      testWidgets('쓰던 내용이 있으면 뒤로 갈 때 한 번 묻는다', (tester) async {
        await openAdd(tester);
        await tester.tap(find.byTooltip('뒤로'));
        await tester.pumpAndSettle();
        expect(
          find.text('어떤 이야기를 볼까요?'),
          findsOneWidget,
          reason: '쓴 것이 없으면 묻지 않는다',
        );

        await tapAndSettle(tester, find.text('이야기 추가하기'));
        await fill(tester, '쓰다 만 이야기', '');
        await tester.tap(find.byTooltip('뒤로'));
        await tester.pumpAndSettle();

        expect(find.text('작성 중인 내용이 사라져요'), findsOneWidget);
        await tapAndSettle(tester, find.text('계속 쓰기'));
        expect(find.text('쓰다 만 이야기'), findsOneWidget);

        await tester.tap(find.byTooltip('뒤로'));
        await tester.pumpAndSettle();
        await tapAndSettle(tester, find.text('나가기'));

        expect(find.text('어떤 이야기를 볼까요?'), findsOneWidget);
        expect(find.text('쓰다 만 이야기'), findsNothing);
      });

      testWidgets('연필로 고치면 고친 내용이 바로 보인다', (tester) async {
        await openAt(tester, AppRoutes.albumCategoryOf('family'));
        await tapAndSettle(tester, find.text('남편을 처음 만난 날'));
        await tapAndSettle(tester, find.byTooltip('이야기 수정'));

        expect(find.text('이야기 수정하기'), findsOneWidget);
        expect(find.text('남편을 처음 만난 날'), findsOneWidget, reason: '원래 값');

        await tester.enterText(find.byType(TextField).at(0), '국숫집에서 만난 날');
        await tester.pump();
        await tapAndSettle(tester, find.text('수정 완료'));

        expect(find.text('이야기를 고쳤어요.'), findsOneWidget);
        expect(find.text('국숫집에서 만난 날'), findsOneWidget);
        expect(find.text('가족 · 2장'), findsOneWidget, reason: '담은 날짜는 그대로다');
      });

      testWidgets('분류를 바꾸면 새 분류의 목차 위에서 다시 연다', (tester) async {
        await openAt(tester, AppRoutes.albumCategoryOf('family'));
        await tapAndSettle(tester, find.text('남편을 처음 만난 날'));
        await tapAndSettle(tester, find.byTooltip('이야기 수정'));
        await tapAndSettle(tester, find.text('여행'));
        await tapAndSettle(tester, find.text('수정 완료'));

        // 8월 22일에 담아 신혼여행(9월 25일)보다 앞이다.
        expect(find.text('여행 · 1장'), findsOneWidget);

        await tester.tap(find.byTooltip('뒤로'));
        await tester.pumpAndSettle();

        expect(find.text('김새록님의 여행에 대한\n이야기입니다.'), findsOneWidget);
        expect(find.text('남편을 처음 만난 날'), findsOneWidget);
      });

      testWidgets('휴지통은 한 번 묻고 지운 뒤 목차로 돌아간다', (tester) async {
        await openAt(tester, AppRoutes.albumCategoryOf('family'));
        await tapAndSettle(tester, find.text('남편을 처음 만난 날'));
        await tapAndSettle(tester, find.byTooltip('이야기 지우기'));

        expect(find.text('이 이야기를 지울까요?'), findsOneWidget);
        await tapAndSettle(tester, find.text('취소'));
        expect(find.text('가족 · 2장'), findsOneWidget);

        await tapAndSettle(tester, find.byTooltip('이야기 지우기'));
        await tapAndSettle(tester, find.text('지우기'));

        expect(find.text('이야기를 지웠어요.'), findsOneWidget);
        expect(find.text('김새록님의 가족에 대한\n이야기입니다.'), findsOneWidget);
        expect(find.text('남편을 처음 만난 날'), findsNothing);
      });

      testWidgets('세부 정보 이야기는 지울 수 없고 연필은 세부 정보 수정을 연다', (tester) async {
        await openAt(tester, AppRoutes.albumCategoryOf('family'));
        await tapAndSettle(tester, find.text('가족'));

        expect(find.byTooltip('이야기 지우기'), findsNothing);

        await tapAndSettle(tester, find.byTooltip('이야기 수정'));

        expect(find.text('세부 정보 수정'), findsOneWidget);
      });

      testWidgets('입력 화면도 글자를 두 배로 키워도 깨지지 않는다', (tester) async {
        await openAt(tester, AppRoutes.albumStoryNew, textScale: 2);
        await tapAndSettle(tester, find.text('가족'));
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('바꾼 이야기 기억', () {
    const draft = LifeStoryDraft(
      category: LifeStoryCategory.other,
      title: '고친 제목',
      content: '내용',
      imageNumber: 1,
    );
    const base = [
      LifeStory(
        id: 'm1',
        category: LifeStoryCategory.family,
        title: '원래',
        content: '내용',
        imageNumber: 1,
      ),
      LifeStory(
        id: 'm2',
        category: LifeStoryCategory.family,
        title: '지울 것',
        content: '내용',
        imageNumber: 1,
      ),
    ];

    test('어르신마다 따로 기억하고 목 이야기도 고치거나 지울 수 있다', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final edits = container.read(lifeStoryEditsProvider.notifier);
      List<String> idsOf(String profileId) => container
          .read(lifeStoryEditsProvider)[profileId]!
          .applyTo(base)
          .map((s) => s.id)
          .toList();

      final added = edits.add('a', draft);
      edits.update('a', base[0], draft);
      edits.delete('a', base[1]);

      expect(idsOf('a'), ['m1', added.id]);
      expect(
        container.read(lifeStoryEditsProvider)['a']!.applyTo(base).first.title,
        '고친 제목',
      );
      expect(container.read(lifeStoryEditsProvider)['b'], isNull);

      edits.delete('a', added);
      expect(idsOf('a'), ['m1']);
    });
  });
}
