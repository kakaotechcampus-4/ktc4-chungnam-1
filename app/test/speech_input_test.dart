// 세부 정보 음성 입력의 서버 연결을 확인한다.
//
// 짧은 음성 전사 API(`lib/data/speech_api.dart`)는 `MockClient` 로, 실제 녹음과
// 전사를 잇는 `ServerSpeechInput` 은 가짜 녹음 장치와 가짜 API 로 본다. 값은
// 모두 합성 데이터다. 실제 음성은 쓰지 않는다.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:record/record.dart';
import 'package:saerok/data/api_client.dart';
import 'package:saerok/data/speech_api.dart';
import 'package:saerok/features/profile_setup/speech_input.dart';
import 'package:saerok/features/profile_setup/speech_recorder.dart';

http.Response _json(Object body, int status) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);

/// 녹음 순서와 지운 파일, 지금 녹음 중인지만 적는 가짜 녹음 장치다.
class _FakeRecorder implements SpeechRecorder {
  _FakeRecorder({
    this.permitted = true,
    this.failOnStart = false,
    this.losesFile = false,
  });

  final bool permitted;
  final bool failOnStart;
  final bool losesFile;

  /// 첫 녹음의 파일. 녹음할 때마다 끝 번호가 하나씩 는다.
  static const path = '/fake/speech_inputs/speech-1.wav';

  /// 불린 순서다. `delete` 는 지운 경로를 함께 적는다.
  final List<String> calls = [];

  /// 장치가 지금 녹음하고 있다.
  bool recording = false;

  int _count = 0;

  @override
  Future<bool> hasPermission() async {
    calls.add('hasPermission');
    return permitted;
  }

  @override
  Future<void> start() async {
    calls.add('start');
    if (failOnStart) throw Exception('장치를 열지 못했다');
    _count += 1;
    recording = true;
  }

  @override
  Future<String?> stop() async {
    calls.add('stop');
    recording = false;
    return losesFile ? null : '/fake/speech_inputs/speech-$_count.wav';
  }

  @override
  Future<void> discard() async {
    calls.add('discard');
    recording = false;
  }

  @override
  Future<void> delete(String path) async => calls.add('delete $path');

  @override
  Future<void> dispose() async {}
}

/// 차례대로 결과나 실패를 돌려주는 가짜 API 다.
class _FakeApi implements SpeechApi {
  _FakeApi(this._results);

  /// `String` 이면 그 글자를, [ApiFailure] 면 던진다.
  final List<Object> _results;

  final List<String> sentPaths = [];

  @override
  Future<String> transcribe(String audioPath) async {
    sentPaths.add(audioPath);
    final result = _results.removeAt(0);
    if (result is ApiFailure) throw result;
    return result as String;
  }
}

/// 결과를 붙잡아 두는 가짜 API 다. 보낸 순서대로 [replies] 를 완료해 결과를
/// 돌려준다.
class _HeldApi implements SpeechApi {
  final List<Completer<String>> replies = [];

  @override
  Future<String> transcribe(String audioPath) {
    final reply = Completer<String>();
    replies.add(reply);
    return reply.future;
  }
}

/// 파일만 만들고 지우는 가짜 `record` 장치다. 쓰는 기능만 흉내 낸다.
class _FakeAudioRecorder implements AudioRecorder {
  String? _path;

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    await File(path).writeAsBytes([1, 2, 3, 4]);
    _path = path;
  }

  @override
  Future<String?> stop() async {
    final path = _path;
    _path = null;
    return path;
  }

  @override
  Future<bool> isRecording() async => _path != null;

  @override
  Future<bool> isPaused() async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<SpeechRecording> _start(ServerSpeechInput input) =>
    input.start(category: 'occupation', attempt: 1);

