// 보내지 못한 녹음 기록(`lib/features/visit/pending_uploads.dart`)을 확인한다.
//
// 임시 폴더에 합성 파일을 만들어 쓴다. 실제 녹음은 쓰지 않는다.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/features/visit/pending_uploads.dart';

void main() {
  late Directory dir;
  late DevicePendingUploads store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('saerok_pending_test');
    addTearDown(() => dir.delete(recursive: true));
    store = DevicePendingUploads(directory: () async => dir);
  });

  Future<String> wav(String name) async {
    final path = '${dir.path}/$name';
    await File(path).writeAsBytes([1, 2, 3, 4]);
    return path;
  }

  File record() => File('${dir.path}/${DevicePendingUploads.fileName}');

  test('회차 ID 로 녹음 파일과 참여자 수를 다시 찾는다', () async {
    final path = await wav('visit-a.wav');
    await store.save(
      PendingUpload(sessionId: 's1', audioPath: path, participantCount: 3),
    );

    final found = await store.find('s1');

    expect(found?.audioPath, path);
    expect(found?.participantCount, 3);
    expect(await store.find('other'), isNull);
  });

  test('기록에는 회차 ID, 파일 이름, 참여자 수만 둔다', () async {
    final path = await wav('visit-a.wav');
    await store.save(
      PendingUpload(sessionId: 's1', audioPath: path, participantCount: 2),
    );

    expect(jsonDecode(await record().readAsString()), [
      {'sessionId': 's1', 'fileName': 'visit-a.wav', 'participantCount': 2},
    ]);
  });

  test('같은 회차를 다시 적으면 바꾼다', () async {
    final first = await wav('visit-a.wav');
    final second = await wav('visit-b.wav');
    await store.save(
      PendingUpload(sessionId: 's1', audioPath: first, participantCount: 2),
    );
    await store.save(
      PendingUpload(sessionId: 's1', audioPath: second, participantCount: 4),
    );

    final found = await store.find('s1');
    expect(found?.audioPath, second);
    expect(found?.participantCount, 4);
  });

  test('파일이 사라졌으면 찾지 못한 것으로 본다', () async {
    final path = await wav('visit-a.wav');
    await store.save(
      PendingUpload(sessionId: 's1', audioPath: path, participantCount: 2),
    );
    await File(path).delete();

    expect(await store.find('s1'), isNull);
  });

  test('지우면 녹음 파일과 기록을 함께 지운다', () async {
    final keep = await wav('visit-a.wav');
    final drop = await wav('visit-b.wav');
    await store.save(
      PendingUpload(sessionId: 's1', audioPath: keep, participantCount: 2),
    );
    await store.save(
      PendingUpload(sessionId: 's2', audioPath: drop, participantCount: 2),
    );

    await store.remove('s2');

    expect(await File(drop).exists(), isFalse);
    expect(await File(keep).exists(), isTrue);
    expect(await store.find('s2'), isNull);
    expect(await store.find('s1'), isNotNull);

    await store.remove('s1');
    expect(await record().exists(), isFalse, reason: '남은 기록이 없으면 지운다');
  });

  test('기록이 없어도 넘긴 파일은 지운다', () async {
    final path = await wav('visit-a.wav');

    await store.remove('s1', audioPath: path);

    expect(await File(path).exists(), isFalse);
  });

  test('읽지 못하는 기록은 빈 것으로 보고 면회를 막지 않는다', () async {
    await record().writeAsString('{not json');
    final path = await wav('visit-a.wav');

    expect(await store.find('s1'), isNull);
    await store.save(
      PendingUpload(sessionId: 's1', audioPath: path, participantCount: 2),
    );
    expect(await store.find('s1'), isNotNull);
  });
}
