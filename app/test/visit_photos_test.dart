// 기기에 남기는 면회 사진(`lib/features/visit/visit_photos.dart`)을 확인한다.
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

  test('찍은 사진을 사진 폴더로 옮기고 계정만 적는다', () async {
    final original = await captured('picker-1.jpg');

    final kept = await store.keep(original);

    expect(File(original).existsSync(), isFalse, reason: '임시 원본은 지운다');
    expect(File(kept).readAsBytesSync(), [1, 2, 3, 4]);
    expect(File(kept).parent.path, dir.path);
    expect(jsonDecode(await record().readAsString()), [
      {
        'accountId': 'account-a',
        'fileName': kept.split('/').last,
        'sessionId': null,
      },
    ]);
  });

  test('올린 사진은 회차를 적고 파일을 남긴다', () async {
    final kept = await store.keep(await captured('picker-1.jpg'));

    await store.markUploaded(kept, 's1');
    await store.discard(kept);

    expect(File(kept).existsSync(), isTrue, reason: '올린 사진은 지우지 않는다');
    expect(jsonDecode(await record().readAsString()), [
      {
        'accountId': 'account-a',
        'fileName': kept.split('/').last,
        'sessionId': 's1',
      },
    ]);
  });

  test('올리지 않은 사진은 지운다', () async {
    final kept = await store.keep(await captured('picker-1.jpg'));

    await store.discard(kept);

    expect(File(kept).existsSync(), isFalse);
    expect(record().existsSync(), isFalse);
  });

  test('탈퇴하면 그 계정의 사진과 기록 없는 사진만 지운다', () async {
    final mine = await store.keep(await captured('picker-1.jpg'));
    await store.markUploaded(mine, 's1');
    final other = await DeviceVisitPhotos(
      accountId: 'account-b',
      directory: () async => dir,
    ).keep(await captured('picker-2.jpg'));
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
