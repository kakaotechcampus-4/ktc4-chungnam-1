// 서버는 대역이며 사진, 프로필, 응답은 모두 합성이다.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saerok/app/router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/data/api_client.dart';
import 'package:saerok/data/card_api.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/cards/card_generation_controller.dart';

import 'fake_card_api.dart';
import 'sample_profile.dart';

const _running = CardGenerationStatus.running;
const _ready = CardGenerationStatus.ready;
const _id = 'sample';

Map<String, dynamic> _photos({
  String state = 'choice',
  int completed = 3,
  String? reason = 'analysisFailed',
}) => {
  'setId': 'set-1',
  'state': state,
  'total': 5,
  'completed': completed,
  'failed': state == 'choice' ? 5 - completed : 0,
  'pending': state == 'choice' ? 0 : 5 - completed,
  'reason': reason,
};

CardGenerationSnapshot _snapshot({
  bool choice = true,
  int completed = 3,
  String? reason = 'analysisFailed',
}) => CardGenerationSnapshot(
  _running,
  CardPhotoPreparation.fromJson(
    _photos(
      state: choice ? 'choice' : 'waiting',
      completed: completed,
      reason: choice ? reason : null,
    ),
  ),
);

class PhotoApi extends FakeCardApi implements PhotoPreparationApi {
  PhotoApi(this.replies);
  final List<CardGenerationSnapshot> replies;
  Object? error;
  Object? resolveError;
  Completer<CardGenerationSnapshot>? pendingResolve;
  final actions = <String>[];
  @override
  Future<CardGenerationSnapshot> snapshot(String profileId) async {
    calls.add('snapshot');
    profileIds.add(profileId);
    if (error != null) throw error!;
    return replies.length > 1 ? replies.removeAt(0) : replies.single;
  }

  @override
  Future<CardGenerationSnapshot> resolvePhotos(
    String profileId,
    String setId,
    String action,
  ) async {
    actions.add('$profileId/$setId/$action');
    if (resolveError != null) throw resolveError!;
    return pendingResolve?.future ?? const CardGenerationSnapshot(_ready, null);
  }
}

