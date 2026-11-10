// 리포트 완료 알림을 눌렀을 때 어느 화면에서 바로 열고 어느 화면에서 기다리는지 확인한다.
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/app/report_open_policy.dart';
import 'package:saerok/app/routes.dart';

void main() {
  test('보기만 하는 화면에서는 바로 연다', () {
    for (final path in [
      AppRoutes.home,
      AppRoutes.visitReviewDone,
      AppRoutes.reports,
      AppRoutes.notifications,
      AppRoutes.settings,
      AppRoutes.profile,
      AppRoutes.profileSwitch,
      AppRoutes.album,
      AppRoutes.albumBook,
      AppRoutes.reportOf('session-1'),
      AppRoutes.albumCategoryOf('family'),
      AppRoutes.albumStoryOf('family', 'story-1'),
    ]) {
      expect(canOpenReportOver(path), isTrue, reason: path);
    }
  });

  test('하던 일이 있는 화면에서는 기다린다', () {
    for (final path in [
      '/splash',
      AppRoutes.googleConsent,
      AppRoutes.onboarding,
      AppRoutes.settingsConsents,
      AppRoutes.profileCreate,
      AppRoutes.cards,
      AppRoutes.visitPhoto,
      AppRoutes.visitRecord,
      AppRoutes.visitAddCards,
      AppRoutes.visitReview,
      AppRoutes.visitUpload,
      AppRoutes.reportChangesOf('session-1'),
      AppRoutes.storyEditOf('session-1'),
      AppRoutes.profileEditBasic,
      AppRoutes.profileEditDetails,
      AppRoutes.profilePhotoAdd,
      AppRoutes.profileDelete,
      AppRoutes.albumStoryNew,
      AppRoutes.albumStoryEditOf('story-1'),
    ]) {
      expect(canOpenReportOver(path), isFalse, reason: path);
    }
  });
}
