import 'routes.dart';

/// 리포트 완료 알림을 눌렀을 때 지금 화면 위에 그 리포트를 바로 열어도 되는지.
///
/// 보기만 하는 화면(홈, 제출 완료, 리포트와 일대기 보기, 설정 등)에서는 바로 연다.
/// 로그인, 동의, 등록, 면회 진행과 평가, 글을 고치는 화면에서는 하던 일을 끊지
/// 않도록 기다렸다가 그런 화면을 떠나 이 목록의 화면에 오면 연다.
///
/// 2026-11-07 Galaxy S22에서 평가를 제출한 뒤 "제출 완료" 화면에 둔 채 알림을
/// 누르면 리포트가 열리지 않고 "홈으로"를 눌러야 열렸다. 그때는 홈에서만 열었다.
bool canOpenReportOver(String path) {
  const viewOnly = {
    AppRoutes.home,
    AppRoutes.visitReviewDone,
    AppRoutes.reports,
    AppRoutes.notifications,
    AppRoutes.settings,
    AppRoutes.profile,
    AppRoutes.profileSwitch,
    AppRoutes.album,
    AppRoutes.albumBook,
  };
  if (viewOnly.contains(path)) return true;
  // 다른 리포트를 보는 중이면 연다. 변경 사항을 고르는 화면과 이야기 수정은 기다린다.
  if (path.startsWith('/report/')) return !path.contains('/changes');
  // 일대기 분류와 이야기 보기. 새 이야기와 고치기(/album/new, /album/edit/)는 기다린다.
  if (path.startsWith('/album/category/')) return true;
  return false;
}
