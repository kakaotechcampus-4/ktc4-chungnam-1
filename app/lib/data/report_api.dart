/// 회차 상태, 분석 상태와 리포트 API(`docs/architecture/api-spec.md` 5-4, 6-3,
/// 6-4, 7-1 ~ 7-4)를 부른다.
///
/// 요청은 [ApiClient] 가 보내고, 이 파일은 경로, 본문과 응답 모양만 맡는다.
/// 회차를 만들고(5-1) 평가와 음성을 보내는 일(6-1, 6-2)은 면회 흐름이 맡는다.
///
/// 앱의 [VisitSession] 과 [CaregiverEvaluation] 은 예전 목 계약의 모양이라
/// 면회 흐름이 함께 쓴다. 여기서는 바꾸지 않고, 필요한 값만 따로 읽는다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'models.dart';

/// 서버가 계산한 회차 상태(명세 5절 표). 앱의 [SessionStatus] 와 다른 값이다.
enum VisitStatus {
  /// 보호자 평가 전.
  evaluationPending,

  /// 평가 뒤 음성 접수 전.
  audioPending,

  /// 음성 분석과 리포트 생성 중.
  processing,

  /// 리포트를 저장했다.
  completed,

  /// 접수한 음성 분석이 실패했다.
  failed;

  static VisitStatus? parse(String raw) =>
      values.where((v) => v.name == raw).firstOrNull;
}

/// 5-4 목록의 회차 하나. 홈 표시에 쓰는 값만 읽는다.
class VisitProgress {
  const VisitProgress({
    required this.sessionId,
    required this.status,
    required this.startedAt,
    this.analysisId,
  });

  factory VisitProgress.fromJson(Map<String, dynamic> json) => VisitProgress(
    sessionId: json['sessionId'] as String,
    status: VisitStatus.parse(json['sessionStatus'] as String),
    startedAt: json['startedAt'] as String,
    analysisId: json['analysisId'] as String?,
  );

  final String sessionId;

  /// 모르는 값이면 `null` 이다.
  final VisitStatus? status;

  final String startedAt;

  /// 음성을 접수한 뒤에 생긴다. 가장 최근 분석 작업이다.
  final String? analysisId;

  /// 면회한 날. 리포트의 `visitDate` 와 같이 `startedAt` 의 한국 시간 날짜다.
  String get visitDate {
    final kst = DateTime.parse(startedAt).toUtc().add(const Duration(hours: 9));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${kst.year}-${two(kst.month)}-${two(kst.day)}';
  }
}

/// 음성 분석 작업의 상태(6-3).
enum AnalysisStatus {
  queued,
  transcribing,
  sttCompleted,
  generatingReport,
  completed,
  failed;

  static AnalysisStatus? parse(String raw) =>
      values.where((v) => v.name == raw).firstOrNull;
}

/// 리포트 기록의 한 줄(7-1).
class ReportListItem {
  const ReportListItem({
    required this.reportId,
    required this.title,
    required this.visitDate,
    required this.mood,
  });

  factory ReportListItem.fromJson(Map<String, dynamic> json) => ReportListItem(
    reportId: json['sessionId'] as String,
    title: json['title'] as String,
    visitDate: json['visitDate'] as String,
    mood: VisitMood.parse(json['mood'] as String),
  );

  /// 리포트를 여는 ID. 서버의 리포트는 회차 ID 로 연다(7-2).
  final String reportId;
  final String title;
  final String visitDate;
  final VisitMood? mood;
}

/// 회차 상태와 리포트 API 를 부른다. 실패는 [ApiFailure] 로 던진다.
class ReportApi {
  const ReportApi(this._client);

  final ApiClient _client;

  static const _base = '/api/v1';

  /// 5-4 가장 최근 회차. 회차가 없으면 `null` 이다.
  Future<VisitProgress?> latestSession(String profileId) async {
    final body = await _client.get(
      '$_base/profiles/$profileId/visit-sessions',
      query: {'limit': '1'},
    );
    return _read(() {
      final sessions = body['sessions'] as List;
      if (sessions.isEmpty) return null;
      return VisitProgress.fromJson(sessions.first as Map<String, dynamic>);
    });
  }

  /// 6-3 음성 분석 작업의 상태. 모르는 값이면 `null` 이다.
  Future<AnalysisStatus?> analysis(String analysisId) async {
    final body = await _client.get('$_base/speech-analyses/$analysisId');
    return _read(() => AnalysisStatus.parse(body['status'] as String));
  }

