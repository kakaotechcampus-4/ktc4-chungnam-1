// 앱 전체 여정 테스트가 쓰는 가짜 새록 서버다.
//
// 앱의 실제 API 코드(ProfileApi, ServerCardApi, ServerVisitApi, ReportApi,
// AuthApi)는 그대로 두고 HTTP 경계만 이 서버로 바꾼다. 회차, 카드 묶음, 분석
// 작업과 리포트 상태를 한곳에서 들고 있어, 앱이 보낸 요청이 다음 화면의 응답을
// 바꾼다. 예를 들어 이야기를 고치면 아직 쓰지 않은 카드 묶음이 `needsRefresh`
// 가 되고, 그 묶음으로 회차를 만들면 `CARD_SET_NEEDS_REFRESH` 로 거절한다.
//
// 규칙은 `docs/architecture/api-spec.md` 와 `backend/app/services/` 의 동작을
// 줄여 옮긴 것이다. 실제 서버, STT, LLM 을 대신해 정해 둔 결과를 돌려줄 뿐이며
// 서버 구현을 검증하지 않는다. 응답 모양은 `test/journey_contract_test.dart` 가
// BE 의 pydantic 스키마와 비교한다.
//
// 값은 모두 합성이다. 실제 사용자의 음성, 사진, 이름이나 생애 정보가 아니다.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 음성 분석 하나가 어떻게 끝날지 정해 둔다. STT 와 리포트 모델을 대신한다.
enum AnalysisPlan {
  /// 리포트, 카드 요약과 이야기 제안을 만든다.
  success,

  /// 분석이 실패한다(`failed`). 다시 요청하면 [success] 로 끝난다.
  failed,

  /// 라벨이 부족해도 일반 리포트와 후보를 반환하는 합성 응답이다.
  /// 실제 STT와 모델의 화자 추론은 검사하지 않는다.
  insufficientSpeakerLabels,
}

const journeyUncertainProposalReason =
    '대화 흐름상 어르신의 경험으로 보아 제안했습니다. '
    '화자가 명확하지 않아 누구의 경험인지 확인이 필요합니다.';

/// 일반 리포트의 합성 문장.
const journeyReportTitle = '수선집 이야기를 나눈 날';
const journeyReportBody = '오늘은 수선집을 하시던 시절 이야기를 나눴어요.';
const journeyCardSummary = '단골손님 옷을 고쳐 주던 이야기를 하셨어요.';

/// 이야기 제안. 보호자가 내용을 고쳐 승인한다.
const journeyProposalTitle = '한복 짓던 시절';
const journeyProposalContent = '한복을 주로 지으셨어요.';

class JourneyServer {
  JourneyServer({List<AnalysisPlan> plans = const [AnalysisPlan.success]})
    : _plans = [...plans] {
    _profile = {
      'schemaVersion': 1,
      'profileId': profileId,
      'setupStatus': 'completed',
      'name': '김새록',
      'gender': 'female',
      'birthDate': '1943-03-12',
      'condition': {'stage': 'mildDementia', 'symptomNote': null},
      'occupation': '수선집을 오래 하셨어요.',
      'hometown': null,
      'hobby': null,
      'family': null,
      'lifeFacts': <Map<String, Object?>>[],
      'photos': <Object>[],
      'createdAt': '2026-10-13T09:00:00+09:00',
    };
    // 온보딩 `마치기` 에서 첫 카드를 이미 만들었다(API 4-1, 2026-10-14 결정).
    _sets.add(_buildSet(ready: true));
  }

  static const baseUrl = 'http://journey.test';
  static const accountId = 'journey-account';
  static final profileId = _id('1', 1);

  /// 회차마다 쓸 분석 결과. 다 쓰면 [AnalysisPlan.success] 다.
  final List<AnalysisPlan> _plans;

