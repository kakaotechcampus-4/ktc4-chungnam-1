// 앱의 실제 API 코드로 실제 BE 서버를 부른다.
//
//     cd backend && python scripts/run_app_server_e2e.py
//
// 위 스크립트가 빈 DB, BE, 카드 생성과 음성 분석 worker, 로컬 서명 키를 준비하고
// `SAEROK_E2E_BASE_URL`, `SAEROK_E2E_ID_TOKEN` 을 넘겨 이 파일을 실행한다.
// 두 값이 없으면 건너뛴다. `test/journey/` 의 여정은 가짜 서버를 쓰고, 이 파일은
// 화면 없이 HTTP 경계만 실제로 보낸다.
//
// 대신하는 것: 구글 로그인(스크립트의 서명 키), 카드 생성 모델(합성 카드 12장), 녹음 저장소(S3
// 대신 메모리), STT(화자 둘의 합성 전사), 리포트 모델(합성 리포트와 제안). 사진은 넣지 않았다.
// 녹음은 0.1초 무음 WAV 다. 값은 모두 합성이다.

@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:saerok/data/api_client.dart';
import 'package:saerok/data/auth_api.dart';
import 'package:saerok/data/card_api.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/profile_api.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/data/report_api.dart';
import 'package:saerok/data/visit_api.dart';

final _baseUrl = Platform.environment['SAEROK_E2E_BASE_URL'];
final _idToken = Platform.environment['SAEROK_E2E_ID_TOKEN'];

