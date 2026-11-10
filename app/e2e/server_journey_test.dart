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

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:saerok/data/account_api.dart';
import 'package:saerok/data/api_client.dart';
import 'package:saerok/data/auth_api.dart';
import 'package:saerok/data/card_api.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/profile_api.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/data/push_device_api.dart';
import 'package:saerok/data/report_api.dart';
import 'package:saerok/data/visit_api.dart';

final _baseUrl = Platform.environment['SAEROK_E2E_BASE_URL'];
final _idToken = Platform.environment['SAEROK_E2E_ID_TOKEN'];

/// 스크립트가 실제 모델 모드로 띄웠는지. 실제 모델이 쓴 글은 미리 알 수 없어 구조만 본다.
final _realModels = Platform.environment['SAEROK_E2E_MODELS'] == 'real';

/// 실제 STT 모드에서 올릴 합성 음성 파일. 없으면 0.1초 무음 WAV 를 만든다.
final _audioFile = Platform.environment['SAEROK_E2E_AUDIO_FILE'];

/// 카드 생성과 음성 분석을 기다리는 시간. 실제 모델은 한 번에 1~2분씩 걸린다.
final _wait = _realModels
    ? const Duration(minutes: 10)
    : const Duration(seconds: 60);

/// 이야기 제안을 고쳐 승인할 때 쓰는 제목. 스크립트가 다음 카드 생성 요청에서 이 제목을 찾는다.
const _approvedTitle = 'E2E 고쳐서 승인한 이야기';

/// 합성 카드 생성 함수는 이 제목의 이야기가 있으면 실패한다(스크립트의 `FAIL_CARDS_TITLE`).
const _failCardsTitle = 'E2E 생성 실패 유도';

/// 카드를 합성 함수로 만드는지. 실패 유도는 합성 함수에서만 한다.
final _syntheticCards = Platform.environment['SAEROK_E2E_CARD_MODEL'] != 'real';