  late final Map<String, Object?> _profile;
  final _sets = <_CardSet>[];
  final _sessions = <_Session>[];
  final _analyses = <String, _Analysis>{};
  int _next = 1;

  /// 받은 요청. 본문은 JSON 이면 읽은 값, multipart 면 필드 값이다.
  final requests = <({String method, String path, Object? body})>[];

  /// 받은 요청에 돌려준 응답. 스키마 비교(`journey_contract_test.dart`)에 쓴다.
  final responses =
      <({String method, String path, int status, Object? body})>[];

  /// `true` 인 동안 분석 작업이 다음 단계로 나아가지 않는다. 홈의 `만드는 중`
  /// 을 확인한 뒤 풀어 도착을 확인한다.
  bool holdAnalyses = false;

  http.Client get client => MockClient(handle);

  // ── 테스트가 확인할 값 ──────────────────────────────

  /// 지금까지 만든 카드 묶음 ID. 만든 순서다.
  List<String> get setIds => [for (final s in _sets) s.setId];

  /// 회차를 만든 요청(5-1)이 쓴 카드 묶음 ID. 만든 순서다.
  List<String> get sessionSetIds => [for (final s in _sessions) s.setId];

  /// 서버에 저장된 이야기(2-3 의 `lifeFacts`).
  List<Map<String, Object?>> get lifeFacts =>
      (_profile['lifeFacts']! as List).cast<Map<String, Object?>>();

  /// [setId] 묶음의 카드 제목. 화면에서 고를 때 쓴다.
  List<String> cardTitlesOf(String setId) => [
    for (final card in _sets.firstWhere((s) => s.setId == setId).cards)
      card['cardTitle']! as String,
  ];

  /// [path] 로 받은 [method] 요청 수.
  int count(String method, String path) =>
      requests.where((r) => r.method == method && r.path == path).length;

  // ── 요청 처리 ────────────────────────────────────

  Future<http.Response> handle(http.Request request) async {
    final multipart =
        request.headers['content-type']?.startsWith('multipart/') ?? false;
    final path = request.url.path;
    final Object? body;
    if (multipart) {
      body = _multipartFields(latin1.decode(request.bodyBytes));
    } else {
      body = request.body.isEmpty ? null : jsonDecode(request.body);
    }
    requests.add((method: request.method, path: path, body: body));

    final response = _route(request.method, request.url, body);
    responses.add((
      method: request.method,
      path: path,
      status: response.status,
      body: response.body,
    ));
    if (response.body == null) return http.Response('', response.status);
    return http.Response.bytes(
      utf8.encode(jsonEncode(response.body)),
      response.status,
      headers: {'content-type': 'application/json'},
    );
  }