void main() {
  final skip = _baseUrl == null || _idToken == null
      ? 'SAEROK_E2E_BASE_URL, SAEROK_E2E_ID_TOKEN 이 없습니다. '
            'backend/scripts/run_app_server_e2e.py 로 실행합니다.'
      : null;

  test(
    '가입부터 사실 정정, 카드 재생성, 면회 평가, 로그아웃과 탈퇴까지',
    () async {
      final http.Client httpClient = http.Client();
      addTearDown(httpClient.close);
      final auth = AuthApi(baseUrl: _baseUrl!, client: httpClient);
      String? authorization;
      final api = ApiClient(
        authorization: () => authorization,
        baseUrl: _baseUrl!,
        client: httpClient,
      );
      final profiles = ProfileApi(api);
      final cards = ServerCardApi(api);
      final visits = ServerVisitApi(api);
      final reports = ReportApi(api);

      // 1-1, 1-2, 1-3: 첫 로그인은 동의를 요구하고, 동의를 내면 계정과 세션이 생긴다.
      final first = await auth.signInWithGoogle(_idToken!);
      expect(first, isA<ConsentRequiredResult>());
      final consentRequired = first as ConsentRequiredResult;
      final signedIn = await auth.submitConsent(
        registrationToken: consentRequired.registrationToken,
        consentVersion: consentRequired.consentVersion,
        consents: {
          for (final key in consentRequired.requiredConsents) key: true,
          for (final key in consentRequired.optionalConsents) key: false,
        },
        displayName: 'E2E 합성 보호자',
      );
      authorization = '${signedIn.tokenType} ${signedIn.accessToken}';
      final me = await auth.me(authorization);
      expect(me.accountId, signedIn.account.accountId);
      expect(me.displayName, 'E2E 합성 보호자');

      // 2-2, 2-4, 2-6, 2-1, 2-3: 프로필과 세부 정보, 이야기 한 개.
      final created = await profiles.create(
        const EnteredBasicInfo(
          name: 'E2E 합성 어르신',
          gender: 'female',
          birthDate: '1943-03-12',
          stage: ConditionStage.unknown,
        ),
      );
      final profileId = created.profileId;
      await profiles.updateDetails(
        profileId,
        const EnteredDetails(hobby: '합성 정원 가꾸기'),
      );
      final fact = await profiles.createLifeFact(
        profileId,
        storyCategory: 'work',
        title: '합성 수선집',
        content: '합성 수선집에 단골손님이 많았어요.',
        imageNumber: 3,
      );
      expect(
        (await profiles.list()).map((p) => p.profileId),
        contains(profileId),
      );
      final loaded = await profiles.get(profileId);
      expect(loaded.details.hobby, '합성 정원 가꾸기');
      expect(loaded.lifeFacts.map((f) => f.factId), [fact.factId]);

      // 4-1, 4-2, 4-3: 카드 12장을 받는다.
      final firstSet = await _generate(cards, profileId);
      expect(firstSet.cards, hasLength(12));
      expect(firstSet.needsRefresh, isFalse);
      expect(
        await cards.requestGeneration(profileId),
        CardGenerationStatus.ready,
        reason: '쓰지 않은 묶음이 있으면 서버가 CARD_SET_READY 로 거절한다',
      );

      // 2-7 사실 정정: 받은 묶음은 볼 수만 있고 면회를 시작할 수 없다.
      await profiles.updateLifeFact(
        fact.factId,
        storyCategory: 'work',
        title: '합성 수선집',
        content: '합성 양복점에 단골손님이 많았어요.',
        imageNumber: 3,
      );
      expect(await cards.status(profileId), CardGenerationStatus.needsRefresh);
      expect((await cards.current(profileId)).needsRefresh, isTrue);
      await expectLater(
        visits.createSession(
          setId: firstSet.setId,
          selectedCardIds: [firstSet.cards.first.cardId],
        ),
        throwsA(
          isA<ApiServerFailure>()
              .having((f) => f.statusCode, 'statusCode', 409)
              .having(
                (f) => f.errorCode,
                'errorCode',
                'CARD_SET_NEEDS_REFRESH',
              ),
        ),
      );

      // 정정을 반영해 묶음 전체를 다시 만든다.
      final refreshed = await _generate(cards, profileId);
      expect(refreshed.setId, isNot(firstSet.setId));
      expect(refreshed.needsRefresh, isFalse);

      // 5-1, 5-3: 1~9번에서 세 장을 골라 시작하고, 면회 중 보충 카드 한 장을 더한다.
      final picked = refreshed.cards
          .where((c) => c.position <= 9)
          .take(3)
          .map((c) => c.cardId)
          .toList();
      final extra = refreshed.cards.firstWhere((c) => c.position == 10).cardId;
      final session = await visits.createSession(
        setId: refreshed.setId,
        selectedCardIds: picked,
      );
      expect(session.sessionStatus, SessionStatus.evaluationPending);
      expect(session.selectedCardIds, picked);
      final withExtra = await visits.addCards(session.sessionId, [extra]);
      expect(withExtra.selectedCardIds, [...picked, extra]);
      expect(
        await cards.requestGeneration(profileId),
        CardGenerationStatus.inVisit,
        reason: '평가 전 회차가 있으면 서버가 VISIT_IN_PROGRESS 로 거절한다',
      );

      // 6-1: 평가를 낸다. 같은 평가를 다시 내도 실패로 보지 않는다.
      final evaluation = EvaluationSubmission(
        conversationSatisfaction: 4,
        careRecipientReaction: CareRecipientReaction.pleased,
        cardReviews: [
          CardReview(
            cardId: picked.first,
            wasUsed: true,
            caregiverReaction: CaregiverReaction.positive,
          ),
          CardReview(cardId: picked[1], wasUsed: false),
        ],
        freeNote: 'E2E 합성 소감',
      );
      await visits.submitEvaluation(session.sessionId, evaluation);
      await visits.submitEvaluation(session.sessionId, evaluation);

      // 5-4: 가장 최근 회차는 녹음을 기다린다.
      final latest = await reports.latestSession(profileId);
      expect(latest?.sessionId, session.sessionId);
      expect(latest?.status, VisitStatus.audioPending);

      // 6-2, 6-3: 녹음을 올리고 분석이 끝나기를 기다린다.
      final audio = await _syntheticWav();
      addTearDown(() => audio.parent.delete(recursive: true));
      final analysisId = await visits.submitAudio(
        session.sessionId,
        audioPath: audio.path,
        participantCount: 2,
      );
      expect(
        await _waitForAnalysis(reports, analysisId),
        AnalysisStatus.completed,
      );
      expect(
        (await reports.latestSession(profileId))?.status,
        VisitStatus.completed,
      );

      // 7-1, 7-2: 리포트. 평가에서 쓴 카드의 요약만 들어 있다.
      expect((await reports.reports(profileId)).map((r) => r.title), [
        'E2E 합성 리포트',
      ]);
      final report = await reports.report(session.sessionId);
      expect(report.title, 'E2E 합성 리포트');
      expect(report.cardSummaries.map((c) => c.cardId), [picked.first]);

      // 7-3, 7-4: 이야기 제안을 고쳐서 승인하고 주제 제안도 받아들인다.
      final proposal = await reports.proposals(session.sessionId);
      expect(proposal.pendingLifeFacts, hasLength(1));
      expect(proposal.pendingTopics, hasLength(1));
      await reports.reviewProposals(
        session.sessionId,
        ProposalReview(
          lifeFacts: [
            LifeFactReview.accepted(
              proposalId: proposal.pendingLifeFacts.single.proposalId,
              title: 'E2E 고쳐서 승인한 이야기',
              content: '한복 고름을 몇 번이나 다시 다셨어요.',
            ),
          ],
          topics: [
            TopicReview.accepted(
              proposalId: proposal.pendingTopics.single.proposalId,
              action: TopicAction.more,
            ),
          ],
        ),
      );
      expect(
        (await reports.proposals(session.sessionId)).nothingPending,
        isTrue,
      );
      expect(
        (await profiles.get(profileId)).lifeFacts.map((f) => f.title),
        containsAll(['합성 수선집', 'E2E 고쳐서 승인한 이야기']),
      );

      // 다음 대화 준비: 승인한 이야기가 다음 카드 생성 자료에 들어간다. 합성 생성 함수는 받은
      // 이야기마다 카드 제목에 그 제목을, 설명에 출처를 적는다.
      final next = await _generate(cards, profileId);
      final approvedCard = next.cards.singleWhere(
        (c) => c.cardTitle == 'E2E 이야기 카드: E2E 고쳐서 승인한 이야기',
      );
      expect(approvedCard.description, contains('이야기 출처: visit'));

      // 1-4: 로그아웃한 세션은 다시 쓰이지 않는다.
      await auth.logout(authorization);
      await expectLater(
        auth.me(authorization),
        throwsA(
          isA<AuthServerFailure>().having(
            (f) => f.statusCode,
            'statusCode',
            401,
          ),
        ),
      );

      // 계정이 있으니 다시 로그인하면 바로 세션을 받는다. 1-5 탈퇴 뒤에는 다시 동의를 요구한다.
      final again = await auth.signInWithGoogle(_idToken!);
      expect(again, isA<AuthenticatedResult>());
      final second = again as AuthenticatedResult;
      expect(second.account.accountId, signedIn.account.accountId);
      authorization = '${second.tokenType} ${second.accessToken}';
      expect((await profiles.list()).map((p) => p.profileId), [profileId]);
      await auth.deleteAccount(authorization);
      expect(
        await auth.signInWithGoogle(_idToken!),
        isA<ConsentRequiredResult>(),
      );
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

/// 16kHz, 16비트 모노 0.1초 무음 WAV 를 임시 폴더에 쓴다. BE 테스트의 `synthetic_wav()` 와 같다.
Future<File> _syntheticWav() async {
  const samples = 1600;
  const dataBytes = samples * 2;
  final header = ByteData(44)
    ..setUint32(0, 0x52494646) // RIFF
    ..setUint32(4, 36 + dataBytes, Endian.little)
    ..setUint32(8, 0x57415645) // WAVE
    ..setUint32(12, 0x666d7420) // fmt
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, 16000, Endian.little)
    ..setUint32(28, 16000 * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint32(36, 0x64617461) // data
    ..setUint32(40, dataBytes, Endian.little);
  final dir = await Directory.systemTemp.createTemp('saerok_e2e_');
  final file = File('${dir.path}/synthetic.wav');
  await file.writeAsBytes([
    ...header.buffer.asUint8List(),
    ...List<int>.filled(dataBytes, 0),
  ]);
  return file;
}

/// 6-3 이 `completed` 나 `failed` 가 될 때까지 기다린다.
Future<AnalysisStatus?> _waitForAnalysis(
  ReportApi reports,
  String analysisId,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    final status = await reports.analysis(analysisId);
    if (status == AnalysisStatus.completed || status == AnalysisStatus.failed) {
      return status;
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  fail('음성 분석이 60초 안에 끝나지 않았습니다');
}

/// 4-1 로 요청하고 4-2 가 `ready` 가 될 때까지 기다린 뒤 4-3 으로 받는다.
Future<CardSet> _generate(ServerCardApi cards, String profileId) async {
  expect(
    await cards.requestGeneration(profileId),
    CardGenerationStatus.running,
  );
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    final status = await cards.status(profileId);
    if (status == CardGenerationStatus.ready) return cards.current(profileId);
    expect(status, CardGenerationStatus.running);
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  fail('카드 생성이 60초 안에 끝나지 않았습니다');
}
