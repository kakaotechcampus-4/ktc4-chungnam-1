// 이 기기에만 두는 어르신 사진과 이야기 사진(`lib/features/local_photos/`)을
// 확인한다.
//
// 보관소는 임시 폴더에 합성 파일을 만들어 쓰고, 화면은 메모리 대역을 쓴다.
// 실제 사진은 쓰지 않는다.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/app/router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/life_story/life_story_image.dart';
import 'package:saerok/features/local_photos/local_photos.dart';
import 'package:saerok/features/profile_setup/photo_picker.dart';
import 'package:saerok/widgets/profile_avatar.dart';

import 'fake_local_photos.dart';
import 'sample_profile.dart';

void main() {
  group('기기 사진 보관소', () {
    late Directory root;
    late Directory dir;
    late DeviceLocalPhotos store;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('saerok_local_photos_test');
      addTearDown(() => root.delete(recursive: true));
      dir = Directory('${root.path}/${DeviceLocalPhotos.directoryName}');
      store = DeviceLocalPhotos(
        accountId: 'account-a',
        directory: () async => dir,
      );
    });

    /// 앨범 선택기가 임시 폴더에 남긴 것처럼 만든 합성 파일.
    Future<String> picked(
      String name, [
      List<int> bytes = const [1, 2, 3],
    ]) async {
      final path = '${root.path}/$name';
      await File(path).writeAsBytes(bytes);
      return path;
    }

    File record() => File('${dir.path}/${DeviceLocalPhotos.fileName}');

    String nameOf(String path) => path.split('/').last;

    test('고른 사진을 사진 폴더로 복사하고 계정, 어르신, 자리, 파일 이름만 적는다', () async {
      final original = await picked('picker-1.png');

      final kept = await store.keep('p1', LocalPhotoSlot.avatar, original);

      expect(File(kept).parent.path, dir.path);
      expect(File(kept).readAsBytesSync(), [1, 2, 3]);
      expect(kept, endsWith('.png'), reason: '확장자는 그대로 둔다');
      expect(File(original).existsSync(), isTrue, reason: '선택기의 파일은 건드리지 않는다');
      expect(jsonDecode(await record().readAsString()), [
        {
          'accountId': 'account-a',
          'profileId': 'p1',
          'slot': 'avatar',
          'fileName': nameOf(kept),
        },
      ]);
      expect(await store.load(), {'p1/avatar': kept});
    });

    test('같은 자리에 다시 넣으면 앞 사진 파일을 지우고 새 이름으로 둔다', () async {
      final first = await store.keep(
        'p1',
        LocalPhotoSlot.story('s1'),
        await picked('a.jpg'),
      );
      final second = await store.keep(
        'p1',
        LocalPhotoSlot.story('s1'),
        await picked('b.jpg', [9]),
      );

      expect(second, isNot(first), reason: '화면이 앞 사진을 캐시에서 꺼내지 않게');
      expect(File(first).existsSync(), isFalse);
      expect(await store.load(), {'p1/story:s1': second});
    });

    test('다른 계정의 사진은 읽지 않는다', () async {
      await store.keep('p1', LocalPhotoSlot.avatar, await picked('a.jpg'));
      final other = DeviceLocalPhotos(
        accountId: 'account-b',
        directory: () async => dir,
      );

      expect(await other.load(), isEmpty);
    });

    test('되돌리면 그 자리의 사진과 기록만 지운다', () async {
      final avatar = await store.keep(
        'p1',
        LocalPhotoSlot.avatar,
        await picked('a.jpg'),
      );
      final story = await store.keep(
        'p1',
        LocalPhotoSlot.story('s1'),
        await picked('b.jpg'),
      );

      await store.remove('p1', LocalPhotoSlot.avatar);

      expect(File(avatar).existsSync(), isFalse);
      expect(await store.load(), {'p1/story:s1': story});
    });

    test('어르신을 지우면 그분의 사진을 모두 지운다', () async {
      final p1 = await store.keep(
        'p1',
        LocalPhotoSlot.story('s1'),
        await picked('a.jpg'),
      );
      final p2 = await store.keep(
        'p2',
        LocalPhotoSlot.avatar,
        await picked('b.jpg'),
      );

      await store.forgetProfile('p1');

      expect(File(p1).existsSync(), isFalse);
      expect(await store.load(), {'p2/avatar': p2});
    });

    test('탈퇴하면 그 계정의 사진과 기록 없는 파일을 지우고 다른 계정 것은 둔다', () async {
      final mine = await store.keep(
        'p1',
        LocalPhotoSlot.avatar,
        await picked('a.jpg'),
      );
      final other = DeviceLocalPhotos(
        accountId: 'account-b',
        directory: () async => dir,
      );
      final theirs = await other.keep(
        'p9',
        LocalPhotoSlot.avatar,
        await picked('b.jpg'),
      );
      final orphan = File('${dir.path}/local-photo-orphan.jpg')
        ..writeAsBytesSync([0]);

      await store.forgetAccount('account-a');

      expect(File(mine).existsSync(), isFalse);
      expect(orphan.existsSync(), isFalse);
      expect(File(theirs).existsSync(), isTrue);
      expect(await other.load(), {'p9/avatar': theirs});
    });

    test('기록을 읽지 못하면 사진이 없는 것으로 본다', () async {
      await dir.create(recursive: true);
      await record().writeAsString('{망가진 기록');

      expect(await store.load(), isEmpty);
    });
  });

  group('사진 바꾸기 화면', () {
    late FakeLocalPhotos photos;

    setUp(() => photos = FakeLocalPhotos());

    Future<void> openAt(WidgetTester tester, String location) async {
      tester.view.physicalSize = const Size(412, 917) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final router = buildRouter();
      router.go(location);

      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              careProfilesProvider.overrideWith(_OneProfile.new),
              localPhotosProvider.overrideWithValue(photos),
              photoPickerProvider.overrideWithValue(
                const _FakePicker('/picked/photo.jpg'),
              ),
            ],
            child: MaterialApp.router(
              theme: buildAppTheme(),
              routerConfig: router,
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

    String? storyPhoto(WidgetTester tester) =>
        tester.widget<LifeStoryImage>(find.byType(LifeStoryImage)).photoPath;

    final storyKey = localPhotoKey(
      sampleProfileId,
      LocalPhotoSlot.story('fact_demo_001'),
    );

    testWidgets('이야기 그림을 앨범 사진으로 바꾸고 기본 그림으로 되돌린다', (tester) async {
      await openAt(tester, AppRoutes.albumStoryOf('family', 'fact_demo_001'));
      expect(storyPhoto(tester), isNull);

      await tapAndSettle(tester, find.text('사진 바꾸기'));
      expect(find.textContaining('이 휴대폰에만 저장돼요'), findsOneWidget);
      expect(
        find.text('기본 그림으로 되돌리기'),
        findsNothing,
        reason: '넣은 사진이 없으면 되돌릴 것도 없다',
      );
      await tapAndSettle(tester, find.text('앨범에서 고르기'));

      expect(photos.saved, {storyKey: '/picked/photo.jpg'});
      expect(storyPhoto(tester), '/picked/photo.jpg');
      expect(find.text('사진을 바꿨어요.'), findsOneWidget);

      await tapAndSettle(tester, find.text('사진 바꾸기'));
      await tapAndSettle(tester, find.text('기본 그림으로 되돌리기'));

      expect(photos.saved, isEmpty);
      expect(storyPhoto(tester), isNull);
    });

    testWidgets('이야기를 지우면 넣어 둔 사진도 지운다', (tester) async {
      photos.saved[storyKey] = '/picked/old.jpg';
      // 지운 뒤 목차로 돌아가야 하므로 목차에서 연다.
      await openAt(tester, AppRoutes.albumCategoryOf('family'));
      await tapAndSettle(tester, find.text('남편을 처음 만난 날'));
      expect(storyPhoto(tester), '/picked/old.jpg');

      await tapAndSettle(tester, find.byTooltip('이야기 지우기'));
      await tapAndSettle(tester, find.text('지우기'));

      expect(photos.saved, isEmpty);
    });

    testWidgets('세부 정보 이야기도 사진을 바꿀 수 있다', (tester) async {
      await openAt(tester, AppRoutes.albumStoryOf('work', 'detail-occupation'));

      await tapAndSettle(tester, find.text('사진 바꾸기'));
      await tapAndSettle(tester, find.text('앨범에서 고르기'));

      expect(photos.saved.keys, [
        localPhotoKey(
          sampleProfileId,
          LocalPhotoSlot.story('detail-occupation'),
        ),
      ]);
    });

    testWidgets('프로필 설정에서 어르신 사진을 바꾸면 다른 화면도 그 사진을 쓴다', (tester) async {
      await openAt(tester, AppRoutes.profile);

      Iterable<Image> avatarImages() => tester.widgetList<Image>(
        find.descendant(
          of: find.byType(ProfileAvatar),
          matching: find.byType(Image),
        ),
      );
      expect(avatarImages().single.image, isA<AssetImage>());

      await tapAndSettle(tester, find.byTooltip('사진 바꾸기'));
      await tapAndSettle(tester, find.text('앨범에서 고르기'));

      expect(photos.saved, {
        localPhotoKey(sampleProfileId, LocalPhotoSlot.avatar):
            '/picked/photo.jpg',
      });
      final image = avatarImages().single.image;
      expect(image, isA<ResizeImage>());
      expect(
        ((image as ResizeImage).imageProvider as FileImage).file.path,
        '/picked/photo.jpg',
      );

      await tapAndSettle(tester, find.byTooltip('사진 바꾸기'));
      await tapAndSettle(tester, find.text('기본 사진으로 되돌리기'));
      expect(avatarImages().single.image, isA<AssetImage>());
    });

    testWidgets('사진을 둘 곳이 없는 기기에서는 바꾸는 버튼을 두지 않는다', (tester) async {
      photos.supported = false;
      await openAt(tester, AppRoutes.albumStoryOf('family', 'fact_demo_001'));
      expect(find.text('사진 바꾸기'), findsNothing);
    });
  });
}

/// 세부 정보 중 하시던 일을 적은 어르신 한 분.
class _OneProfile extends CareProfilesNotifier {
  @override
  CareProfiles build() => const CareProfiles(
    entries: [
      CareProfileEntry(
        id: sampleProfileId,
        basicInfo: sampleBasicInfo,
        details: EnteredDetails(occupation: '수선집을 하셨어요.'),
      ),
    ],
    selectedId: sampleProfileId,
  );
}

class _FakePicker implements PhotoPicker {
  const _FakePicker(this.path);

  final String path;

  @override
  Future<List<PickedPhoto>> pick({required int limit}) async => [
    PickedPhoto(path),
  ];
}