  _Reply _route(String method, Uri url, Object? body) {
    final s = url.pathSegments;
    final key = '$method ${s.join('/')}';

    if (key == 'GET auth/me') return _ok(_account());

    if (s.length < 3 || s[0] != 'api' || s[1] != 'v1') return _notFound();
    final rest = s.sublist(2);

    // 2-1 어르신 목록
    if (method == 'GET' && rest.length == 1 && rest[0] == 'profiles') {
      return _ok({
        'schemaVersion': 1,
        'profiles': [
          {
            'profileId': profileId,
            'name': _profile['name'],
            'gender': _profile['gender'],
            'setupStatus': _profile['setupStatus'],
          },
        ],
      });
    }

    if (rest[0] == 'profiles' && rest.length >= 2) {
      if (rest[1] != profileId) return _error(404, 'PROFILE_NOT_FOUND');
      final tail = rest.sublist(2).join('/');
      switch ('$method $tail') {
        case 'GET ':
          return _ok(_profile);
        case 'POST card-generations':
          return _requestCards();
        case 'GET card-generations/status':
          return _cardStatus();
        case 'GET card-generations/current':
          return _currentCards();
        case 'GET visit-sessions':
          final limit = int.parse(url.queryParameters['limit'] ?? '20');
          return _ok({
            'schemaVersion': 1,
            'sessions': [
              for (final session in _sessions.reversed.take(limit))
                session.toJson(),
            ],
          });
        case 'GET reports':
          return _ok({
            'schemaVersion': 1,
            'reports': [
              for (final session in _sessions.reversed)
                if (session.report case final report?)
                  {
                    'sessionId': report['sessionId'],
                    'title': report['title'],
                    'visitDate': report['visitDate'],
                    'mood': report['mood'],
                    'photo': report['photo'],
                  },
            ],
          });
      }
      return _notFound();
    }

    // 2-7 이야기 고치기. 아직 쓰지 않은 카드 묶음을 갱신 필요로 둔다.
    if (method == 'PATCH' && rest.length == 2 && rest[0] == 'life-facts') {
      final index = lifeFacts.indexWhere((f) => f['factId'] == rest[1]);
      if (index < 0) return _error(404, 'LIFE_FACT_NOT_FOUND');
      final updated = {
        ...lifeFacts[index],
        ...(body! as Map).cast<String, Object?>(),
      };
      lifeFacts[index] = updated;
      _markUnusedSetsStale();
      return _ok(updated);
    }

    // 5-1 회차 만들기
    if (method == 'POST' && rest.length == 1 && rest[0] == 'visit-sessions') {
      return _createSession((body! as Map).cast<String, Object?>());
    }

    if (rest[0] == 'visit-sessions' && rest.length >= 3) {
      final session = _sessions
          .where((x) => x.sessionId == rest[1])
          .firstOrNull;
      if (session == null) return _error(404, 'VISIT_SESSION_NOT_FOUND');
      switch ('$method ${rest.sublist(2).join('/')}') {
        case 'POST evaluation':
          return _saveEvaluation(session, (body! as Map).cast());
        case 'GET evaluation':
          final evaluation = session.evaluation;
          return evaluation == null
              ? _error(404, 'EVALUATION_NOT_FOUND')
              : _ok(evaluation);
        case 'POST speech-analyses':
          return _acceptAudio(session, (body! as Map).cast());
        case 'GET report':
          final report = session.report;
          return report == null ? _error(404, 'REPORT_NOT_FOUND') : _ok(report);
        case 'GET proposals':
          final proposal = session.proposal;
          return proposal == null
              ? _error(404, 'REPORT_NOT_FOUND')
              : _ok(proposal);
        case 'POST proposals/review':
          return _review(session, (body! as Map).cast());
        case 'PATCH cards':
          return _addCards(session, (body! as Map).cast());
      }
      return _notFound();
    }

    // 6-3 분석 상태, 6-5 다시 요청
    if (rest[0] == 'speech-analyses' && rest.length >= 2) {
      final analysis = _analyses[rest[1]];
      if (analysis == null) return _error(404, 'SPEECH_ANALYSIS_NOT_FOUND');
      if (method == 'GET' && rest.length == 2) return _advance(analysis);
      if (method == 'POST' && rest.length == 3 && rest[2] == 'retry') {
        return _retry(analysis);
      }
    }
    return _notFound();
  }

  // ── 4절 카드 ─────────────────────────────────────

  _CardSet? get _latest => _sets.lastOrNull;

  /// BE `card_sets._status` 와 같은 규칙이다.
  String _statusOf(_CardSet? set) {
    if (set == null) return 'none';
    if (!set.ready) return 'running';
    final session = _sessions.where((x) => x.setId == set.setId).firstOrNull;
    if (session == null) return 'ready';
    return session.evaluation == null ? 'inVisit' : 'none';
  }

  bool _needsRefresh(_CardSet? set) => _statusOf(set) == 'ready' && set!.stale;

