/// 서버에 아직 보내지 못한 면회 녹음을 회차별로 기억한다.
///
/// 앱을 다시 켜도 `음성 다시 보내기` 가 녹음 파일과 참여자 수를 찾을 수 있게,
/// 녹음 파일 옆에 작은 기록(`pending-uploads.json`)을 둔다. 담는 것은 계정 ID,
/// 회차 ID, 파일 이름, 참여자 수뿐이다. 어르신 이름이나 대화 내용은 담지 않는다.
///
/// 기록은 녹음 파일과 함께 생기고 함께 지운다. 서버가 녹음을 받았거나(API 6-2
/// `202`) 다시 받지 않는 회차면 둘 다 지운다. 서버가 받은 직후 지울지, 전사문을
/// 저장할 때까지 둘지는 아직 정하지 않았다(PR #117 리뷰).
///
/// 기록마다 녹음한 계정을 적는다. 로그아웃해도 녹음은 남기되, 다른 계정으로
/// 들어오면 찾지도 보내지도 못한다. 탈퇴하면 그 계정의 녹음과 기록을 지운다
/// ([PendingUploads.forgetAccount]). 시간이 지났다고 지우지는 않는다. 앱을 지우면
/// Android 가 앱 전용 공간과 함께 지운다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../auth/auth_providers.dart';
import 'visit_recorder.dart';

/// 보내지 못한 녹음 하나.
class PendingUpload {
  const PendingUpload({
    required this.sessionId,
    required this.audioPath,
    required this.participantCount,
  });

  final String sessionId;

  /// 녹음 파일의 절대 경로.
  final String audioPath;

  /// 녹음을 끝낼 때 보호자가 확인한 1~8.
  final int participantCount;
}

abstract interface class PendingUploads {
  /// 회차의 녹음을 기억한다. 같은 회차가 있으면 바꾼다.
  Future<void> save(PendingUpload upload);

  /// 회차의 녹음을 찾는다. 기록이 없거나 파일이 사라졌으면 `null` 이다.
  Future<PendingUpload?> find(String sessionId);

  /// 녹음 파일과 기록을 함께 지운다. [audioPath] 는 기록이 없을 때도 지울
  /// 파일이다.
  Future<void> remove(String sessionId, {String? audioPath});

  /// 탈퇴한 계정의 녹음과 기록을 모두 지운다.
  ///
  /// 기록이 없는 녹음 파일도 함께 지운다. 녹음을 끝내지 못했거나 기록을 남기지
  /// 못한 파일이라 어느 계정 것인지 알 수 없고 다시 보낼 수도 없다.
  Future<void> forgetAccount(String accountId);
}

/// 앱 전용 공간의 `visit_recordings/` 에 둔다. 녹음 파일과 같은 폴더다.
///
/// [accountId] 는 지금 로그인한 계정이다. 그 계정이 남긴 기록만 찾고 지운다.
/// `null` 이면 서버 세션 없이 들어온 경우다(디버그 빌드의 로그인 건너뛰기).
class DevicePendingUploads implements PendingUploads {
  DevicePendingUploads({
    this.accountId,
    Future<Directory> Function()? directory,
  }) : _directory = directory ?? _recordingsDirectory;

  final String? accountId;

  final Future<Directory> Function() _directory;

  /// 지금 계정이 남긴 기록인지. 계정을 적기 전의 기록은 세션 없이 남긴 것으로 본다.
  bool _mine(Map<String, dynamic> entry) => entry['accountId'] == accountId;

  static const fileName = 'pending-uploads.json';

  static Future<Directory> _recordingsDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory('${documents.path}/${VisitRecording.directoryName}');
  }

  @override
  Future<void> save(PendingUpload upload) async {
    final directory = await _directory();
    final entries = await _read(directory)
      ..removeWhere((e) => e['sessionId'] == upload.sessionId && _mine(e));
    entries.add({
      'accountId': accountId,
      'sessionId': upload.sessionId,
      // 폴더는 앱이 다시 정하므로 이름만 둔다.
      'fileName': upload.audioPath.split(RegExp(r'[/\\]')).last,
      'participantCount': upload.participantCount,
    });
    await _write(directory, entries);
  }

  @override
  Future<PendingUpload?> find(String sessionId) async {
    final directory = await _directory();
    for (final entry in await _read(directory)) {
      if (entry['sessionId'] != sessionId || !_mine(entry)) continue;
      final name = entry['fileName'];
      final count = entry['participantCount'];
      if (name is! String || count is! int) return null;

      final path = '${directory.path}/$name';
      if (!await File(path).exists()) return null;
      return PendingUpload(
        sessionId: sessionId,
        audioPath: path,
        participantCount: count,
      );
    }
    return null;
  }

  @override
  Future<void> remove(String sessionId, {String? audioPath}) async {
    final directory = await _directory();
    final entries = await _read(directory);
    final paths = {
      ?audioPath,
      for (final e in entries)
        if (e['sessionId'] == sessionId && _mine(e) && e['fileName'] is String)
          '${directory.path}/${e['fileName']}',
    };
    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }

    entries.removeWhere((e) => e['sessionId'] == sessionId && _mine(e));
    await _write(directory, entries);
  }

  @override
  Future<void> forgetAccount(String accountId) async {
    final directory = await _directory();
    if (!await directory.exists()) return;

    final entries = await _read(directory)
      ..removeWhere((e) => e['accountId'] == accountId);
    await _write(directory, entries);

    // 남은 기록이 가리키지 않는 녹음은 모두 지운다. 탈퇴한 계정의 녹음과 어느
    // 계정 것인지 모르는 녹음이다.
    final kept = {
      for (final e in entries)
        if (e['fileName'] is String) e['fileName'] as String,
    };
    await for (final item in directory.list()) {
      if (item is! File) continue;
      final name = item.uri.pathSegments.last;
      if (!name.endsWith('.${VisitRecording.fileExtension}')) continue;
      if (kept.contains(name)) continue;
      await item.delete();
    }
  }

  /// 읽지 못하는 기록은 빈 것으로 본다. 기록 때문에 면회를 막지 않는다.
  Future<List<Map<String, dynamic>>> _read(Directory directory) async {
    final file = File('${directory.path}/$fileName');
    if (!await file.exists()) return [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      return decoded.whereType<Map<String, dynamic>>().toList();
    } on FormatException {
      return [];
    }
  }

  /// 쓰다 앱이 꺼져도 반쯤 쓴 기록이 남지 않게 옆에 쓴 뒤 바꿔 끼운다.
  Future<void> _write(
    Directory directory,
    List<Map<String, dynamic>> entries,
  ) async {
    final file = File('${directory.path}/$fileName');
    if (entries.isEmpty) {
      if (await file.exists()) await file.delete();
      return;
    }
    await directory.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(entries), flush: true);
    await temp.rename(file.path);
  }
}

/// 지금 로그인한 계정의 기록이다. 계정이 바뀌면 새로 만든다.
///
/// 테스트는 이 provider 를 override 해 실제 파일을 건드리지 않는다.
final pendingUploadsProvider = Provider<PendingUploads>(
  (ref) => DevicePendingUploads(
    accountId: ref.watch(sessionProvider.select((s) => s?.account.accountId)),
  ),
);
