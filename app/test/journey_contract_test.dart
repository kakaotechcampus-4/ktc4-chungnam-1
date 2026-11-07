// 여정 테스트의 가짜 서버(`journey/journey_server.dart`)가 돌려주는 응답과 앱이
// 만드는 요청 본문이 BE 의 pydantic 스키마(`backend/app/schemas/*.py`)와 같은
// 필드 이름을 쓰는지 확인한다.
//
// BE 모델은 `extra="forbid"` 이고 응답은 모든 필드를 내보내므로, 응답은 필드
// 이름이 정확히 같아야 하고 요청은 필수 필드를 담되 모르는 필드가 없어야 한다.
// 타입, 값의 범위와 enum 값은 비교하지 않는다. 파이썬 파일을 글자로 읽는 가벼운
// 검사라 스키마를 다른 방식으로 선언하면 따라 고쳐야 한다.
//
// 저장소 루트의 `backend/` 를 읽으므로 호스트의 `flutter test` 에서만 돈다.
// 기기에서 도는 여정(`integration_test/`)에는 넣지 않는다. CI(`CI=true`)에서
// `backend/` 를 찾지 못하면 건너뛰지 않고 실패한다.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:saerok/data/api_client.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/profile_api.dart';
import 'package:saerok/data/visit_api.dart';

import 'journey/journey_server.dart';

final _schemaDir = Directory('../backend/app/schemas');
final _speechRoute = File('../backend/app/api/routes/speech_analyses.py');