  _Reply _requestCards() {
    final status = _statusOf(_latest);
    if (status == 'ready' && !_latest!.stale) {
      return _error(409, 'CARD_SET_READY');
    }
    if (status == 'inVisit') return _error(409, 'VISIT_IN_PROGRESS');
    if (status != 'running') _sets.add(_buildSet(ready: false));
    return _ok({
      'schemaVersion': 1,
      'status': 'running',
      'needsRefresh': false,
    });
  }

  _Reply _cardStatus() {
    final latest = _latest;
    // 만드는 중인 묶음은 한 번 물으면 다 만든다. 생성 모델을 대신한다.
    if (latest != null && !latest.ready) {
      latest.ready = true;
      return _ok({
        'schemaVersion': 1,
        'status': 'running',
        'needsRefresh': false,
      });
    }
    return _ok({
      'schemaVersion': 1,
      'status': _statusOf(latest),
      'needsRefresh': _needsRefresh(latest),
    });
  }

  _Reply _currentCards() {
    final latest = _latest;
    final status = _statusOf(latest);
    if (status != 'ready' && status != 'inVisit') {
      return _error(404, 'CARD_GENERATION_NOT_FOUND');
    }
    final usedBy = _sessions
        .where((x) => x.setId == latest!.setId)
        .firstOrNull
        ?.sessionId;
    return _ok({
      'schemaVersion': 1,
      'setId': latest!.setId,
      'usedBySessionId': usedBy,
      'needsRefresh': _needsRefresh(latest),
      'cards': latest.cards,
    });
  }

  /// 2-4, 2-7, 2-9 가 아직 면회에 쓰지 않은 묶음에 `stale_at` 을 찍는 것과 같다.
  void _markUnusedSetsStale() {
    for (final set in _sets) {
      if (set.ready && !_sessions.any((x) => x.setId == set.setId)) {
        set.stale = true;
      }
    }
  }

  /// 12장을 만든다. 1번 카드는 가장 최근 이야기로 만들어, 정정한 이야기가
  /// 새 묶음에 들어갔는지 화면에서 확인할 수 있게 한다.
  _CardSet _buildSet({required bool ready}) {
    final generation = _sets.length + 1;
    final setId = _id('2', generation);
    final fact = lifeFacts.lastOrNull;
    final cards = <Map<String, Object?>>[];
    for (var position = 1; position <= 12; position++) {
      final fromFact = position == 1 && fact != null;
      final title = fromFact
          ? fact['title']! as String
          : position == 1
          ? '수선집 시절'
          : '$generation회 준비 카드 $position';
      cards.add({
        'cardId': _id('3', generation * 100 + position),
        'position': position,
        'topic': {
          'topicId': _id('8', generation * 100 + position),
          'title': fromFact ? '이야기' : '일',
          'description': '합성 주제 설명이에요.',
        },
        'cardTitle': title,
        'description': fromFact ? fact['content']! as String : '합성 카드 설명이에요.',
        'primaryQuestion': '그때 이야기를 들려주시겠어요?',
        'followUpQuestions': ['어디였어요?', '누구와 함께였어요?', '어떤 기분이셨어요?'],
        'evidenceSource': fromFact ? 'lifeFact' : 'profile',
        'evidence': [
          if (fromFact)
            {'factId': fact['factId']! as String}
          else
            {'profileField': 'occupation'},
        ],
        'selected': false,
      });
    }
    return _CardSet(setId: setId, cards: cards, ready: ready);
  }

  // ── 5절, 6절 회차 ─────────────────────────────────

  _Reply _createSession(Map<String, Object?> body) {
    final latest = _latest;
    final setId = body['setId'];
    if (latest == null || latest.setId != setId) {
      return _error(404, 'CARD_SET_NOT_FOUND');
    }
    if (latest.stale) return _error(409, 'CARD_SET_NEEDS_REFRESH');
    if (_statusOf(latest) != 'ready') {
      return _error(409, 'CARD_SET_ALREADY_USED');
    }
    final selected = (body['selectedCardIds']! as List).cast<String>();
    final session = _Session(
      sessionId: _id('4', _next++),
      setId: latest.setId,
      selectedCardIds: [...selected],
      // 회차마다 날을 달리해 홈 알림의 날짜로 구분한다.
      startedAt: '2026-11-0${_sessions.length + 1}T14:00:00+09:00',
    );
    _sessions.add(session);
    return _ok(session.toJson(), 201);
  }