void main() {
  group('짧은 음성 전사 API', () {
    late String audioPath;

    setUp(() async {
      final dir = await Directory.systemTemp.createTemp('saerok_speech_test');
      addTearDown(() => dir.delete(recursive: true));
      // 내용은 상관없다. 합성 바이트만 담는다.
      audioPath = '${dir.path}/speech.wav';
      await File(audioPath).writeAsBytes([1, 2, 3, 4]);
    });

    SpeechApi api(Future<http.Response> Function(http.Request) handler) =>
        ServerSpeechApi(
          ApiClient(
            authorization: () => 'Bearer test-token',
            baseUrl: 'http://api.test',
            client: MockClient(handler),
          ),
        );

    test('녹음 하나를 multipart 로 보내고 글자를 받는다', () async {
      late http.Request sent;
      final speech = api((request) async {
        sent = request;
        return _json({'schemaVersion': 1, 'text': '합성 문장입니다'}, 200);
      });

      expect(await speech.transcribe(audioPath), '합성 문장입니다');
      expect(sent.method, 'POST');
      expect(
        sent.url.toString(),
        'http://api.test/api/v1/speech-transcriptions',
      );
      expect(sent.headers['content-type'], startsWith('multipart/form-data'));
      expect(sent.body, contains('name="audio"; filename="speech.wav"'));
    });

    test('알아듣지 못한 빈 글자도 그대로 돌려준다', () async {
      final speech = api(
        (_) async => _json({'schemaVersion': 1, 'text': ''}, 200),
      );

      expect(await speech.transcribe(audioPath), '');
    });

    test('글자가 없으면 성공으로 넘기지 않는다', () async {
      final speech = api((_) async => _json({'schemaVersion': 1}, 200));

      await expectLater(
        speech.transcribe(audioPath),
        throwsA(isA<ApiUnexpectedResponseFailure>()),
      );
    });

    test('서버가 준 retryable 을 그대로 넘긴다', () async {
      final speech = api(
        (_) async => _json({
          'schemaVersion': 1,
          'errorCode': 'AI_SERVER_TIMEOUT',
          'message': '합성 메시지',
          'requestId': 'req_01',
          'retryable': true,
        }, 504),
      );

      await expectLater(
        speech.transcribe(audioPath),
        throwsA(
          isA<ApiServerFailure>().having((f) => f.retryable, 'retryable', true),
        ),
      );
    });
  });

  group('녹음 시작', () {
    test('마이크 권한이 없으면 녹음하지 않고 알린다', () async {
      final recorder = _FakeRecorder(permitted: false);
      final input = ServerSpeechInput(recorder: recorder, api: _FakeApi([]));

      await expectLater(
        _start(input),
        throwsA(
          isA<SpeechStartFailure>().having(
            (f) => f.problem,
            'problem',
            SpeechStartProblem.micDenied,
          ),
        ),
      );
      expect(recorder.calls, ['hasPermission']);
    });

    test('장치를 열지 못하면 남은 녹음을 지우고 알린다', () async {
      final recorder = _FakeRecorder(failOnStart: true);
      final input = ServerSpeechInput(recorder: recorder, api: _FakeApi([]));

      await expectLater(
        _start(input),
        throwsA(
          isA<SpeechStartFailure>().having(
            (f) => f.problem,
            'problem',
            SpeechStartProblem.unavailable,
          ),
        ),
      );
      expect(recorder.calls.last, 'discard');
    });
  });

  group('결과와 녹음 파일', () {
    test('알아들으면 앞뒤 공백을 뗀 글자를 돌려주고 파일을 지운다', () async {
      final recorder = _FakeRecorder();
      final api = _FakeApi(['  합성 문장입니다  ']);
      final input = ServerSpeechInput(recorder: recorder, api: api);

      final outcome = await (await _start(input)).finish();

      expect(outcome, isA<SpeechHeard>());
      expect((outcome as SpeechHeard).text, '합성 문장입니다');
      expect(api.sentPaths, [_FakeRecorder.path]);
      expect(recorder.calls.last, 'delete ${_FakeRecorder.path}');
    });

    test('빈 글자는 못 알아들음이고 파일을 지운다', () async {
      final recorder = _FakeRecorder();
      final input = ServerSpeechInput(
        recorder: recorder,
        api: _FakeApi(['   ']),
      );

      final outcome = await (await _start(input)).finish();

      expect(outcome, isA<SpeechNotHeard>());
      expect(recorder.calls.last, 'delete ${_FakeRecorder.path}');
    });

    test('녹음 파일이 없으면 보내지 않고 실패로 알린다', () async {
      final recorder = _FakeRecorder(losesFile: true);
      final api = _FakeApi([]);
      final input = ServerSpeechInput(recorder: recorder, api: api);

      final outcome = await (await _start(input)).finish();

      expect(
        outcome,
        isA<SpeechFailed>().having((o) => o.canResend, 'canResend', false),
      );
      expect(api.sentPaths, isEmpty);
    });

    test('연결이 끊기면 파일을 남기고 같은 녹음을 다시 보낸다', () async {
      final recorder = _FakeRecorder();
      final api = _FakeApi([const ApiNetworkFailure(), '합성 문장입니다']);
      final input = ServerSpeechInput(recorder: recorder, api: api);
      final recording = await _start(input);

      final first = await recording.finish();
      expect(
        first,
        isA<SpeechFailed>().having((o) => o.canResend, 'canResend', true),
      );
      expect(
        recorder.calls.where((c) => c.startsWith('delete')),
        isEmpty,
        reason: '다시 보낼 녹음은 지우지 않는다',
      );

      final second = await recording.resend();
      expect(second, isA<SpeechHeard>());
      expect(api.sentPaths, [_FakeRecorder.path, _FakeRecorder.path]);
      expect(recorder.calls.last, 'delete ${_FakeRecorder.path}');
    });

    test('서버가 다시 시도해도 된다고 하면 파일을 남긴다', () async {
      final recorder = _FakeRecorder();
      final input = ServerSpeechInput(
        recorder: recorder,
        api: _FakeApi([
          const ApiServerFailure(
            statusCode: 503,
            errorCode: 'AI_SERVER_UNAVAILABLE',
            retryable: true,
          ),
        ]),
      );

      final outcome = await (await _start(input)).finish();

      expect(
        outcome,
        isA<SpeechFailed>().having((o) => o.canResend, 'canResend', true),
      );
      expect(recorder.calls.where((c) => c.startsWith('delete')), isEmpty);
    });

    test('다시 해도 안 되는 실패는 파일을 지운다', () async {
      final recorder = _FakeRecorder();
      final input = ServerSpeechInput(
        recorder: recorder,
        api: _FakeApi([
          const ApiServerFailure(
            statusCode: 403,
            errorCode: 'SPEECH_PROCESSING_CONSENT_REQUIRED',
          ),
        ]),
      );

      final outcome = await (await _start(input)).finish();

      expect(
        outcome,
        isA<SpeechFailed>().having((o) => o.canResend, 'canResend', false),
      );
      expect(recorder.calls.last, 'delete ${_FakeRecorder.path}');
    });

    test('버리면 남겨 둔 파일을 지운다', () async {
      final recorder = _FakeRecorder();
      final input = ServerSpeechInput(
        recorder: recorder,
        api: _FakeApi([const ApiNetworkFailure()]),
      );
      final recording = await _start(input);
      await recording.finish();

      await recording.cancel();

      expect(recorder.calls.last, 'delete ${_FakeRecorder.path}');
    });
  });

  // PM 확인(PR #146): 하시던 일을 말한 뒤 전사 중에 건너뛰고 고향에서 다시
  // 녹음하면, 앞 전사가 끝나 파일을 지울 때 고향 녹음까지 멈췄다.
  group('앞 항목의 전사가 늦게 끝날 때', () {
    test('앞 파일만 지우고 지금 녹음은 멈추지 않는다', () async {
      final recorder = _FakeRecorder();
      final api = _HeldApi();
      final input = ServerSpeechInput(recorder: recorder, api: api);

      final occupation = await _start(input);
      final heard = occupation.finish();
      final hometown = await input.start(category: 'hometown', attempt: 1);
      await pumpEventQueue();

      api.replies.first.complete('합성 문장입니다');
      expect(await heard, isA<SpeechHeard>());

      expect(recorder.recording, isTrue, reason: '고향 녹음은 계속된다');
      expect(recorder.calls, isNot(contains('discard')));
      expect(recorder.calls.last, 'delete ${_FakeRecorder.path}');

      final second = hometown.finish();
      await pumpEventQueue();
      api.replies.last.complete('합성 고향 문장입니다');
      expect(await second, isA<SpeechHeard>());
      expect(recorder.calls.last, 'delete /fake/speech_inputs/speech-2.wav');
    });

    test('화면을 벗어나 버려도 지금 녹음은 멈추지 않는다', () async {
      final recorder = _FakeRecorder();
      final api = _HeldApi();
      final input = ServerSpeechInput(recorder: recorder, api: api);

      final occupation = await _start(input);
      final heard = occupation.finish();
      await input.start(category: 'hometown', attempt: 1);
      await pumpEventQueue();

      await occupation.cancel();
      api.replies.first.complete('합성 문장입니다');
      await heard;

      expect(recorder.recording, isTrue);
      expect(recorder.calls, isNot(contains('discard')));
    });

    test('녹음하는 중에 버리면 장치를 멈추고 지운다', () async {
      final recorder = _FakeRecorder();
      final input = ServerSpeechInput(recorder: recorder, api: _HeldApi());
      final recording = await _start(input);

      await recording.cancel();
      await recording.cancel();

      expect(recorder.recording, isFalse);
      expect(recorder.calls.where((c) => c == 'discard'), hasLength(1));
    });
  });

  group('기기 녹음 장치', () {
    late Directory folder;
    late DeviceSpeechRecorder recorder;

    setUp(() async {
      final temporary = await Directory.systemTemp.createTemp(
        'saerok_speech_recorder_test',
      );
      addTearDown(() => temporary.delete(recursive: true));
      folder = Directory('${temporary.path}/speech_inputs');
      recorder = DeviceSpeechRecorder(
        recorder: _FakeAudioRecorder(),
        directory: () async => folder,
      );
    });

    test('새 녹음을 시작해도 아직 보내는 파일은 지우지 않는다', () async {
      await folder.create(recursive: true);
      // 앱이 꺼져 지우지 못한 파일이다.
      final leftover = File('${folder.path}/speech-old.wav');
      await leftover.writeAsBytes([1]);

      await recorder.start();
      final sending = (await recorder.stop())!;
      await recorder.start();

      expect(await leftover.exists(), isFalse);
      expect(await File(sending).exists(), isTrue);

      await recorder.delete(sending);
      expect(await File(sending).exists(), isFalse);
    });

    test('파일만 지울 때는 녹음을 멈추지 않는다', () async {
      await recorder.start();
      final finished = (await recorder.stop())!;
      // 파일 이름은 시각으로 짓는다. 같은 이름이 되지 않게 잠시 기다린다.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await recorder.start();

      await recorder.delete(finished);

      final current = (await recorder.stop())!;
      expect(current, isNot(finished));
      expect(await File(current).exists(), isTrue);
    });
  });

  test('최대 길이에 닿으면 알린다', () async {
    final input = ServerSpeechInput(
      recorder: _FakeRecorder(),
      api: _FakeApi([]),
      maxDuration: const Duration(milliseconds: 10),
    );
    final recording = await _start(input);

    await expectLater(
      recording.limitReached.timeout(const Duration(seconds: 1)),
      completes,
    );
    await recording.cancel();
  });
}
