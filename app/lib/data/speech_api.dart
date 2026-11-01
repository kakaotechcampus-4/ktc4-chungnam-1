/// 짧은 음성 전사 API(이슈 #138 의 BE 답변).
///
/// 세부 정보 입력에서 녹음 하나를 보내면 글자를 바로 돌려받는다. 면회 녹음의
/// 음성 분석(6-2)과 달리 프로필이나 회차에 묶지 않는다. 아직
/// `docs/architecture/api-spec.md` 에 들어가지 않아 이슈의 합의를 따른다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';

/// 결과를 기다리는 최대 시간.
///
/// **잠정값이다.** BE 의 시간 제한은 AI 의 처리 시간 측정 뒤에 정한다(이슈
/// #138). 그 전까지 앱은 넉넉하게 두라는 BE 의견을 따른다. 5분 녹음은 약
/// 9.6MB 라 올리는 시간도 함께 든다.
const speechTranscriptionTimeout = Duration(minutes: 2);

abstract interface class SpeechApi {
  /// WAV 파일 하나를 보내고 글자를 받는다.
  ///
  /// 알아듣지 못하면 빈 문자열이다. 실패는 [ApiFailure] 로 던진다.
  Future<String> transcribe(String audioPath);
}

class ServerSpeechApi implements SpeechApi {
  const ServerSpeechApi(this._client);

  final ApiClient _client;

  @override
  Future<String> transcribe(String audioPath) async {
    final body = await _client.postMultipart(
      '/api/v1/speech-transcriptions',
      files: [await http.MultipartFile.fromPath('audio', audioPath)],
      limit: speechTranscriptionTimeout,
    );
    final text = body['text'];
    if (text is! String) {
      throw const ApiUnexpectedResponseFailure('text 가 없다');
    }
    return text;
  }
}

final speechApiProvider = Provider<SpeechApi>(
  (ref) => ServerSpeechApi(ref.watch(apiClientProvider)),
);