  /// 5-3 면회 중 보충 카드. 같은 묶음의 10~12번만 받고, 이미 더한 카드는
  /// 무시한다.
  _Reply _addCards(_Session session, Map<String, Object?> body) {
    if (session.status != 'evaluationPending') {
      return _error(409, 'INVALID_SESSION_STATE');
    }
    final ids = (body['cardIds'] as List?)?.cast<String>() ?? const [];
    final set = _sets.firstWhere((s) => s.setId == session.setId);
    final supplements = {
      for (final card in set.cards)
        if ((card['position']! as int) >= 10) card['cardId']! as String,
    };
    if (ids.isEmpty ||
        ids.length > 3 ||
        ids.toSet().length != ids.length ||
        !ids.every(supplements.contains)) {
      return _error(422, 'INVALID_CARD_SELECTION');
    }
    for (final id in ids) {
      if (!session.selectedCardIds.contains(id)) {
        session.selectedCardIds.add(id);
      }
    }
    return _ok(session.toJson());
  }

  _Reply _saveEvaluation(_Session session, Map<String, Object?> body) {
    if (session.evaluation != null) {
      return _error(409, 'EVALUATION_ALREADY_SUBMITTED');
    }
    session.evaluation = {
      'schemaVersion': 1,
      'sessionId': session.sessionId,
      'conversationSatisfaction': body['conversationSatisfaction'],
      'careRecipientReaction': body['careRecipientReaction'],
      'cardReviews': body['cardReviews'],
      'freeNote': body['freeNote'],
      'evaluatedAt': session.startedAt.replaceFirst('14:00', '15:00'),
    };
    session.status = 'audioPending';
    return _ok(session.evaluation!, 201);
  }

  _Reply _acceptAudio(_Session session, Map<String, Object?> fields) {
    if (session.evaluation == null) return _error(409, 'EVALUATION_REQUIRED');
    if (fields['audio'] != true) return _error(422, 'INVALID_REQUEST');
    final count = int.tryParse('${fields['participantCount']}');
    if (count == null || count < 1 || count > 8) {
      return _error(422, 'INVALID_REQUEST');
    }
    session.participantCount = count;
    final plan = _plans.isEmpty ? AnalysisPlan.success : _plans.removeAt(0);
    return _startAnalysis(session, plan);
  }

  _Reply _startAnalysis(_Session session, AnalysisPlan plan) {
    final analysis = _Analysis(
      analysisId: _id('5', _next++),
      session: session,
      plan: plan,
    );
    _analyses[analysis.analysisId] = analysis;
    session
      ..analysisId = analysis.analysisId
      ..status = 'processing';
    return _ok({
      'schemaVersion': 1,
      'analysisId': analysis.analysisId,
      'sessionId': session.sessionId,
      'status': 'queued',
    }, 202);
  }

  /// 물을 때마다 한 단계씩 나아간다. STT 와 리포트 생성을 대신한다.
  _Reply _advance(_Analysis analysis) {
    if (!holdAnalyses && analysis.steps.length > 1) analysis.steps.removeAt(0);
    final status = analysis.steps.first;
    final session = analysis.session;
    if (status == 'completed' && session.report == null) {
      _writeReport(session, analysis.plan);
      session.status = 'completed';
    } else if (status == 'failed') {
      session.status = 'failed';
    }
    return _ok({
      'schemaVersion': 1,
      'analysisId': analysis.analysisId,
      'sessionId': session.sessionId,
      'status': status,
      'errorCode': status == 'failed' ? 'REPORT_GENERATION_FAILED' : null,
    });
  }

