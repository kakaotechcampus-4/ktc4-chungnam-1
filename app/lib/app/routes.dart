/// 화면 경로를 한곳에 모은다. 화면 이동은 문자열을 직접 적지 않고 여기를 쓴다.
///
/// 사용자 흐름은 `app/README.md` 의 "현재 사용자 흐름" 과 피그마 스토리맵
/// A~H 를 따른다. `리포트 기록` 은 기획 보류 상태다.
library;

abstract final class AppRoutes {
  /// A-1 스플래시. 따로 있던 A-2 로그인을 합쳤다. 로그인이 필요하면 로고
  /// 아래에 구글 로그인 버튼을 띄운다.
  static const splash = '/splash';

  /// 로그인이 풀린 것을 이미 알고 스플래시로 돌아갈 때 쓴다. 로그아웃, 탈퇴,
  /// 세션이 풀렸을 때다. 복원을 확인하지 않고 곧바로 로그인 버튼을 띄운다.
  static const signIn = '/splash?signedOut=true';

  /// 구글 로그인 뒤 받는 필수 동의.
  ///
  /// `POST /auth/google` 이 `consentRequired` 를 준 경우에만 들어간다.
  /// 스플래시의 로그인 버튼이 `extra` 로 등록 정보를 함께 넘긴다.
  static const googleConsent = '/consent';

  /// B-1 처음 오셨네요.
  static const onboarding = '/onboarding';

  /// B-2 ~ B-7 환자 정보 최초 입력.
  static const profileCreate = '/profile/create';

  /// 어르신을 더 등록하는 입력. 최초 입력과 같은 화면이며, 처음 오셨네요를
  /// 거치지 않고 마치면 새로 등록한 분으로 바뀐다. [id] 는 `입력 중` 슬롯이다.
  static String profileAddOf(String id) => '/profile/create?adding=$id';

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

  /// 보호자 평가 제출 뒤 위로 화면. 피그마 설계 없음. 여기서 홈으로 간다.
  static const visitReviewDone = '/visit/review/done';

  /// G 리포트. `:reportId` 를 받는다.
  static const report = '/report/:reportId';

  /// 리포트 기록에서 들어오면 이미 반영을 마친 회차라 변경 사항을 다시 묻지
  /// 않는다. 홈의 도착 알림에서 들어오면 아직 확인 전이다.
  static String reportOf(String reportId, {bool fromHistory = false}) =>
      fromHistory ? '/report/$reportId?from=history' : '/report/$reportId';

  /// G-2 변경 사항 확인.
  static const reportChanges = '/report/:reportId/changes';

  static String reportChangesOf(String reportId) => '/report/$reportId/changes';

  /// G-2 에서 여는 이야기 수정. 변경 사항 확인이 `extra` 로 고칠 이야기를
  /// 넘기고, `수정 완료` 를 누르면 고친 값을 돌려받는다.
  ///
  /// `/report/story-edit` 처럼 두면 `/report/:reportId` 가 먼저 잡아 리포트
  /// 화면이 열린다. 변경 사항 확인 아래에 둔다.
  static const storyEdit = '/report/:reportId/changes/story';

  static String storyEditOf(String reportId) =>
      '/report/$reportId/changes/story';

  /// 프로필 설정. 하단 탭의 팝업 메뉴에서 들어간다.
  static const profile = '/profile';

  /// 지금 보고 있는 어르신의 이름과 기본 정보 수정. 프로필 설정에서 들어간다.
  /// 피그마 설계 없음.
  static const profileEditBasic = '/profile/edit/basic';

  /// 지금 보고 있는 어르신의 세부 정보 네 항목 수정. 프로필 설정에서 들어간다.
  /// 피그마 설계 없음.
  static const profileEditDetails = '/profile/edit/details';

  /// 함께하는 소중한 분. 홈 상단의 어르신 알약을 누르면 들어온다. 피그마 설계 없음.
  static const profileSwitch = '/profiles';

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

  /// H 일대기의 표지. 하단 탭의 일대기에서 들어온다.
  static const album = '/album';

  /// 일대기 표지를 펼친 첫 장. 어르신 정보, 분류와 최근 이야기.
  static const albumBook = '/album/book';

  /// 한 분류의 목차. `:category` 는 `LifeStoryCategory` 의 이름이다.
  static const albumCategory = '/album/category/:category';

  static String albumCategoryOf(String category) => '/album/category/$category';

  /// 이야기 한 편. 목차 아래에 두어 뒤로 가면 목차가 나온다.
  static const albumStory = '/album/category/:category/story/:storyId';

  static String albumStoryOf(String category, String storyId) =>
      '/album/category/$category/story/$storyId';

  /// 일대기 첫 장의 `이야기 추가하기`.
  static const albumStoryNew = '/album/new';

  /// 이야기 화면의 연필. 고친 이야기를 돌려준다.
  static const albumStoryEdit = '/album/edit/:storyId';

  static String albumStoryEditOf(String storyId) => '/album/edit/$storyId';
}
