// 합성 녹음 기록과 API 대역으로 확인한다. 실제 마이크와 Android 종료 시험은 아니다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/features/review/upload_retry_screen.dart';
import 'package:saerok/features/visit/pending_uploads.dart';

import 'fake_card_api.dart';
import 'fake_pending_uploads.dart';
import 'fake_visit_api.dart';
import 'sample_profile.dart';

void main() {
  for (final size in [const Size(412, 917), const Size(360, 800)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('녹음 복원 확인과 취소 $size 글자 $scale', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = FakeVisitApi();
        final files = FakePendingUploads()
          ..saved[FakeVisitApi.sessionId] = const PendingUpload(
            sessionId: FakeVisitApi.sessionId,
            audioPath: '/synthetic/preserved.wav',
            participantCount: null,
          );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              withSampleProfile,
              ...mockCardsWith(visitApi: api, pendingUploads: files),
            ],
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const UploadRetryScreen(sessionId: FakeVisitApi.sessionId),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('녹음이 기기에 남아 있어요'), findsOneWidget);
        expect(api.calls, isEmpty);
        await tester.tap(find.text('참여자 수 확인하기'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('나중에 보내기'));
        await tester.tap(find.text('나중에 보내기'));
        await tester.pumpAndSettle();
        expect(api.calls, isEmpty);
        expect(files.saved, contains(FakeVisitApi.sessionId));
        await tester.tap(find.text('참여자 수 확인하기'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('participantPlus')));
        await tester.ensureVisible(find.text('확인하고 보내기'));
        await tester.tap(find.text('확인하고 보내기'));
        await tester.pumpAndSettle();
        expect(api.audio?.audioPath, '/synthetic/preserved.wav');
        expect(api.audio?.participantCount, 3);
        expect(find.text('녹음을 보냈어요'), findsOneWidget);
        expect(files.removedPaths, isEmpty);
        expect(tester.takeException(), isNull);
        // 기존 목 리포트 알림이 예약한 타이머도 끝낸다.
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();
      });
    }
  }
}