ProviderContainer _container(PhotoApi api) => ProviderContainer(
  overrides: [
    withSampleProfile,
    cardApiProvider.overrideWithValue(api),
    cardPollIntervalProvider.overrideWithValue(Duration.zero),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final generation = cardGenerationProvider(_id);
  final preparation = cardPhotoPreparationProvider(_id);

  // 로컬 시각 검토 때만 시스템 한글 글꼴을 읽고 build/에 화면을 남긴다.
  // CI 회귀 시험은 기존 테스트 글꼴을 그대로 쓴다.
  const capture = bool.fromEnvironment('PHOTO_WAIT_CAPTURE');
  setUpAll(() async {
    if (capture) {
      final bytes = await File('C:/Windows/Fonts/malgun.ttf').readAsBytes();
      final loader = FontLoader('Roboto')
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
  });

  test('선택 상태는 계속 조회하거나 새 카드 작업을 만들지 않는다', () async {
    final api = PhotoApi([_snapshot()]);
    final c = _container(api);
    addTearDown(c.dispose);
    await c.read(generation.notifier).resume();
    expect(c.read(generation).value, _running);
    expect(c.read(preparation)!.completed, 3);
    expect(api.calls, ['snapshot']);
    expect(c.read(cardPhotoPreparationProvider('other')), isNull);
  });

  test('대기 중에는 진행률을 읽고 준비가 끝나면 대기를 지운다', () async {
    final api = PhotoApi([
      _snapshot(choice: false),
      _snapshot(choice: false, completed: 4),
      const CardGenerationSnapshot(_ready, null),
    ]);
    final c = _container(api);
    addTearDown(c.dispose);
    final counts = <int?>[];
    c.listen(preparation, (_, p) => counts.add(p?.completed));
    await c.read(generation.notifier).resume();
    expect(counts, [3, 4, null]);
    expect(c.read(generation).value, _ready);
    expect(api.calls, ['snapshot', 'snapshot', 'snapshot']);
  });

  test('앱 재실행에 해당하는 새 컨테이너에서도 같은 선택을 복원한다', () async {
    final api = PhotoApi([_snapshot()]);
    final first = _container(api);
    await first.read(generation.notifier).resume();
    first.dispose();
    final second = _container(api);
    addTearDown(second.dispose);
    await second.read(generation.notifier).resume();
    expect(second.read(preparation)!.setId, 'set-1');
    expect(api.calls, ['snapshot', 'snapshot']);
  });

  for (final status in [
    CardGenerationStatus.none,
    CardGenerationStatus.failed,
  ]) {
    test('홈 복원은 $status 작업을 자동 생성하지 않는다', () async {
      final api = PhotoApi([CardGenerationSnapshot(status, null)]);
      final c = _container(api);
      addTearDown(c.dispose);
      await c.read(generation.notifier).resume();
      expect(api.calls, ['snapshot']);
      expect(c.read(generation).value, status);
    });
  }

  for (final action in ['retry', 'continue']) {
    test('$action 중복 입력은 한 번만 전송한다', () async {
      final api = PhotoApi([_snapshot()])
        ..pendingResolve = Completer<CardGenerationSnapshot>();
      final c = _container(api);
      addTearDown(c.dispose);
      final controller = c.read(generation.notifier);
      await controller.resume();
      final first = controller.resolvePhotos(action);
      await controller.resolvePhotos(action);
      expect(api.actions, ['$_id/set-1/$action']);
      api.pendingResolve!.complete(const CardGenerationSnapshot(_ready, null));
      await first;
      expect(c.read(preparation), isNull);
      expect(c.read(generation).value, _ready);
    });
  }

  test('선택 전송 실패는 선택을 남기고 사용자가 다시 시도한다', () async {
    final api = PhotoApi([_snapshot()])
      ..resolveError = const ApiNetworkFailure();
    final c = _container(api);
    addTearDown(c.dispose);
    await c.read(generation.notifier).resume();
    await c.read(generation.notifier).resolvePhotos('retry');
    expect(c.read(generation).hasError, isTrue);
    expect(c.read(preparation)!.needsChoice, isTrue);
    expect(api.actions, hasLength(1));
    api.resolveError = null;
    await c.read(generation.notifier).resolvePhotos('retry');
    expect(c.read(generation).value, _ready);
  });

  test('상태 조회 연결 실패 후 재진입하면 같은 작업을 이어받는다', () async {
    final api = PhotoApi([_snapshot()])..error = const ApiNetworkFailure();
    final c = _container(api);
    addTearDown(c.dispose);
    await c.read(generation.notifier).resume();
    expect(c.read(generation).hasError, isTrue);
    api.error = null;
    await c.read(generation.notifier).resume();
    expect(c.read(preparation)!.needsChoice, isTrue);
    expect(api.calls, ['snapshot', 'snapshot']);
  });

  test('실제 HTTP 어댑터가 상태와 선택 본문을 처리한다', () async {
    final sent = <http.Request>[];
    final api = ServerCardApi(
      ApiClient(
        baseUrl: 'https://synthetic.invalid',
        authorization: () => 'Bearer synthetic',
        client: MockClient((request) async {
          sent.add(request);
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'schemaVersion': 1,
                'status': 'running',
                'photoPreparation': _photos(),
              }),
            ),
            200,
          );
        }),
      ),
    );
    expect((await api.snapshot(_id)).photos!.failed, 2);
    await api.resolvePhotos(_id, 'set-1', 'continue');
    expect(
      sent.last.url.path,
      '/api/v1/profiles/sample/card-generations/photo-preparation',
    );
    expect(jsonDecode(sent.last.body), {
      'setId': 'set-1',
      'action': 'continue',
    });
  });

  test('다른 기기에서 이미 선택했으면 새 상태를 읽는다', () async {
    final api = PhotoApi([_snapshot()]);
    final c = _container(api);
    addTearDown(c.dispose);
    await c.read(generation.notifier).resume();
    api.resolveError = const ApiServerFailure(
      statusCode: 409,
      errorCode: 'PHOTO_PREPARATION_CHANGED',
    );
    api.replies.replaceRange(0, 1, [
      const CardGenerationSnapshot(_ready, null),
    ]);
    await c.read(generation.notifier).resolvePhotos('continue');
    expect(c.read(generation).value, _ready);
    expect(c.read(preparation), isNull);
    expect(api.calls, ['snapshot', 'snapshot']);
  });

  for (final bad in [
    {..._photos(), 'state': 'unknown'},
    {..._photos(), 'total': -1},
    {..._photos(), 'pending': 9},
    {..._photos(), 'reason': 'unknown'},
    {..._photos(), 'setId': ''},
  ]) {
    test('잘못된 진행 상태를 정상으로 표시하지 않는다: $bad', () {
      expect(() => CardPhotoPreparation.fromJson(bad), throwsFormatException);
    });
  }

  for (final size in const [Size(360, 640), Size(412, 917)]) {
    for (final scale in [1.0, 2.0]) {
      for (final reason in ['analysisFailed', 'timedOut', 'consentRequired']) {
        testWidgets('홈 ${size.width} 글자 $scale $reason 선택과 화면 복원', (
          tester,
        ) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final api = PhotoApi([_snapshot(reason: reason)])
            ..pendingResolve = Completer<CardGenerationSnapshot>();
          final c = _container(api);
          addTearDown(c.dispose);
          final router = buildRouter()..go(AppRoutes.home);
          addTearDown(router.dispose);
          await tester.runAsync(() async {
            await tester.pumpWidget(
              UncontrolledProviderScope(
                container: c,
                child: MaterialApp.router(
                  theme: buildAppTheme(),
                  routerConfig: router,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                ),
              ),
            );
            await c.read(serverProfileIdProvider.future);
          });
          await tester.pump();
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(find.text('사진 분석 다시 시도'), findsOneWidget);
          if (capture && reason == 'consentRequired') {
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile(
                Uri.file(
                  '${Directory.current.path}/build/photo-wait-${size.width.toInt()}-$scale.png',
                ),
              ),
            );
          }
          final proceed = find.text('완료된 사진으로 카드 만들기');
          await tester.ensureVisible(proceed);
          await tester.tap(proceed);
          await tester.pump();
          expect(api.actions.single, endsWith('/set-1/continue'));
          final buttons = tester.widgetList<OutlinedButton>(
            find.byType(OutlinedButton),
          );
          expect(buttons.every((b) => b.onPressed == null), isTrue);
          api.pendingResolve!.complete(
            const CardGenerationSnapshot(_ready, null),
          );
          await tester.pump();
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
}
