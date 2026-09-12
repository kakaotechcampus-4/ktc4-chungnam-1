/// `app/DESIGN.md` 의 값을 코드로 옮긴 것이다.
/// 화면에서 색과 크기를 직접 적지 않고 여기를 통해 쓴다.
/// 값을 바꾸면 `app/DESIGN.md` 도 같은 변경에서 갱신한다.
library;

import 'package:flutter/material.dart';

/// 1층. 팔레트 원색과 거기서 파생한 단계다.
///
/// **화면에서 이 이름을 직접 부르지 않는다.** 역할 이름인 [AppColors] 를 쓴다.
/// 네 원색은 `app/docs/design-references/04-Color-palette.webp` 에서 왔고,
/// 파생 단계는 [forest] 의 밝기만 옮긴 것이다. 새 색조를 들이지 않는다.
abstract final class AppPalette {
  /// 화면 배경.
  static const ivory = Color(0xFFFFFBF7);

  /// 카드와 입력 상자의 면.
  static const cream = Color(0xFFFAF2E7);

  /// 선택되거나 강조된 영역의 면.
  static const sage = Color(0xFFE5EFE7);

  /// 본문 글자와 주 버튼 면.
  static const forest = Color(0xFF074321);

  /// 보조 글자. 아이보리 위 7.9:1.
  static const forestSub = Color(0xFF0A5C2D);

  /// 비활성 글자. 아이보리 위 5.4:1, 세이지 위 4.7:1 로 하한이다.
  static const forestSoft = Color(0xFF0D783B);

  /// 구분선과 기본 테두리.
  static const lineTint = Color(0xFFDCE1D9);

  /// 필수 표시와 오류.
  static const clay = Color(0xFF99392E);

  /// 오류 영역 배경.
  static const claySurface = Color(0xFFF7E9E7);
}

/// 2층. 역할 이름이다. 화면에서는 여기만 부른다.
///
/// 색을 바꿀 때 이 표만 고치면 화면이 따라온다.
abstract final class AppColors {
  /// 화면 배경.
  static const background = AppPalette.ivory;

  /// 카드와 입력 상자의 면.
  static const surface = AppPalette.cream;

  /// 선택되거나 강조된 영역의 면.
  static const accentSurface = AppPalette.sage;

  /// 본문 글자.
  static const ink = AppPalette.forest;

  /// 보조 글자.
  static const textSub = AppPalette.forestSub;

  /// 비활성 글자. 4.5:1 이 하한이라 이보다 흐린 색을 글자에 쓰지 않는다.
  static const textDisabled = AppPalette.forestSoft;

  /// 구분선과 테두리.
  static const line = AppPalette.lineTint;

  /// 강조와 주 버튼 면.
  static const accent = AppPalette.forest;

  /// 강조 면 위의 글자.
  static const onAccent = AppPalette.ivory;

  /// 필수 표시와 오류.
  static const danger = AppPalette.clay;

  /// 오류 영역 배경. 그 위에는 [danger] 글자를 올린다.
  static const dangerSurface = AppPalette.claySurface;

  /// 눌렀을 때 면 위에 얹는 덮개. 포레스트 12%.
  ///
  /// 버튼마다 눌린 색을 따로 정하지 않는다.
  static const pressOverlay = Color(0x1F074321);
}

/// 비활성 상태의 투명도.
///
/// 글자만 흐리게 바꾸지 않고 컴포넌트 전체에 건다.
const double kDisabledOpacity = 0.3;

/// 간격은 4의 배수만 쓴다.
abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 40.0;

  /// 화면 좌우 여백.
  static const screen = 20.0;

  /// 섹션 사이.
  static const section = 32.0;

  /// 같은 섹션 안의 항목 사이.
  static const item = 12.0;

  /// 라벨과 입력처럼 붙어 있어야 하는 것 사이는 [sm], 목록의 행 사이는 [lg],
  /// 누르는 요소 사이의 최소 간격은 [md] 다. 같은 값에 이름을 더 만들지 않는다.
}

/// 모서리는 높이에 연동한다. 큰 것일수록 더 둥글다.
abstract final class AppRadius {
  /// 높이 56. 주 버튼, 보조 버튼, 입력 상자.
  static const control56 = 16.0;

  static const control48 = 14.0;
  static const control40 = 12.0;
  static const control32 = 10.0;

  /// 높이를 갖지 않는 것은 따로 정한다.
  static const card = 16.0;
  static const image = 16.0;