  _Reply _retry(_Analysis analysis) {
    if (analysis.steps.first != 'failed') {
      return _error(409, 'ANALYSIS_ALREADY_COMPLETED');
    }
    // BE 처럼 새 분석 ID 로 202 를 돌려준다(`speech_analyses.py`).
    return _startAnalysis(analysis.session, AnalysisPlan.success);
  }

  void _writeReport(_Session session, AnalysisPlan plan) {
    final insufficientLabels = plan == AnalysisPlan.insufficientSpeakerLabels;
    final evaluation = session.evaluation!;
    final reviews = (evaluation['cardReviews']! as List)
        .cast<Map<String, Object?>>();
    final usedCards = [
      for (final review in reviews)
        if (review['wasUsed'] == true) review['cardId']! as String,
    ];
    final set = _sets.firstWhere((x) => x.setId == session.setId);
    String titleOf(String cardId) =>
        set.cards.firstWhere((c) => c['cardId'] == cardId)['cardTitle']!
            as String;
    final satisfaction = evaluation['conversationSatisfaction']! as int;

    session.report = {
      'schemaVersion': 1,
      'sessionId': session.sessionId,
      'title': journeyReportTitle,
      'body': journeyReportBody,
      'visitDate': session.startedAt.substring(0, 10),
      // BE 는 보호자 만족도로 기분을 정한다.
      'mood': satisfaction <= 2
          ? 'hard'
          : satisfaction == 3
          ? 'normal'
          : 'good',
      'photo': null,
      'cardSummaries': [
        for (final cardId in usedCards)
          {
            'cardId': cardId,
            'cardTitle': titleOf(cardId),
            'summary': journeyCardSummary,
          },
      ],
      'generatedAt': session.startedAt.replaceFirst('14:00', '16:00'),
    };
    session.proposal = {
      'schemaVersion': 1,
      'sessionId': session.sessionId,
      'lifeFactProposals': <Map<String, Object?>>[
        {
          'proposalId': _id('6', _next++),
          'title': journeyProposalTitle,
          'content': journeyProposalContent,
          'reason': insufficientLabels
              ? journeyUncertainProposalReason
              : '이번 면회에서 말씀하셨어요.',
          'reviewStatus': 'pending',
        },
      ],
      'topicProposals': <Object>[],
    };
  }

  // ── 7-4 변경 제안 검토 ───────────────────────────────

  _Reply _review(_Session session, Map<String, Object?> body) {
    final proposal = session.proposal;
    if (proposal == null) return _error(404, 'REPORT_NOT_FOUND');
    final facts = (proposal['lifeFactProposals']! as List)
        .cast<Map<String, Object?>>();
    final reviews = (body['lifeFacts']! as List).cast<Map<String, Object?>>();
    for (final review in reviews) {
      final index = facts.indexWhere(
        (f) => f['proposalId'] == review['proposalId'],
      );
      if (index < 0) return _error(422, 'INVALID_REQUEST');
      if (facts[index]['reviewStatus'] != 'pending') {
        return _error(409, 'PROPOSAL_ALREADY_REVIEWED');
      }
      final accepted = review['reviewStatus'] == 'accepted';
      // 제안 값은 AI 가 만든 원래 값 그대로 두고 상태만 바꾼다(7-3 응답 규칙).
      facts[index] = {...facts[index], 'reviewStatus': review['reviewStatus']};
      if (accepted) {
        // 7-4 는 분류와 그림을 보내지 않아 BE 는 `other` 와 임의 그림을 쓴다.
        lifeFacts.add({
          'schemaVersion': 1,
          'factId': _id('7', _next++),
          'profileId': profileId,
          'storyCategory': 'other',
          'title': review['title'],
          'content': review['content'],
          'imageNumber': 1,
          'createdAt': session.startedAt.replaceFirst('14:00', '17:00'),
        });
      }
    }
    return _ok(proposal);
  }

