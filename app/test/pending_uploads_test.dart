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

  test('기록에는 계정 ID, 회차 ID, 파일 이름, 참여자 수만 둔다', () async {
    final path = await wav('visit-a.wav');
    await DevicePendingUploads(
      accountId: 'account-a',
      directory: () async => dir,
    ).save(
      PendingUpload(sessionId: 's1', audioPath: path, participantCount: 2),
    );

    expect(jsonDecode(await record().readAsString()), [
      {
        'accountId': 'account-a',
        'sessionId': 's1',
        'fileName': 'visit-a.wav',
        'participantCount': 2,
      },
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

  group('계정', () {
    DevicePendingUploads storeOf(String? accountId) =>
        DevicePendingUploads(accountId: accountId, directory: () async => dir);

    test('로그아웃해도 녹음은 남고 다른 계정은 찾거나 지우지 못한다', () async {
      final path = await wav('visit-a.wav');
      await storeOf('account-a').save(
        PendingUpload(sessionId: 's1', audioPath: path, participantCount: 2),
      );

      final other = storeOf('account-b');
      expect(await other.find('s1'), isNull);
      await other.remove('s1');
      expect(await File(path).exists(), isTrue);

      expect(await storeOf('account-a').find('s1'), isNotNull);
    });

    test('탈퇴한 계정의 녹음과 기록만 지운다', () async {
      final mine = await wav('visit-a.wav');
      final others = await wav('visit-b.wav');
      await storeOf('account-a').save(
        PendingUpload(sessionId: 's1', audioPath: mine, participantCount: 2),
      );
      await storeOf('account-b').save(
        PendingUpload(sessionId: 's2', audioPath: others, participantCount: 3),
      );

      await storeOf(null).forgetAccount('account-a');

      expect(await File(mine).exists(), isFalse);
      expect(await storeOf('account-a').find('s1'), isNull);
      expect(await File(others).exists(), isTrue);
      expect(await storeOf('account-b').find('s2'), isNotNull);
    });

    test('탈퇴하면 기록이 없는 녹음도 지운다', () async {
      final orphan = await wav('visit-orphan.wav');

      await storeOf('account-a').forgetAccount('account-a');

      expect(await File(orphan).exists(), isFalse);
    });
  });
}
