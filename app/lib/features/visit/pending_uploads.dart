/// 서버에 아직 보내지 못한 면회 녹음을 회차별로 기억한다.
///
/// 앱을 다시 켜도 `음성 다시 보내기` 가 녹음 파일과 참여자 수를 찾을 수 있게,
/// 녹음 파일 옆에 작은 기록(`pending-uploads.json`)을 둔다. 담는 것은 회차 ID,
/// 파일 이름, 참여자 수뿐이다. 어르신 이름이나 대화 내용은 담지 않는다.
///
/// 기록은 녹음 파일과 함께 생기고 함께 지운다. 서버가 녹음을 받았거나(API 6-2
/// `202`) 다시 받지 않는 회차면 둘 다 지운다. 끝내 보내지 못한 파일을 언제
/// 지울지와 탈퇴 때 지울지는 정해지지 않았다(app/README.md "아직 없는 것").
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

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
}

/// 앱 전용 공간의 `visit_recordings/` 에 둔다. 녹음 파일과 같은 폴더다.
class DevicePendingUploads implements PendingUploads {
  DevicePendingUploads({Future<Directory> Function()? directory})
    : _directory = directory ?? _recordingsDirectory;

  final Future<Directory> Function() _directory;

  static const fileName = 'pending-uploads.json';

  static Future<Directory> _recordingsDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory('${documents.path}/${VisitRecording.directoryName}');
  }

  @override
  Future<void> save(PendingUpload upload) async {
    final directory = await _directory();
    final entries = await _read(directory)
      ..removeWhere((e) => e['sessionId'] == upload.sessionId);
    entries.add({
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
      if (entry['sessionId'] != sessionId) continue;
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
        if (e['sessionId'] == sessionId && e['fileName'] is String)
          '${directory.path}/${e['fileName']}',
    };
    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }

    entries.removeWhere((e) => e['sessionId'] == sessionId);
    await _write(directory, entries);
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

/// 테스트는 이 provider 를 override 해 실제 파일을 건드리지 않는다.
final pendingUploadsProvider = Provider<PendingUploads>(
  (ref) => DevicePendingUploads(),
);