  // ── 그 밖 ─────────────────────────────────────

  Map<String, Object?> _account() => {
    'schemaVersion': 1,
    'accountId': accountId,
    'authProvider': 'google',
    'displayName': '테스트 보호자',
    'email': null,
    'consent': {
      'consentVersion': '2026-10-01',
      'serviceData': {
        'granted': true,
        'grantedAt': '2026-10-13T09:00:00+09:00',
      },
      'sensitiveData': {
        'granted': true,
        'grantedAt': '2026-10-13T09:00:00+09:00',
      },
      'serviceImprovement': {'granted': false, 'grantedAt': null},
      'pushNotification': {'granted': false, 'grantedAt': null},
    },
    'createdAt': '2026-10-13T09:00:00+09:00',
  };

  /// multipart 본문에서 글자 필드와 파일 필드가 있었는지만 읽는다.
  static Map<String, Object?> _multipartFields(String raw) {
    final fields = <String, Object?>{};
    final pattern = RegExp(
      r'name="([^"]+)"(; filename="[^"]*")?[^\r\n]*\r\n(?:[^\r\n]+\r\n)*\r\n',
    );
    for (final match in pattern.allMatches(raw)) {
      final name = match.group(1)!;
      if (match.group(2) != null) {
        fields[name] = true;
        continue;
      }
      final start = match.end;
      final end = raw.indexOf('\r\n', start);
      fields[name] = raw.substring(start, end < 0 ? raw.length : end);
    }
    return fields;
  }

  static String _id(String kind, int n) =>
      '${kind * 8}-0000-4000-8000-${n.toString().padLeft(12, '0')}';

  static _Reply _ok(Map<String, Object?> body, [int status = 200]) =>
      _Reply(status, body);

  static _Reply _notFound() => _error(404, 'NOT_FOUND');

  static _Reply _error(int status, String errorCode) => _Reply(status, {
    'schemaVersion': 1,
    'errorCode': errorCode,
    'message': '테스트용 오류',
    'requestId': 'req_journey',
    'retryable': false,
  });
}

class _Reply {
  const _Reply(this.status, this.body);

  final int status;
  final Map<String, Object?>? body;
}

class _CardSet {
  _CardSet({required this.setId, required this.cards, required this.ready});

  final String setId;
  final List<Map<String, Object?>> cards;

  /// 다 만들었는지. 만드는 중이면 4-2 가 `running` 이다.
  bool ready;

  /// 받은 뒤 프로필이나 일대기를 고쳤는지(BE 의 `stale_at`).
  bool stale = false;
}

class _Session {
  _Session({
    required this.sessionId,
    required this.setId,
    required this.selectedCardIds,
    required this.startedAt,
  });

  final String sessionId;
  final String setId;
  final List<String> selectedCardIds;
  final String startedAt;
  String status = 'evaluationPending';
  int? participantCount;
  String? analysisId;
  Map<String, Object?>? evaluation;
  Map<String, Object?>? report;
  Map<String, Object?>? proposal;

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'sessionId': sessionId,
    'profileId': JourneyServer.profileId,
    'setId': setId,
    'selectedCardIds': selectedCardIds,
    'sessionStatus': status,
    'photoId': null,
    'participantCount': participantCount,
    'startedAt': startedAt,
    'analysisId': analysisId,
  };
}

class _Analysis {
  _Analysis({
    required this.analysisId,
    required this.session,
    required this.plan,
  }) : steps = [
         'queued',
         'transcribing',
         'generatingReport',
         plan == AnalysisPlan.failed ? 'failed' : 'completed',
       ];

  final String analysisId;
  final _Session session;
  final AnalysisPlan plan;

  /// 앞으로 물을 때 차례로 돌려줄 상태. 맨 앞이 지금 상태다.
  final List<String> steps;
}
