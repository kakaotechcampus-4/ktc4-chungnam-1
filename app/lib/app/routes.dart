/// 화면 경로를 한곳에 모은다. 화면 이동은 문자열을 직접 적지 않고 여기를 쓴다.
///
/// 사용자 흐름은 `app/README.md` 의 "현재 사용자 흐름" 과 피그마 스토리맵
/// A~H 를 따른다. `H` 일대기와 `리포트 기록` 은 기획 보류 상태다.
library;

abstract final class AppRoutes {
  /// A-1 스플래시.
  static const splash = '/splash';

  /// A-2 로그인.
  static const login = '/login';

  /// A-3 회원가입과 동의.
  static const signup = '/signup';

  /// 구글 로그인 뒤 받는 필수 동의.
  ///
  /// `POST /auth/google` 이 `consentRequired` 를 준 경우에만 들어간다. 로그인
  /// 화면이 `extra` 로 등록 정보를 함께 넘긴다.
  static const googleConsent = '/login/consent';

  /// B-1 처음 오셨네요.
  static const onboarding = '/onboarding';

  /// B-2 ~ B-8 환자 정보 최초 입력.
  static const profileCreate = '/profile/create';

  /// 시작 화면.
  static const home = '/home';

  /// C 오늘의 대화 카드.
  static const cards = '/cards';

  /// D 면회 전 사진 촬영.
  static const visitPhoto = '/visit/photo';

  /// E-1, E-2 녹음 안내와 녹음 중.
  static const visitRecord = '/visit/record';

  /// E-5 면회 중 대화 카드 추가.
  ///
  /// E-3, E-4 면회 중 대화 카드는 녹음 화면 위로 올라오는 팝업이라 경로가 없다.
  static const visitAddCards = '/visit/cards/add';

  /// F 보호자 소감 작성.
  static const visitReview = '/visit/review';

  /// G 리포트. `:reportId` 를 받는다.
  static const report = '/report/:reportId';

  /// 리포트 기록에서 들어오면 이미 반영을 마친 회차라 변경 사항을 다시 묻지
  /// 않는다. 홈의 도착 알림에서 들어오면 아직 확인 전이다.
  static String reportOf(String reportId, {bool fromHistory = false}) =>
      fromHistory ? '/report/$reportId?from=history' : '/report/$reportId';

  /// G-2 변경 사항 확인.
  static const reportChanges = '/report/:reportId/changes';

  static String reportChangesOf(String reportId) => '/report/$reportId/changes';

  /// 프로필 설정. 하단 탭의 팝업 메뉴에서 들어간다.
  static const profile = '/profile';

  /// 회원 탈퇴 확인. 피그마 설계 없음.
  static const profileDelete = '/profile/delete';

  /// 리포트 기록. 확인한 리포트를 다시 볼 수 있다.
  static const reports = '/reports';

  /// 알림. 피그마 설계 없음.
  ///
  /// 지금은 홈의 리포트 알림 상태(`ReportNotice`) 하나만 보여준다. 날짜별로
  /// 여러 건이 쌓인 이력을 보여주려면 `app/lib/data/` 의 데이터 모델을
  /// 넓혀야 한다. 그 전까지는 홈 배너와 같은 내용을 보여주는 자리다.
  static const notifications = '/notifications';

  /// H 일대기. 기획 보류.
  static const album = '/album';
}