void main() {
  // 앱만 따로 받은 곳에서는 건너뛴다. CI 는 저장소 전체를 받으므로 없으면
  // 경로가 바뀐 것이다. 조용히 초록으로 끝내지 않는다.
  final inCi = Platform.environment['CI'] == 'true';
  final skip = _schemaDir.existsSync() || inCi
      ? false
      : '저장소 루트의 backend/app/schemas 가 없다';

  late Map<String, _PyClass> schemas;
  setUpAll(() {
    if (skip != false) return;
    if (!_schemaDir.existsSync()) {
      fail('CI 에서 ${_schemaDir.absolute.path} 를 찾지 못했다');
    }
    schemas = _parseSchemas(_schemaDir);
  });

  test('스키마 읽기가 알려진 모델의 필드를 찾는다', () {
    final report = schemas['VisitReport']!;
    expect(report.fields.map((f) => f.alias), [
      'schemaVersion',
      'sessionId',
      'title',
      'body',
      'visitDate',
      'mood',
      'photo',
      'cardSummaries',
      'generatedAt',
    ]);
    // alias_generator(to_camel) 를 쓰는 모델.
    expect(
      schemas['CardSet']!.fields.map((f) => f.alias),
      containsAll(['setId', 'usedBySessionId', 'needsRefresh', 'cards']),
    );
  }, skip: skip);

  test('가짜 서버의 응답이 BE 응답 모델과 같은 필드를 쓴다', () async {
    final server = JourneyServer(
      plans: [AnalysisPlan.failed, AnalysisPlan.insufficientSpeakerLabels],
    );
    await _driveServer(server);

    final checked = <String>{};
    for (final r in server.responses) {
      final model = r.status >= 400 ? 'ErrorResponse' : _responseModel(r);
      expect(model, isNotNull, reason: '스키마를 정하지 않은 응답: ${r.method} ${r.path}');
      if (r.body == null) continue;
      _expectShape(schemas, model!, r.body, response: true, at: r.path);
      checked.add(model);
    }
    expect(
      checked,
      containsAll([
        'AccountResponse',
        'ProfileListResponse',
        'ProfileResponse',
        'CardGenerationStatus',
        'CardSet',
        'VisitSession',
        'CaregiverEvaluation',
        'SpeechAnalysisAccepted',
        'SpeechAnalysisStatusResponse',
        'VisitSessionListResponse',
        'ReportListResponse',
        'VisitReport',
        'ChangeProposal',
        'LifeFactResponse',
        'ErrorResponse',
      ]),
    );
  }, skip: skip);

  test('앱이 만드는 평가와 변경 제안 검토 요청이 BE 요청 모델을 따른다', () {
    const evaluation = EvaluationSubmission(
      conversationSatisfaction: 4,
      careRecipientReaction: CareRecipientReaction.pleased,
      cardReviews: [
        CardReview(
          cardId: 'card-1',
          wasUsed: true,
          caregiverReaction: CaregiverReaction.positive,
        ),
        CardReview(cardId: 'card-2', wasUsed: false, caregiverReaction: null),
      ],
      freeNote: null,
    );
    _expectShape(
      schemas,
      'CaregiverEvaluationRequest',
      evaluation.toJson(),
      response: false,
      at: '6-1',
    );

    const review = ProposalReview(
      lifeFacts: [
        LifeFactReview.accepted(proposalId: 'p1', title: '제목', content: '내용'),
        LifeFactReview.rejected(proposalId: 'p2'),
      ],
      topics: [
        TopicReview.accepted(proposalId: 'p3', action: TopicAction.more),
        TopicReview.rejected(proposalId: 'p4'),
      ],
    );
    _expectShape(
      schemas,
      'ProposalReviewRequest',
      review.toJson(),
      response: false,
      at: '7-4',
    );
  }, skip: skip);

  test('앱이 만드는 회차, 이야기 고치기, 녹음 요청이 BE 요청 형식을 따른다', () async {
    // 앱의 실제 API 코드(ServerVisitApi, ProfileApi)로 가짜 서버를 부르고, 서버가
    // 받은 본문을 비교한다.
    final server = JourneyServer();
    final client = ApiClient(
      authorization: () => 'Bearer journey-token',
      baseUrl: JourneyServer.baseUrl,
      client: server.client,
    );
    final visits = ServerVisitApi(client);
    final profiles = ProfileApi(client);

    final setId = server.setIds.single;
    final current = await client.get(
      '/api/v1/profiles/${JourneyServer.profileId}/card-generations/current',
    );
    final cardIds = [
      for (final card in (current['cards'] as List).take(2))
        (card as Map)['cardId'] as String,
    ];
    final session = await visits.createSession(
      setId: setId,
      selectedCardIds: cardIds,
    );
    await visits.submitEvaluation(
      session.sessionId,
      EvaluationSubmission(
        conversationSatisfaction: 4,
        careRecipientReaction: CareRecipientReaction.pleased,
        cardReviews: [
          CardReview(
            cardId: cardIds.first,
            wasUsed: true,
            caregiverReaction: CaregiverReaction.positive,
          ),
        ],
        freeNote: null,
      ),
    );
    final audioDir = Directory.systemTemp.createTempSync('saerok_contract_');
    addTearDown(() => audioDir.deleteSync(recursive: true));
    final audio = File('${audioDir.path}${Platform.pathSeparator}v.wav')
      ..writeAsBytesSync(List.filled(44, 0));
    await visits.submitAudio(
      session.sessionId,
      audioPath: audio.path,
      participantCount: 2,
    );

    // 7-4 를 거치지 않고 일대기에 이야기 하나를 둔다. 고치기 요청만 본다.
    server.lifeFacts.add({
      'schemaVersion': 1,
      'factId': '77777777-0000-4000-8000-000000000001',
      'profileId': JourneyServer.profileId,
      'storyCategory': 'other',
      'title': '수선집 시절',
      'content': '옷을 고치셨어요.',
      'imageNumber': 1,
      'createdAt': '2026-10-13T17:00:00+09:00',
    });
    await profiles.updateLifeFact(
      '77777777-0000-4000-8000-000000000001',
      storyCategory: 'other',
      title: '고친 제목',
      content: '고친 내용',
      imageNumber: 1,
    );

    Object? bodyOf(String method, bool Function(String) path) => server.requests
        .singleWhere((r) => r.method == method && path(r.path))
        .body;

    _expectShape(
      schemas,
      'CreateVisitSessionRequest',
      bodyOf('POST', (p) => p == '/api/v1/visit-sessions'),
      response: false,
      at: '5-1',
    );
    _expectShape(
      schemas,
      'LifeFactUpdateRequest',
      bodyOf('PATCH', (p) => p.startsWith('/api/v1/life-facts/')),
      response: false,
      at: '2-7',
    );

    // 6-2 는 pydantic 모델이 아니라 라우트의 File, Form 인자로 받는다.
    final sent = (bodyOf('POST', (p) => p.endsWith('/speech-analyses'))! as Map)
        .keys
        .toSet();
    expect(sent, _multipartNames(_speechRoute, 'submit_speech_analysis'));
  }, skip: skip);
}

