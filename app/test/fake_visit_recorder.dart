// 기기 없이 녹음 흐름을 확인하려고 쓰는 가짜 녹음 장치다.
//
// 실제 마이크와 파일 쓰기는 플러그인이 하므로 단위 테스트에서 돌릴 수 없다.
// 화면과 상태가 장치를 어떤 순서로 부르는지만 여기서 확인한다.

import 'dart:async';

import 'package:saerok/features/visit/visit_recorder.dart';

class FakeVisitRecorder implements VisitRecorder {
  FakeVisitRecorder({
    this.permitted = true,
    this.failOnStart = false,
    this.failOnStop = false,
    this.losesFile = false,
    this.failOnResume = false,
    this.directory = '/fake/visit_recordings',
  });

  /// 마이크 권한을 줄지.
  bool permitted;

  /// 시작할 때 장치가 열리지 않는 경우.
  bool failOnStart;

  /// 끝낼 때 파일을 닫지 못하는 경우.
  bool failOnStop;

  /// 끝냈는데 파일이 없는 경우.
  bool losesFile;

  /// 있으면 끝날 때까지 장치가 열리지 않는다. 장치를 여는 중을 흉내 낸다.
  Completer<void>? startGate;
  /// 멈춘 녹음을 이어 가지 못하는 경우.
  bool failOnResume;

  /// 파일 경로의 폴더. 실제 파일을 두고 확인할 때 임시 폴더로 바꾼다.
  final String directory;

  /// 불린 순서다. `hasPermission`, `start`, `pause`, `resume`, `stop`.
  final List<String> calls = [];

  int _files = 0;

  /// 실제 장치처럼 앱이 부른 시작, 멈춤, 이어 가기, 끝내기도 상태로 알린다.
  /// 비동기 broadcast 라 부른 뒤에 닿는다.
  final _states = StreamController<VisitRecorderState>.broadcast();

  @override
  Stream<VisitRecorderState> get stateChanges => _states.stream;

  /// 앱이 부르지 않은 장치 쪽 변화를 흉내 낸다. 전화나 다른 앱의 소리로
  /// 멈춘 경우는 [VisitRecorderState.paused] 다.
  void deviceChanged(VisitRecorderState state) => _states.add(state);

  /// 장치가 오류로 멈춘 경우를 흉내 낸다.
  void deviceFailed() => _states.addError(Exception('장치가 멈췄다'));

  @override
  Future<bool> hasPermission() async {
    calls.add('hasPermission');
    return permitted;
  }

  @override
  Future<VisitRecording> start() async {
    calls.add('start');
    final gate = startGate;
    if (gate != null) await gate.future;
    if (failOnStart) throw Exception('장치를 열지 못했다');
    _files++;
    _states.add(VisitRecorderState.recording);
    return VisitRecording(path: '$directory/visit-$_files.wav');
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    _states.add(VisitRecorderState.paused);
  }

  @override
  Future<void> resume() async {
    calls.add('resume');
    if (failOnResume) throw Exception('이어 가지 못했다');
    _states.add(VisitRecorderState.recording);
  }

  @override
  Future<VisitRecording?> stop() async {
    calls.add('stop');
    _states.add(VisitRecorderState.stopped);
    if (failOnStop) throw Exception('파일을 닫지 못했다');
    if (losesFile) return null;
    return VisitRecording(path: '$directory/visit-$_files.wav');
  }

  @override
  Future<void> dispose() async => calls.add('dispose');
}
