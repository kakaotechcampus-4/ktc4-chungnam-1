/// 면회 녹음을 기기에 기록한다.
///
/// 화면과 [VisitController] 는 이 인터페이스만 본다. 어떤 녹음 라이브러리를
/// 쓰는지, 파일을 어디에 두는지는 여기서만 안다. 테스트는
/// [visitRecorderProvider] 를 override 해서 기기 없이 확인한다(`ADR-005` 의
/// 주입 방식과 같다).
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// 녹음 파일의 형식이다.
///
/// **잠정값이다. AI 영역의 확정을 기다린다.** `app/CLAUDE.md` 대로 음성 형식은
/// FE 가 정하는 값이 아니다. PR #65 의 요청 예시가 `audio.wav` 이고 STT 모델이
/// 보통 16kHz 모노 PCM 을 받으므로 그 값을 임시로 쓴다. AI 가 형식을 확정하면
/// 이 상수와 [VisitRecording.fileExtension] 만 바꾸면 된다.
const visitRecordConfig = RecordConfig(
  encoder: AudioEncoder.wav,
  sampleRate: 16000,
  numChannels: 1,
);

/// 기기에 남은 녹음 파일 하나다.
class VisitRecording {
  const VisitRecording({required this.path});

  /// 앱 전용 저장소 안의 절대 경로다. 다른 앱은 이 자리를 읽지 못한다.
  final String path;

  /// 녹음 파일을 모아 두는 폴더 이름.
  static const directoryName = 'visit_recordings';

  /// [visitRecordConfig] 의 인코더에 맞춘 확장자.
  static const fileExtension = 'wav';
}

/// 녹음 장치를 다루는 최소한의 약속이다.
abstract interface class VisitRecorder {
  /// 마이크를 쓸 수 있는지 확인한다. 아직 묻지 않았으면 사용자에게 묻는다.
  Future<bool> hasPermission();

  /// 새 파일에 녹음을 시작하고 그 파일을 돌려준다.
  Future<VisitRecording> start();

  /// 잠시 멈춘다. 파일은 그대로 두고 이어서 쓴다.
  Future<void> pause();

  /// 멈춘 자리에서 이어 녹음한다.
  Future<void> resume();

  /// 녹음을 끝내고 저장된 파일을 돌려준다. 시작한 적이 없으면 `null` 이다.
  Future<VisitRecording?> stop();

  /// 장치를 놓아준다.
  Future<void> dispose();
}

/// `record` 패키지로 실제 마이크를 쓰는 구현이다.
class DeviceVisitRecorder implements VisitRecorder {
  DeviceVisitRecorder({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<VisitRecording> start() async {
    final recording = VisitRecording(path: await _newFilePath());
    await _recorder.start(visitRecordConfig, path: recording.path);
    return recording;
  }

  @override
  Future<void> pause() => _recorder.pause();

  @override
  Future<void> resume() => _recorder.resume();

  @override
  Future<VisitRecording?> stop() async {
    final path = await _recorder.stop();
    if (path == null) return null;
    if (!await _isPlayable(path)) return null;
    return VisitRecording(path: path);
  }

  @override
  Future<void> dispose() => _recorder.dispose();

  /// 남은 파일을 정말 재생할 수 있는지 본다.
  ///
  /// WAV 헤더는 녹음을 끝낼 때 파일 앞 44바이트에 덮어 쓰인다. 끝내지 않고
  /// 화면을 떠나거나 앱이 죽으면 그 자리가 0으로 남아 소리는 들어 있는데 열 수
  /// 없는 파일이 된다. 경로만 보고 성공이라 말하지 않으려고 여기서 확인한다.
  Future<bool> _isPlayable(String path) async {
    if (visitRecordConfig.encoder != AudioEncoder.wav) return true;

    final file = File(path);
    if (!await file.exists()) return false;
    if (await file.length() <= _wavHeaderSize) return false;

    final head = await file.openRead(0, 4).expand((chunk) => chunk).toList();
    return head.length == 4 && String.fromCharCodes(head) == 'RIFF';
  }

  static const _wavHeaderSize = 44;

  /// 앱 전용 저장소 안에 녹음 폴더를 만들고 새 파일 경로를 짓는다.
  ///
  /// 파일 이름에는 시각만 넣는다. 어르신 이름이나 회차 정보처럼 사람을 알아볼
  /// 수 있는 값은 파일 이름에 남기지 않는다(저장소 공통 지침).
  Future<String> _newFilePath() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${documents.path}/${VisitRecording.directoryName}',
    );
    await directory.create(recursive: true);

    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-');
    return '${directory.path}/visit-$stamp.${VisitRecording.fileExtension}';
  }
}

/// 화면과 상태가 쓰는 녹음 장치다. 테스트에서 갈아 끼운다.
final visitRecorderProvider = Provider<VisitRecorder>((ref) {
  final recorder = DeviceVisitRecorder();
  ref.onDispose(recorder.dispose);
  return recorder;
});