/// 스크립트가 첫 리포트 생성을 일부러 실패시켰는지(6-5 가 있는 서버에서만).
final _expectReportRetry =
    Platform.environment['SAEROK_E2E_EXPECT_REPORT_RETRY'] == '1';

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

      // 1-6, 1-7, 1-8: 알림 수신에 동의해야 푸시 받을 기기를 등록할 수 있고, 동의를 거두면
      // 서버가 그 계정의 등록을 지운다. 실제 FCM 발송은 하지 않고 서버 API 까지만 본다.
      final accounts = AccountApi(api);
      final pushDevices = PushDeviceApi(api);
      const fid = 'e2e-synthetic-fid-0001';
      Matcher refusedForConsent() => throwsA(
        isA<ApiServerFailure>()
            .having((f) => f.statusCode, 'statusCode', 403)
            .having(
              (f) => f.errorCode,
              'errorCode',
              'PUSH_NOTIFICATION_CONSENT_REQUIRED',
            ),
      );
      await expectLater(pushDevices.register(fid), refusedForConsent());
      final pushOn = await accounts.updateConsents({'pushNotification': true});
      expect(pushOn.consent['pushNotification']!.granted, isTrue);
      await pushDevices.register(fid);
      await pushDevices.register(fid); // 같은 기기를 다시 등록해도 된다.
      final pushOff = await accounts.updateConsents({'pushNotification': false});
      expect(pushOff.consent['pushNotification']!.granted, isFalse);
      await expectLater(pushDevices.register(fid), refusedForConsent());
      await pushDevices.unregister(fid); // 동의나 등록이 없어도 204 다.

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

      // 3-1, 3-2: 프로필 사진. 분석 worker 는 이 E2E 에 없어 대기 상태로 남는다.
      final png = await _syntheticPng();
      addTearDown(() => png.parent.delete(recursive: true));
      final profilePhoto = await profiles.uploadPhoto(profileId, png.path);
      expect(
        (await profiles.photo(profilePhoto.photoId)).photoId,
        profilePhoto.photoId,
      );
      expect(
        (await profiles.get(profileId)).photos.map((p) => p.photoId),
        contains(profilePhoto.photoId),
      );

      // 카드 생성이 실패하면 4-2 가 failed 를 주고, 원인을 지우면(2-9) 다시 요청할 수 있다.
      if (_syntheticCards) {
        final trigger = await profiles.createLifeFact(
          profileId,
          storyCategory: 'other',
          title: _failCardsTitle,
          content: '합성 실패 유도용 이야기',
          imageNumber: 1,
        );
        expect(
          await cards.requestGeneration(profileId),
          CardGenerationStatus.running,
        );
        expect(
          await _waitForCards(cards, profileId),
          CardGenerationStatus.failed,
        );
        await profiles.deleteLifeFact(trigger.factId);
        expect((await profiles.get(profileId)).lifeFacts.map((f) => f.factId), [
          fact.factId,
        ]);
      }

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
      final visitPhotoId = await visits.uploadPhoto(
        session.sessionId,
        photoPath: png.path,
      );
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
      var analysisStatus = await _waitForAnalysis(reports, analysisId);
      if (_expectReportRetry) {
        // 스크립트가 첫 리포트 생성을 일부러 실패시켰다. 남은 전사로 리포트만 다시 만든다.
        expect(analysisStatus, AnalysisStatus.failed);
        final retried = await api.post(
          '/api/v1/speech-analyses/$analysisId/retry',
        );
        final retriedId = retried['analysisId'] as String;
        expect(retriedId, isNot(analysisId));
        analysisStatus = await _waitForAnalysis(reports, retriedId);
      }
      expect(analysisStatus, AnalysisStatus.completed);
      expect(
        (await reports.latestSession(profileId))?.status,
        VisitStatus.completed,
      );

      // 7-1, 7-2: 리포트. 평가에서 쓴 카드의 요약만 들어 있다.
      final reportList = await reports.reports(profileId);
      expect(reportList, hasLength(1));
      final report = await reports.report(session.sessionId);
      expect(reportList.single.title, report.title);
      expect(report.photoId, visitPhotoId);
      expect(report.photoUrl, isNotNull);
      if (_realModels) {
        expect(report.title.trim(), isNotEmpty);
        expect(report.summaryText.trim(), isNotEmpty);
        expect(
          report.cardSummaries.map((c) => c.cardId).toSet().difference({
            picked.first,
          }),
          isEmpty,
          reason: '평가에서 쓴 카드만 요약한다',
        );
      } else {
        expect(report.title, 'E2E 합성 리포트');
        expect(report.cardSummaries.map((c) => c.cardId), [picked.first]);
      }

      // 7-3, 7-4: 첫 이야기 제안은 고쳐서 승인하고 나머지는 거절한다. 주제 제안은 제안대로 받는다.
      final proposal = await reports.proposals(session.sessionId);
      if (!_realModels) {
        expect(proposal.pendingLifeFacts, hasLength(1));
        expect(proposal.pendingTopics, hasLength(1));
      }
      final approved = proposal.pendingLifeFacts.isNotEmpty;
      if (!proposal.nothingPending) {
        await reports.reviewProposals(
          session.sessionId,
          ProposalReview(
            lifeFacts: [
              for (final (i, p) in proposal.pendingLifeFacts.indexed)
                i == 0
                    ? LifeFactReview.accepted(
                        proposalId: p.proposalId,
                        title: _approvedTitle,
                        content: '한복 고름을 몇 번이나 다시 다셨어요.',
                      )
                    : LifeFactReview.rejected(proposalId: p.proposalId),
            ],
            topics: [
              for (final p in proposal.pendingTopics)
                p.suggestedAction == null
                    ? TopicReview.rejected(proposalId: p.proposalId)
                    : TopicReview.accepted(
                        proposalId: p.proposalId,
                        action: p.suggestedAction!,
                      ),
            ],
          ),
        );
        expect(
          (await reports.proposals(session.sessionId)).nothingPending,
          isTrue,
        );
      }
      if (approved) {
        expect(
          (await profiles.get(profileId)).lifeFacts.map((f) => f.title),
          containsAll(['합성 수선집', _approvedTitle]),
        );
      }

      // 다음 대화 준비: 승인한 이야기가 다음 카드 생성 자료에 들어간다. 합성 생성 함수는 받은
      // 이야기마다 카드 제목에 그 제목을, 설명에 출처를 적는다. 실제 모델 모드에서는 스크립트가
      // 서버가 모델에 넘긴 요청에서 확인한다.
      final next = await _generate(cards, profileId);
      expect(next.cards, hasLength(12));
      if (!_realModels) {
        final approvedCard = next.cards.singleWhere(
          (c) => c.cardTitle == 'E2E 이야기 카드: $_approvedTitle',
        );
        expect(approvedCard.description, contains('이야기 출처: visit'));
      }
      // 두 번째 면회: 승인한 이야기가 들어간 새 묶음으로 회차를 만들고 두 번째 리포트까지 받는다.
      final secondSession = await visits.createSession(
        setId: next.setId,
        selectedCardIds: [next.cards.first.cardId],
      );
      await visits.submitEvaluation(
        secondSession.sessionId,
        EvaluationSubmission(
          conversationSatisfaction: 5,
          careRecipientReaction: CareRecipientReaction.calm,
          cardReviews: [
            CardReview(
              cardId: next.cards.first.cardId,
              wasUsed: true,
              caregiverReaction: CaregiverReaction.neutral,
            ),
          ],
        ),
      );
      final secondAnalysis = await visits.submitAudio(
        secondSession.sessionId,
        audioPath: audio.path,
        participantCount: 2,
      );
      expect(
        await _waitForAnalysis(reports, secondAnalysis),
        AnalysisStatus.completed,
      );
      expect(await reports.reports(profileId), hasLength(2));
      expect(
        (await reports.latestSession(profileId))?.sessionId,
        secondSession.sessionId,
      );

      _writeOutcome({
        'secondReport': true,
        'cardRetries': _cardRetries,
        'reportRetry': _expectReportRetry,
        'cardFailureRecovered': _syntheticCards,
        'approved': approved,
        'lifeFactProposals': proposal.lifeFactProposals.length,
        'topicProposals': proposal.topicProposals.length,
        'cardSummaries': report.cardSummaries.length,
        'nextCards': next.cards.length,
      });

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
    timeout: Timeout(
      _realModels ? const Duration(minutes: 40) : const Duration(minutes: 3),
    ),
  );
}