/// 라우트 함수 [function] 이 받는 multipart 이름. `File()` 인자는 인자 이름,
/// `Form(alias=...)` 인자는 alias 를 쓴다.
Set<String> _multipartNames(File route, String function) {
  final source = route.readAsStringSync();
  final start = source.indexOf('async def $function(');
  expect(
    start,
    greaterThanOrEqualTo(0),
    reason: '${route.path} 에 $function 이 없다',
  );
  final end = source.indexOf(') ->', start);
  final params = source.substring(start, end);
  final names = {
    for (final m in RegExp(
      r'(\w+): Annotated\[\s*UploadFile,\s*File\(\)',
    ).allMatches(params))
      m.group(1)!,
    for (final m in RegExp(r'Form\(alias="(\w+)"').allMatches(params))
      m.group(1)!,
  };
  expect(names, isNotEmpty, reason: '$function 의 File, Form 인자를 읽지 못했다');
  return names;
}

/// 여정에서 앱이 부르는 순서대로 가짜 서버를 직접 부른다. 분석은 한 번 실패한
/// 뒤 다시 요청하고, 두 번째 면회는 라벨이 부족해도 일반 리포트와 후보를 반환한다.
Future<void> _driveServer(JourneyServer server) async {
  final client = server.client;
  const base = JourneyServer.baseUrl;
  final profile = '$base/api/v1/profiles/${JourneyServer.profileId}';

  Future<Map<String, dynamic>> call(
    String method,
    String url, [
    Object? body,
  ]) async {
    final request = http.Request(method, Uri.parse(url));
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await http.Response.fromStream(await client.send(request));
    return response.body.isEmpty
        ? const {}
        : jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<String> visit() async {
    final current = await call('GET', '$profile/card-generations/current');
    final cards = (current['cards'] as List).cast<Map<String, dynamic>>();
    final session = await call('POST', '$base/api/v1/visit-sessions', {
      'setId': current['setId'],
      'selectedCardIds': [cards[0]['cardId'], cards[1]['cardId']],
    });
    final sessionId = session['sessionId'] as String;
    await call('POST', '$base/api/v1/visit-sessions/$sessionId/evaluation', {
      'conversationSatisfaction': 4,
      'careRecipientReaction': 'pleased',
      'cardReviews': [
        {
          'cardId': cards[0]['cardId'],
          'wasUsed': true,
          'caregiverReaction': 'positive',
        },
      ],
      'freeNote': null,
    });
    final upload =
        http.MultipartRequest(
            'POST',
            Uri.parse('$base/api/v1/visit-sessions/$sessionId/speech-analyses'),
          )
          ..fields['participantCount'] = '2'
          ..files.add(
            http.MultipartFile.fromBytes(
              'audio',
              List.filled(44, 0),
              filename: 'v.wav',
            ),
          );
    final accepted = jsonDecode(
      (await http.Response.fromStream(await client.send(upload))).body,
    );
    var analysisId = accepted['analysisId'] as String;
    for (var i = 0; i < 10; i++) {
      final status = await call(
        'GET',
        '$base/api/v1/speech-analyses/$analysisId',
      );
      if (status['status'] == 'completed') break;
      if (status['status'] == 'failed') {
        final retried = await call(
          'POST',
          '$base/api/v1/speech-analyses/$analysisId/retry',
        );
        analysisId = retried['analysisId'] as String;
      }
    }
    await call('GET', '$profile/visit-sessions?limit=1');
    await call('GET', '$base/api/v1/visit-sessions/$sessionId/report');
    await call('GET', '$base/api/v1/visit-sessions/$sessionId/evaluation');
    return sessionId;
  }

  await call('GET', '$base/auth/me');
  await call('GET', '$base/api/v1/profiles');
  await call('GET', profile);
  await call('GET', '$profile/card-generations/status');

  final first = await visit();
  final proposals = await call(
    'GET',
    '$base/api/v1/visit-sessions/$first/proposals',
  );
  final fact = (proposals['lifeFactProposals'] as List).single as Map;
  await call('POST', '$base/api/v1/visit-sessions/$first/proposals/review', {
    'lifeFacts': [
      {
        'proposalId': fact['proposalId'],
        'reviewStatus': 'accepted',
        'title': '제목',
        'content': '고친 내용',
      },
    ],
    'topics': <Object>[],
  });
  await call('GET', '$profile/reports');
  await call('GET', profile);

  await call('POST', '$profile/card-generations');
  await call('GET', '$profile/card-generations/status');
  await call('GET', '$profile/card-generations/status');
  final factId = server.lifeFacts.single['factId'];
  await call('PATCH', '$base/api/v1/life-facts/$factId', {
    'storyCategory': 'other',
    'title': '고친 제목',
    'content': '고친 내용',
    'imageNumber': 1,
  });
  // 고친 뒤의 묶음으로는 회차를 만들지 못한다(오류 응답).
  final stale = await call('GET', '$profile/card-generations/current');
  await call('POST', '$base/api/v1/visit-sessions', {
    'setId': stale['setId'],
    'selectedCardIds': [(stale['cards'] as List).first['cardId']],
  });
  await call('POST', '$profile/card-generations');
  await call('GET', '$profile/card-generations/status');
  await call('GET', '$profile/card-generations/status');
  final second = await visit();
  await call('GET', '$base/api/v1/visit-sessions/$second/proposals');
}

String? _responseModel(
  ({String method, String path, int status, Object? body}) r,
) {
  final p = r.path;
  final m = r.method;
  if (p == '/auth/me') return 'AccountResponse';
  if (p == '/api/v1/profiles') return 'ProfileListResponse';
  if (RegExp(r'^/api/v1/profiles/[^/]+$').hasMatch(p)) return 'ProfileResponse';
  if (p.endsWith('/card-generations') ||
      p.endsWith('/card-generations/status')) {
    return 'CardGenerationStatus';
  }
  if (p.endsWith('/card-generations/current')) return 'CardSet';
  if (RegExp(r'^/api/v1/profiles/[^/]+/visit-sessions$').hasMatch(p)) {
    return 'VisitSessionListResponse';
  }
  if (p.endsWith('/reports')) return 'ReportListResponse';
  if (p == '/api/v1/visit-sessions' && m == 'POST') return 'VisitSession';
  if (p.endsWith('/evaluation')) return 'CaregiverEvaluation';
  if (RegExp(r'^/api/v1/visit-sessions/[^/]+/speech-analyses$').hasMatch(p)) {
    return 'SpeechAnalysisAccepted';
  }
  if (p.endsWith('/retry')) return 'SpeechAnalysisAccepted';
  if (RegExp(r'^/api/v1/speech-analyses/[^/]+$').hasMatch(p)) {
    return 'SpeechAnalysisStatusResponse';
  }
  if (p.endsWith('/report')) return 'VisitReport';
  if (p.endsWith('/proposals') || p.endsWith('/proposals/review')) {
    return 'ChangeProposal';
  }
  if (RegExp(r'^/api/v1/life-facts/[^/]+$').hasMatch(p)) {
    return 'LifeFactResponse';
  }
  return null;
}

/// [value] 가 [model] 의 필드 이름을 따르는지 확인한다. 하위 모델도 따라간다.
///
/// 응답은 필드가 정확히 같아야 한다. 요청은 기본값 없는 필드를 모두 담고 모르는
/// 필드가 없으면 된다.
void _expectShape(
  Map<String, _PyClass> schemas,
  String model,
  Object? value, {
  required bool response,
  required String at,
}) {
  if (value == null) return;
  if (value is List) {
    for (final (i, item) in value.indexed) {
      _expectShape(schemas, model, item, response: response, at: '$at[$i]');
    }
    return;
  }
  final schema = schemas[model];
  expect(schema, isNotNull, reason: 'BE 스키마에 $model 이 없다 ($at)');
  expect(value, isA<Map>(), reason: '$at 은 $model 객체여야 한다');
  final map = (value as Map).cast<String, Object?>();
  final fields = schema!.allFields(schemas);
  final names = {for (final f in fields) f.alias};
  if (response) {
    expect(map.keys.toSet(), names, reason: '$at 의 필드가 $model 과 다르다');
  } else {
    expect(
      names.containsAll(map.keys),
      isTrue,
      reason: '$at 에 $model 이 모르는 필드: ${map.keys.toSet().difference(names)}',
    );
    final required = {
      for (final f in fields)
        if (!f.optional) f.alias,
    };
    expect(
      map.keys.toSet().containsAll(required),
      isTrue,
      reason:
          '$at 에 $model 의 필수 필드가 없다: ${required.difference(map.keys.toSet())}',
    );
  }
  for (final field in fields) {
    final nested = field.nestedModel(schemas);
    if (nested == null || !map.containsKey(field.alias)) continue;
    _expectShape(
      schemas,
      nested,
      map[field.alias],
      response: response,
      at: '$at.${field.alias}',
    );
  }
}

// ── pydantic 스키마 읽기 ──────────────────────────────

class _PyField {
  _PyField(this.name, this.alias, this.annotation, {required this.optional});

  final String name;
  final String alias;
  final String annotation;

  /// 기본값이 있어 요청에서 빼도 되는 필드.
  final bool optional;

  /// 타입에 적힌 모델 이름. `list[CardSummary]`, `ReportPhoto | None` 같은 꼴이다.
  String? nestedModel(Map<String, _PyClass> schemas) {
    // `Literal["inVisit"]` 같은 글자 값 안의 낱말은 모델 이름이 아니다.
    final types = annotation.replaceAll(RegExp(r'"[^"]*"'), '');
    for (final match in RegExp(r'[A-Z]\w*').allMatches(types)) {
      final name = match.group(0)!;
      if (schemas.containsKey(name)) return name;
    }
    return null;
  }
}

class _PyClass {
  _PyClass(this.name, this.bases);

  final String name;
  final List<String> bases;
  final fields = <_PyField>[];

  bool usesCamel(Map<String, _PyClass> schemas) =>
      name == 'CamelModel' ||
      bases.any((b) => schemas[b]?.usesCamel(schemas) ?? false);

  List<_PyField> allFields(Map<String, _PyClass> schemas) => [
    for (final base in bases) ...?schemas[base]?.allFields(schemas),
    ...fields,
  ];
}

Map<String, _PyClass> _parseSchemas(Directory dir) {
  final raw = <String, ({List<String> bases, List<String> lines})>{};
  final duplicates = <String>{};
  for (final file in dir.listSync().whereType<File>()) {
    if (!file.path.endsWith('.py')) continue;
    String? current;
    var inDocstring = false;
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final header = RegExp(r'^class (\w+)\(([\w, ]+)\):').firstMatch(line);
      if (header != null) {
        current = header.group(1)!;
        if (raw.containsKey(current)) duplicates.add(current);
        raw[current] = (
          bases: header.group(2)!.split(',').map((b) => b.trim()).toList(),
          lines: [],
        );
        inDocstring = false;
        continue;
      }
      if (line.isNotEmpty && !line.startsWith(' ')) {
        current = null;
        continue;
      }
      if (current == null) continue;
      if ('"""'.allMatches(line).length.isOdd) {
        inDocstring = !inDocstring;
        continue;
      }
      if (inDocstring) continue;
      if (!RegExp(r'^    [a-z_][a-z0-9_]*\s*:').hasMatch(line)) continue;
      // 괄호가 닫힐 때까지 이어진 줄을 붙인다.
      var logical = line;
      var depth = _depth(line);
      while (depth > 0 && i + 1 < lines.length) {
        i++;
        logical += ' ${lines[i].trim()}';
        depth += _depth(lines[i]);
      }
      raw[current]!.lines.add(logical);
    }
  }

  final classes = <String, _PyClass>{
    for (final entry in raw.entries)
      if (!duplicates.contains(entry.key))
        entry.key: _PyClass(entry.key, entry.value.bases),
  };
  for (final entry in raw.entries) {
    final schema = classes[entry.key];
    if (schema == null) continue;
    final camel = schema.usesCamel(classes);
    for (final line in entry.value.lines) {
      final m = RegExp(r'^    (\w+)\s*:\s*(.*)$').firstMatch(line)!;
      final name = m.group(1)!;
      final rest = m.group(2)!;
      final eq = _topLevelEquals(rest);
      final annotation = eq < 0 ? rest : rest.substring(0, eq).trim();
      final value = eq < 0 ? '' : rest.substring(eq + 1).trim();
      final explicit = RegExp(r'alias="(\w+)"').firstMatch(value)?.group(1);
      final optional =
          value.isNotEmpty &&
          (!value.startsWith('Field(') ||
              value.contains('default=') ||
              value.contains('default_factory='));
      schema.fields.add(
        _PyField(
          name,
          explicit ?? (camel ? _toCamel(name) : name),
          annotation,
          optional: optional,
        ),
      );
    }
  }
  return classes;
}

int _depth(String line) =>
    '('.allMatches(line).length +
    '['.allMatches(line).length -
    ')'.allMatches(line).length -
    ']'.allMatches(line).length;

/// 괄호 밖의 첫 `=` 위치. 없으면 -1 이다.
int _topLevelEquals(String text) {
  var depth = 0;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '(' || c == '[') depth++;
    if (c == ')' || c == ']') depth--;
    if (c == '=' && depth == 0) return i;
  }
  return -1;
}

/// pydantic 의 `to_camel` 과 같다. `used_by_session_id` → `usedBySessionId`.
String _toCamel(String snake) {
  final parts = snake.split('_');
  return parts.first +
      parts
          .skip(1)
          .map((p) => p.isEmpty ? p : p[0].toUpperCase() + p.substring(1))
          .join();
}