  /// 칩과 뱃지는 완전한 둥근 모양이다.
  static const pill = 999.0;
}

/// 떠 있는 느낌이 필요한 곳에만 쓴다. 평면이 기본이다.
///
/// 그림자 색은 검정이 아니라 포레스트를 낮은 투명도로 쓴다. 크림 바탕에
/// 검정 그림자를 깔면 회색 얼룩으로 남는다.
abstract final class AppShadows {
  /// 목록 카드와 대화 카드.
  static const level1 = [
    BoxShadow(color: Color(0x14074321), blurRadius: 8, offset: Offset(0, 2)),
  ];

  /// 펼친 메뉴와 말풍선. 말풍선은 아직 쓰는 화면이 없다.
  static const level2 = [
    BoxShadow(color: Color(0x1A074321), blurRadius: 12, offset: Offset(0, 4)),
  ];

  /// 다이얼로그와 하단 탭바.
  static const level3 = [
    BoxShadow(color: Color(0x1F074321), blurRadius: 20, offset: Offset(0, 6)),
  ];

  /// 토스트. 아직 쓰는 화면이 없다.
  static const level4 = [
    BoxShadow(color: Color(0x29074321), blurRadius: 24, offset: Offset(0, 8)),
  ];

  /// 아래에서 올라오는 시트. 그림자를 위쪽으로 드리운다.
  static const sheet = [
    BoxShadow(color: Color(0x14074321), blurRadius: 12, offset: Offset(0, -2)),
  ];
}

/// 움직이는 시간은 셋뿐이다.
abstract final class AppMotion {
  /// 누름.
  static const fast = Duration(milliseconds: 120);

  /// 선택, 토글, 초점 이동.
  static const base = Duration(milliseconds: 200);

  /// 시트와 팝업이 열리고 닫힐 때.
  static const slow = Duration(milliseconds: 320);

  /// 끝에서 감속하는 기본 곡선.
  static const curve = Curves.easeOutCubic;

  /// 시트가 올라올 때. 기본보다 빠르게 붙는다.
  static const sheetCurve = Curves.easeOutExpo;
}

/// 50~60대가 주 사용자다. 본문은 17이고 캡션 13보다 작게 쓰지 않는다.
///
/// 크기와 굵기는 `app/DESIGN.md` 의 표를 그대로 옮긴 것이다. 자간은 크기에
/// 비례해 좁히고, 줄 간격은 제목을 좁히고 본문을 넓힌다.
abstract final class AppTypography {
  static const screenTitle = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: -0.56,
    color: AppColors.ink,
  );

  static const sectionTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.35,
    letterSpacing: -0.3,
    color: AppColors.ink,
  );

  static const button = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.25,
    letterSpacing: -0.18,
    color: AppColors.ink,
  );

  static const body = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w400,
    height: 1.5,
    letterSpacing: -0.09,
    color: AppColors.ink,
  );

  static const bodyStrong = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.45,
    letterSpacing: -0.17,
    color: AppColors.ink,
  );

  static const sub = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.5,
    letterSpacing: -0.08,
    color: AppColors.textSub,
  );

  /// 가장 작은 글자다.
  static const caption = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: AppColors.textSub,
  );

  /// 홈의 앱 이름. 제목이 아니라 이름표다.
  static const appName = TextStyle(
    fontSize: 44,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.88,
    color: AppColors.ink,
  );

  /// 면회 중 대화 카드의 메인 질문. 곁눈질로 읽어야 해서 크다.
  static const cardQuestion = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: -0.48,
    color: AppColors.ink,
  );

  /// 면회 중 대화 카드의 꼬리 질문.
  static const cardFollowUp = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w400,
    height: 1.3,
    letterSpacing: -0.39,
    color: AppColors.ink,
  );

  /// 녹음 화면의 경과 시간. 폭이 흔들리지 않게 고정폭 숫자를 쓴다.
  static const elapsed = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: AppColors.ink,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

abstract final class AppSizes {
  /// 주 버튼과 입력 상자의 높이.
  static const control = 56.0;

  /// 누르는 요소의 최소 크기.
  static const minTouch = 48.0;

  static const topBar = 56.0;
  static const bottomNav = 64.0;

  /// 기준 화면. `app/DESIGN.md` 참고.
  static const referenceWidth = 412.0;
  static const referenceHeight = 917.0;
}