/// 스크립트가 넘긴 결과를 파일로 남긴다. 스크립트가 다음 카드 생성 요청과 맞춰 본다.
void _writeOutcome(Map<String, Object?> outcome) {
  final path = Platform.environment['SAEROK_E2E_REPORT_FILE'];
  if (path != null) File(path).writeAsStringSync(jsonEncode(outcome));
}

/// 올릴 녹음. 스크립트가 합성 음성 파일을 넘기면 그것을, 아니면 16kHz, 16비트 모노 0.1초 무음
/// WAV 를 임시 폴더에 쓴다. 무음은 BE 테스트의 `synthetic_wav()` 와 같다.
Future<File> _syntheticWav() async {
  final dir = await Directory.systemTemp.createTemp('saerok_e2e_');
  final audioFile = _audioFile;
  if (audioFile != null) {
    return File(audioFile).copy('${dir.path}/synthetic.wav');
  }
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
  final deadline = DateTime.now().add(_wait);
  while (DateTime.now().isBefore(deadline)) {
    final status = (await reports.analysis(analysisId)).status;
    if (status == AnalysisStatus.completed || status == AnalysisStatus.failed) {
      return status;
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  fail('음성 분석이 ${_wait.inSeconds}초 안에 끝나지 않았습니다');
}

/// 실제 모델 모드에서 카드 생성이 실패해 다시 요청한 횟수.
var _cardRetries = 0;

/// 4-1 로 요청하고 4-2 가 `ready` 가 될 때까지 기다린 뒤 4-3 으로 받는다.
///
/// 실제 모델은 외부 API 가 늦어 제한 시간에 걸릴 수 있다(`LLM_UNAVAILABLE`). 그때는 보호자가
/// 다시 누르는 것처럼 한 번만 더 요청하고 그 횟수를 결과에 남긴다. 합성 모드에서는 다시 요청하지 않는다.
Future<CardSet> _generate(ServerCardApi cards, String profileId) async {
  for (var attempt = 1; ; attempt++) {
    expect(
      await cards.requestGeneration(profileId),
      CardGenerationStatus.running,
    );
    final status = await _waitForCards(cards, profileId);
    if (status == CardGenerationStatus.ready) return cards.current(profileId);
    if (!_realModels || attempt >= 2) {
      fail('카드 생성이 $status 로 끝났다');
    }
    _cardRetries++;
  }
}

/// 4-2 가 `running` 에서 벗어날 때까지 기다린다.
Future<CardGenerationStatus> _waitForCards(
  ServerCardApi cards,
  String profileId,
) async {
  final deadline = DateTime.now().add(_wait);
  while (DateTime.now().isBefore(deadline)) {
    final status = await cards.status(profileId);
    if (status != CardGenerationStatus.running) return status;
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  fail('카드 생성이 ${_wait.inSeconds}초 안에 끝나지 않았습니다');
}

/// 1x1 PNG. 서버는 파일 앞부분의 시그니처로 형식을 본다.
Future<File> _syntheticPng() async {
  const bytes = <int>[
    0x89,
    0x50,
    0x4e,
    0x47,
    0x0d,
    0x0a,
    0x1a,
    0x0a,
    0x00,
    0x00,
    0x00,
    0x0d,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x1f,
    0x15,
    0xc4,
    0x89,
    0x00,
    0x00,
    0x00,
    0x0d,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9c,
    0x63,
    0xf8,
    0xcf,
    0xc0,
    0xf0,
    0x1f,
    0x00,
    0x05,
    0x00,
    0x01,
    0xff,
    0x89,
    0x99,
    0x3d,
    0x1d,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4e,
    0x44,
    0xae,
    0x42,
    0x60,
    0x82,
  ];
  final dir = await Directory.systemTemp.createTemp('saerok_e2e_png_');
  final file = File('${dir.path}/synthetic.png');
  await file.writeAsBytes(bytes);
  return file;
}
