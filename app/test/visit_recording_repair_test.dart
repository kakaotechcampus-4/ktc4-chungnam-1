// 녹음 중에 앱이 죽어 머리글 없이 남은 WAV 파일을 보낼 수 있게 고치는지 확인한다.
//
// `record` 는 앞 44바이트를 비워 두고 소리를 바로 쓰며, 녹음을 끝낼 때 머리글을
// 채운다. 끝내지 못한 파일은 앞 44바이트가 0이고 그 뒤에 16kHz 모노 16비트 PCM 이
// 남는다. 소리는 모두 합성 바이트다.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/features/visit/visit_recorder.dart';

Future<File> _file(List<int> bytes) async {
  final dir = await Directory.systemTemp.createTemp('saerok_wav_test');
  addTearDown(() => dir.delete(recursive: true));
  return File('${dir.path}/visit.wav')..writeAsBytesSync(bytes);
}

String _tag(Uint8List bytes, int offset) =>
    String.fromCharCodes(bytes.sublist(offset, offset + 4));

void main() {
  test('머리글이 비어 있으면 형식과 소리 길이로 다시 채우고 소리는 그대로 둔다', () async {
    final pcm = List<int>.generate(3200, (i) => i % 251);
    final file = await _file([...List<int>.filled(44, 0), ...pcm]);

    expect(repairUnfinishedRecording(file.path), isTrue);

    final bytes = file.readAsBytesSync();
    final data = ByteData.sublistView(bytes);
    expect(bytes.length, 44 + pcm.length);
    expect(_tag(bytes, 0), 'RIFF');
    expect(data.getUint32(4, Endian.little), 36 + pcm.length);
    expect(_tag(bytes, 8), 'WAVE');
    expect(_tag(bytes, 12), 'fmt ');
    expect(data.getUint16(20, Endian.little), 1, reason: 'PCM');
    expect(data.getUint16(22, Endian.little), visitRecordConfig.numChannels);
    expect(data.getUint32(24, Endian.little), visitRecordConfig.sampleRate);
    expect(data.getUint32(28, Endian.little), visitRecordConfig.sampleRate * 2);
    expect(data.getUint16(32, Endian.little), 2);
    expect(data.getUint16(34, Endian.little), 16);
    expect(_tag(bytes, 36), 'data');
    expect(data.getUint32(40, Endian.little), pcm.length);
    expect(bytes.sublist(44), pcm);
  });

  test('마지막 표본이 반만 쓰였으면 그 앞까지만 소리로 적는다', () async {
    final file = await _file([...List<int>.filled(44, 0), 1, 2, 3]);

    expect(repairUnfinishedRecording(file.path), isTrue);

    final data = ByteData.sublistView(file.readAsBytesSync());
    expect(data.getUint32(40, Endian.little), 2);
  });

  test('이미 머리글이 있는 파일은 건드리지 않는다', () async {
    final header = [
      ...'RIFF'.codeUnits,
      ...List<int>.filled(4, 7),
      ...'WAVE'.codeUnits,
      ...List<int>.filled(32, 9),
    ];
    final original = [...header, ...List<int>.filled(100, 5)];
    final file = await _file(original);

    expect(repairUnfinishedRecording(file.path), isFalse);
    expect(file.readAsBytesSync(), original);
  });

  test('소리가 없거나 파일이 없으면 고치지 않는다', () async {
    final empty = await _file(List<int>.filled(44, 0));
    expect(repairUnfinishedRecording(empty.path), isFalse);
    expect(empty.lengthSync(), 44);

    expect(
      repairUnfinishedRecording('${empty.parent.path}/missing.wav'),
      isFalse,
    );
  });
}
