/// 세부 정보(B-3 ~ B-6) 음성 입력의 녹음을 기기에 기록한다.
///
/// 화면과 [SpeechInput] 은 이 인터페이스만 본다. 테스트는
/// [speechRecorderProvider] 를 override 해서 기기 없이 확인한다(`ADR-005`).
///
/// 면회 녹음([VisitRecorder])과 달리 파일을 남기지 않는다. 글로 옮기면 쓸 곳이
/// 없고, 서버도 전사가 끝나면 바로 지운다(이슈 #138). 그래서 앱 전용 임시
/// 폴더에 두고, 결과를 받거나 버리면 [SpeechRecorder.delete] 로 지운다.
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
  /// 아직 보내는 중이거나 다시 보낼 파일은 남긴다.
  Future<void> start();

  /// 녹음을 끝내고 파일 경로를 돌려준다. 파일이 없으면 `null` 이다.
  Future<String?> stop();

  /// 녹음 중이면 멈추고 그 파일을 지운다. 녹음 중이 아니면 아무것도 하지
  /// 않는다.
  Future<void> discard();

  /// [stop] 으로 받은 파일 하나만 지운다. 장치는 건드리지 않는다.
  ///
  /// 장치는 화면들이 함께 쓴다. 앞 항목의 전사가 늦게 끝나 파일을 지울 때
  /// 다음 항목에서 시작한 녹음을 멈추면 안 된다. 없는 파일을 지워도 실패하지
  /// 않는다.
  Future<void> delete(String path);

  /// 장치를 놓아준다.
  Future<void> dispose();
}

/// `record` 패키지로 실제 마이크를 쓰는 구현이다.
///
/// 형식은 면회 녹음과 같은 WAV, 16kHz, 16-bit, mono 다. BE 의 짧은 음성
/// 전사 API 가 받는 형식이다(이슈 #138).
class DeviceSpeechRecorder implements SpeechRecorder {
  DeviceSpeechRecorder({
    AudioRecorder? recorder,
    Future<Directory> Function()? directory,
  }) : _recorder = recorder ?? AudioRecorder(),
       _directoryOf = directory ?? _temporaryDirectory;

  final AudioRecorder _recorder;

  /// 녹음 폴더를 돌려준다. 테스트에서 임시 폴더로 바꾼다.
  final Future<Directory> Function() _directoryOf;

  /// 임시 폴더 아래 녹음 폴더 이름.
  static const directoryName = 'speech_inputs';

  /// 녹음을 마쳤지만 아직 지우지 않은 파일의 이름. 보내는 중이거나 다시
  /// 보낼 파일이라 새 녹음을 시작할 때 지우지 않는다. 앱이 꺼지면 비므로,
  /// 그때 남은 파일은 다음 녹음을 시작할 때 지운다.
  ///
  /// 경로 대신 이름을 둔다. 폴더를 훑어 얻은 경로와 구분자가 다를 수 있다.
  final Set<String> _finished = {};

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start() async {
    final directory = await _directory();
    // 앱이 꺼져 지우지 못한 파일이 있으면 여기서 지운다.
    await for (final entity in directory.list()) {
      if (_finished.contains(_nameOf(entity.path))) continue;
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
    _finished.add(_nameOf(path));
    return path;
  }

  @override
  Future<void> discard() async {
    if (await _recorder.isRecording() || await _recorder.isPaused()) {
      final stopped = await _recorder.stop();
      if (stopped != null) await _deleteQuietly(stopped);
    }
  }

  @override
  Future<void> delete(String path) async {
    _finished.remove(_nameOf(path));
    await _deleteQuietly(path);
  }

  static String _nameOf(String path) => File(path).uri.pathSegments.last;

  @override
  Future<void> dispose() => _recorder.dispose();

  /// 캐시 폴더는 Android 자동 백업에 들어가지 않는다. 지운 녹음이 다시 설치할
  /// 때 되살아나지 않는다.
  static Future<Directory> _temporaryDirectory() async {
    final temporary = await getTemporaryDirectory();
    return Directory('${temporary.path}/$directoryName');
  }

  Future<Directory> _directory() async {
    final directory = await _directoryOf();
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
