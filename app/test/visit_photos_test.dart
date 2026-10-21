// 서버에 올리려고 앱에 두는 면회 사진 사본(`lib/features/visit/visit_photos.dart`)을
// 확인한다.
//
// 임시 폴더에 합성 파일을 만들어 쓴다. 실제 사진은 쓰지 않는다.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/features/visit/visit_photos.dart';

void main() {
  late Directory root;
  late Directory dir;
  late DeviceVisitPhotos store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('saerok_photos_test');
    addTearDown(() => root.delete(recursive: true));
    dir = Directory('${root.path}/${DeviceVisitPhotos.directoryName}');
    store = DeviceVisitPhotos(
      accountId: 'account-a',
      directory: () async => dir,
    );
  });

  /// 카메라 앱이 임시 폴더에 남긴 것처럼 만든 합성 파일.
  Future<String> captured(String name) async {
    final path = '${root.path}/$name';
    await File(path).writeAsBytes([1, 2, 3, 4]);
    return path;
  }

  File record() => File('${dir.path}/${DeviceVisitPhotos.fileName}');

  test('찍은 사진을 사진 폴더로 옮기고 계정과 갤러리 여부만 적는다', () async {
    final original = await captured('picker-1.jpg');

    final kept = await store.keep(original, inGallery: true);

    expect(File(original).existsSync(), isFalse, reason: '임시 파일은 지운다');
    expect(File(kept).readAsBytesSync(), [1, 2, 3, 4]);
    expect(File(kept).parent.path, dir.path);
    expect(jsonDecode(await record().readAsString()), [
      {
        'accountId': 'account-a',
        'fileName': kept.split('/').last,
        'sessionId': null,
        'inGallery': true,
      },
    ]);
  });

  test('갤러리에 원본이 있으면 올린 뒤 사본을 지운다', () async {
    final kept = await store.keep(
      await captured('picker-1.jpg'),
      inGallery: true,
    );

    await store.markUploaded(kept, 's1');

    expect(File(kept).existsSync(), isFalse);
    expect(record().existsSync(), isFalse);
  });

  test('갤러리에 원본이 없으면 올려도 사본과 회차를 남긴다', () async {
    final kept = await store.keep(
      await captured('picker-1.jpg'),
      inGallery: false,
    );

    await store.markUploaded(kept, 's1');
    await store.discard(kept);
    await store.tidy();

    expect(File(kept).existsSync(), isTrue, reason: '하나뿐인 원본이다');
    expect(jsonDecode(await record().readAsString()), [
      {
        'accountId': 'account-a',
        'fileName': kept.split('/').last,
        'sessionId': 's1',
        'inGallery': false,
      },
    ]);
  });

  test('다시 찍어 밀려난 사진은 갤러리에 원본이 있을 때만 지운다', () async {
    final saved = await store.keep(
      await captured('picker-1.jpg'),
      inGallery: true,
    );
    final unsaved = await store.keep(
      await captured('picker-2.jpg'),
      inGallery: false,
    );

    await store.discard(saved);
    await store.discard(unsaved);

    expect(File(saved).existsSync(), isFalse);
    expect(File(unsaved).existsSync(), isTrue);
  });

  test('새 면회를 시작하면 갤러리에 원본이 있는 지난 사본만 지운다', () async {
    final failed = await store.keep(
      await captured('picker-1.jpg'),
      inGallery: true,
    );
    final unsaved = await store.keep(
      await captured('picker-2.jpg'),
      inGallery: false,
    );

    await store.tidy();

    expect(File(failed).existsSync(), isFalse, reason: '올리지 못하고 남은 사본');
    expect(File(unsaved).existsSync(), isTrue);
    final entries = jsonDecode(await record().readAsString()) as List;
    expect(entries.map((e) => e['fileName']), [unsaved.split('/').last]);
  });

  test('갤러리 여부가 적히지 않은 기록은 남기지 않은 것으로 보고 지우지 않는다', () async {
    await dir.create(recursive: true);
    final old = File('${dir.path}/visit-photo-old.jpg')..writeAsBytesSync([1]);
    await record().writeAsString(
      jsonEncode([
        {
          'accountId': 'account-a',
          'fileName': 'visit-photo-old.jpg',
          'sessionId': 's1',
        },
      ]),
    );

    await store.discard(old.path);
    await store.tidy();

    expect(old.existsSync(), isTrue);
  });

  test('정리와 촬영이 겹쳐도 새로 찍은 사진의 기록을 잃지 않는다', () async {
    await store.keep(await captured('picker-1.jpg'), inGallery: true);

    final tidying = store.tidy();
    final kept = store.keep(await captured('picker-2.jpg'), inGallery: true);
    await tidying;
    final path = await kept;

    expect(File(path).existsSync(), isTrue);
    final entries = jsonDecode(await record().readAsString()) as List;
    expect(entries.map((e) => e['fileName']), [path.split('/').last]);
  });

  test('탈퇴하면 그 계정의 사진과 기록 없는 사진만 지운다', () async {
    final mine = await store.keep(
      await captured('picker-1.jpg'),
      inGallery: false,
    );
    await store.markUploaded(mine, 's1');
    final other = await DeviceVisitPhotos(
      accountId: 'account-b',
      directory: () async => dir,
    ).keep(await captured('picker-2.jpg'), inGallery: false);
    final orphan = File('${dir.path}/visit-photo-orphan.jpg')
      ..writeAsBytesSync([1]);

    await store.forgetAccount('account-a');

    expect(File(mine).existsSync(), isFalse);
    expect(orphan.existsSync(), isFalse);
    expect(File(other).existsSync(), isTrue);
    final entries = jsonDecode(await record().readAsString()) as List;
    expect(entries.map((e) => e['accountId']), ['account-b']);
  });
}