  /// 7-1 리포트가 저장된 회차. 최근 면회부터다.
  Future<List<ReportListItem>> reports(String profileId) async {
    final body = await _client.get('$_base/profiles/$profileId/reports');
    return _read(
      () => [
        for (final item in body['reports'] as List)
          ReportListItem.fromJson(item as Map<String, dynamic>),
      ],
    );
  }

  /// 7-2 회차의 리포트.
  ///
  /// 서버의 `body` 와 `cardSummaries[].cardTitle` 을 화면이 쓰는 이름으로
  /// 옮긴다. 리포트가 있으면 저장된 것이므로 상태는 `ready` 로 둔다.
  Future<VisitReport> report(String sessionId) async {
    final body = await _client.get('$_base/visit-sessions/$sessionId/report');
    return _read(() {
      final photo = body['photo'] as Map<String, dynamic>?;
      return VisitReport(
        reportId: body['sessionId'] as String,
        sessionId: body['sessionId'] as String,
        reportStatus: ReportStatus.ready,
        title: body['title'] as String,
        visitDate: body['visitDate'] as String,
        mood: VisitMood.parse(body['mood'] as String),
        photoId: photo?['photoId'] as String?,
        photoUrl: photo?['imageUrl'] as String?,
        summaryText: body['body'] as String,
        cardSummaries: [
          for (final item in body['cardSummaries'] as List)
            CardSummary(
              cardId: (item as Map<String, dynamic>)['cardId'] as String,
              topicTitle: item['cardTitle'] as String,
              summary: item['summary'] as String,
            ),
        ],
      );
    });
  }

  /// 6-4 보호자가 카드마다 남긴 답. 답하지 않은 카드는 들어 있지 않다.
  Future<List<CardReview>> cardReviews(String sessionId) async {
    final body = await _client.get(
      '$_base/visit-sessions/$sessionId/evaluation',
    );
    return _read(
      () => [
        for (final item in body['cardReviews'] as List)
          CardReview.fromJson(item as Map<String, dynamic>),
      ],
    );
  }

  /// 7-3 회차의 변경 제안.
  Future<ChangeProposal> proposals(String sessionId) async {
    final body = await _client.get(
      '$_base/visit-sessions/$sessionId/proposals',
    );
    return _read(() => ChangeProposal.fromJson(body));
  }

  /// 7-4 변경 제안 검토를 보낸다.
  Future<void> reviewProposals(String sessionId, ProposalReview review) async {
    final body = await _client.post(
      '$_base/visit-sessions/$sessionId/proposals/review',
      review.toJson(),
    );
    _read(() => ChangeProposal.fromJson(body));
  }

  /// 성공 응답이 계약과 다르면 성공으로 넘기지 않는다.
  static T _read<T>(T Function() parse) {
    try {
      return parse();
    } on TypeError catch (error) {
      throw ApiUnexpectedResponseFailure('리포트 응답 모양이 다르다: $error');
    } on FormatException catch (error) {
      throw ApiUnexpectedResponseFailure(error.message);
    }
  }
}

/// 리포트와 변경 제안 처리 실패를 보호자에게 보여줄 문구로 옮긴다.
///
/// 서버의 `errorCode` 는 명세 7절의 값만 구분한다. 모르는 실패는 다시 시도하게
/// 안내하고 원인을 지어내지 않는다.
String reportFailureMessage(ApiFailure failure) => switch (failure) {
  ApiServerFailure(errorCode: 'PROPOSAL_ALREADY_REVIEWED') =>
    '이미 확인을 마친 변경 사항이에요.',
  ApiServerFailure(statusCode: 401) ||
  ApiSignedOutFailure() => '로그인이 풀렸어요. 다시 로그인해주세요.',
  ApiNetworkFailure() => '서버에 연결하지 못했어요. 인터넷 연결을 확인하고 다시 시도해주세요.',
  ApiUnexpectedResponseFailure() => '서버 응답을 읽지 못했어요. 잠시 뒤 다시 시도해주세요.',
  ApiServerFailure() => '처리하지 못했어요. 잠시 뒤 다시 시도해주세요.',
};

final reportApiProvider = Provider<ReportApi>(
  (ref) => ReportApi(ref.watch(apiClientProvider)),
);
