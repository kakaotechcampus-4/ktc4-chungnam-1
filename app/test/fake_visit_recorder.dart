// 기기 없이 녹음 흐름을 확인하려고 쓰는 가짜 녹음 장치다.
//
// 실제 마이크와 파일 쓰기는 플러그인이 하므로 단위 테스트에서 돌릴 수 없다.
// 화면과 상태가 장치를 어떤 순서로 부르는지만 여기서 확인한다.

import 'package:saerok/features/visit/visit_recorder.dart';

class FakeVisitRecorder implements VisitRecorder {
  FakeVisitRecorder({
    this.permitted = true,
    this.failOnStart = false,
    this.failOnStop = false,
    this.losesFile = false,
  });

  /// 마이크 권한을 줄지.
  bool permitted;

  /// 시작할 때 장치가 열리지 않는 경우.
  bool failOnStart;

  /// 끝낼 때 파일을 닫지 못하는 경우.
  bool failOnStop;

  /// 끝냈는데 파일이 없는 경우.
  bool losesFile;

  /// 불린 순서다. `hasPermission`, `start`, `pause`, `resume`, `stop`.
  final List<String> calls = [];

  int _files = 0;

  @override
  Future<bool> hasPermission() async {
    calls.add('hasPermission');
    return permitted;
  }

  @override
  Future<VisitRecording> start() async {
    calls.add('start');
    if (failOnStart) throw Exception('장치를 열지 못했다');
    _files++;
    return VisitRecording(path: '/fake/visit_recordings/visit-$_files.wav');
  }

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> resume() async => calls.add('resume');

  @override
  Future<VisitRecording?> stop() async {
    calls.add('stop');
    if (failOnStop) throw Exception('파일을 닫지 못했다');
    if (losesFile) return null;
    return VisitRecording(path: '/fake/visit_recordings/visit-$_files.wav');
  }

  @override
  Future<void> dispose() async => calls.add('dispose');
}
