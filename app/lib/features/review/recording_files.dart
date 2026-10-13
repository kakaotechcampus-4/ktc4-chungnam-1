import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 기기에 남은 면회 녹음 파일을 지운다.
///
/// 명세(API 6-2)대로 서버가 녹음을 받은 뒤(`202`) 지운다. 테스트는
/// [recordingFilesProvider] 를 override 해 실제 파일을 건드리지 않는다.
abstract interface class RecordingFiles {
  /// 파일이 이미 없으면 그대로 둔다.
  Future<void> delete(String path);
}

class DeviceRecordingFiles implements RecordingFiles {
  const DeviceRecordingFiles();

  @override
  Future<void> delete(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}

final recordingFilesProvider = Provider<RecordingFiles>(
  (ref) => const DeviceRecordingFiles(),
);
