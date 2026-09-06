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

  /// E 녹음과 면회 중 대화 카드.
  static const visitRecord = '/visit/record';

  /// F 보호자 소감 작성.
  static const visitReview = '/visit/review';

  /// 소감 제출 후 리포트가 만들어지는 동안 보여주는 로딩 화면.
  static const visitProcessing = '/visit/processing';

  /// G 리포트. `:reportId` 를 받는다.
  static const report = '/report/:reportId';

  static String reportOf(String reportId) => '/report/$reportId';

  /// 프로필 설정. 하단 탭의 팝업 메뉴에서 들어간다.
  static const profile = '/profile';

  /// 리포트 기록. 확인한 리포트를 다시 볼 수 있다.
  static const reports = '/reports';

  /// H 일대기. 기획 보류.
  static const album = '/album';
}
