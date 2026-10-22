/// 세부 정보(B-3 ~ B-6) 음성 입력의 녹음을 기기에 기록한다.
///
/// 화면과 [SpeechInput] 은 이 인터페이스만 본다. 테스트는
/// [speechRecorderProvider] 를 override 해서 기기 없이 확인한다(`ADR-005`).
///
/// 면회 녹음([VisitRecorder])과 달리 파일을 남기지 않는다. 글로 옮기면 쓸 곳이
/// 없고, 서버도 전사가 끝나면 바로 지운다(이슈 #138). 그래서 앱 전용 임시
/// 폴더에 두고, 결과를 받거나 버리면 [SpeechRecorder.discard] 로 지운다.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../visit/visit_recorder.dart' show visitRecordConfig;

/// 한 번에 녹음할 수 있는 최대 길이. BE 가 받는 최대 길이와 같다(이슈 #138).
const speechMaxDuration = Duration(minutes: 5);

/// 녹음 장치를 다루는 최소한의 약속이다.
abstract interface class SpeechRecorder {
  /// 마이크를 쓸 수 있는지 확인한다. 아직 묻지 않았으면 사용자에게 묻는다.
  Future<bool> hasPermission();

  /// 새 파일에 녹음을 시작한다. 지난번에 지우지 못한 파일은 먼저 지운다.
  Future<void> start();

  /// 녹음을 끝내고 파일 경로를 돌려준다. 파일이 없으면 `null` 이다.
  Future<String?> stop();

  /// 녹음 중이면 멈추고 파일을 지운다. 없는 파일을 지워도 실패하지 않는다.
  Future<void> discard(String? path);

  /// 장치를 놓아준다.
  Future<void> dispose();
}

/// `record` 패키지로 실제 마이크를 쓰는 구현이다.
///
/// 형식은 면회 녹음과 같은 WAV, 16kHz, 16-bit, mono 다. BE 의 짧은 음성
/// 전사 API 가 받는 형식이다(이슈 #138).
class DeviceSpeechRecorder implements SpeechRecorder {
  DeviceSpeechRecorder({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  /// 임시 폴더 아래 녹음 폴더 이름. 이 폴더에는 지금 녹음 하나만 둔다.
  static const directoryName = 'speech_inputs';

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start() async {
    final directory = await _directory();
    // 앱이 꺼져 지우지 못한 파일이 있으면 여기서 지운다.
    await for (final entity in directory.list()) {
      await _deleteQuietly(entity.path);
    }

    // 파일 이름에는 시각만 넣는다. 사람을 알아볼 수 있는 값은 넣지 않는다.
    final stamp = DateTime.now().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    await _recorder.start(
      visitRecordConfig,
      path: '${directory.path}/speech-$stamp.wav',
    );
  }

  @override
  Future<String?> stop() async {
    final path = await _recorder.stop();
    if (path == null || !await File(path).exists()) return null;
    return path;
  }

  @override
  Future<void> discard(String? path) async {
    if (await _recorder.isRecording() || await _recorder.isPaused()) {
      final stopped = await _recorder.stop();
      if (stopped != null) await _deleteQuietly(stopped);
    }
    if (path != null) await _deleteQuietly(path);
  }

  @override
  Future<void> dispose() => _recorder.dispose();

  /// 캐시 폴더는 Android 자동 백업에 들어가지 않는다. 지운 녹음이 다시 설치할
  /// 때 되살아나지 않는다.
  Future<Directory> _directory() async {
    final temporary = await getTemporaryDirectory();
    final directory = Directory('${temporary.path}/$directoryName');
    await directory.create(recursive: true);
    return directory;
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      // 이미 없다.
    }
  }
}

/// 세부 정보 음성 입력이 쓰는 녹음 장치다. 테스트에서 갈아 끼운다.
final speechRecorderProvider = Provider<SpeechRecorder>((ref) {
  final recorder = DeviceSpeechRecorder();
  ref.onDispose(recorder.dispose);
  return recorder;
});
