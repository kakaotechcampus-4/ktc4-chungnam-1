/// `app/DESIGN.md` 의 값을 코드로 옮긴 것이다.
/// 화면에서 색과 크기를 직접 적지 않고 여기를 통해 쓴다.
/// 값을 바꾸면 `app/DESIGN.md` 도 같은 변경에서 갱신한다.
library;

import 'package:flutter/material.dart';

/// 화면은 흑백만 쓴다. 붉은색은 필수 표시와 경고에만 쓴다.
abstract final class AppColors {
  /// 본문 글자와 주 버튼 면.
  static const ink = Color(0xFF111111);

  /// 보조 글자.
  static const textSub = Color(0xFF5C5C5C);

  /// 비활성 글자. 흰 배경 대비 4.5:1 로 하한이다.
  static const textDisabled = Color(0xFF767676);

  /// 고르지 않은 선택 표시(빈 원)의 테두리. 누를 수 있는 자리를 알리는 그림의
  /// 하한(흰 배경 3:1)을 지키는 가장 연한 회색이다(3.03:1). 글자에는 쓰지 않는다.
  static const selectionRing = Color(0xFF949494);

  /// 구분선과 테두리.
  static const line = Color(0xFFE0E0E0);

  /// 표면과 카드 배경.
  static const surface = Color(0xFFF5F5F5);

  /// 화면 배경.
  static const background = Color(0xFFFFFFFF);

  /// 필수 표시와 오류.
  static const danger = Color(0xFF99392E);

  /// 오류 영역 배경. 그 위에는 [danger] 글자를 올린다.
  static const dangerSurface = Color(0xFFF7E9E7);

  /// 일대기 책 표지. 그 위에는 [ink] 글자를 올린다.
  static const bookCover = Color(0xFFD9D9D9);

  /// 일대기 책 표지의 책등.
  static const bookSpine = Color(0xFFC6C6C6);
}

/// 앱의 모든 화면에 쓰는 세이지 색. 세이지 초록을 연하게 풀어 쓴다
/// (2026-11-06 디자인 리뉴얼). 글자, 경고, 나눔선은 [AppColors] 의 검정과
/// 회색을 그대로 쓴다.
///
/// 하단 탭은 어느 탭에서든 [accent] 로 고른 탭을 칠한다. 언덕 그림은 홈에만
/// 둔다.
abstract final class HomeColors {
  /// 화면 배경. 흰색에 아주 가까운 오프화이트다. 보조 글자 6.4:1.
  static const background = Color(0xFFFBFAF6);

  /// `오늘의 대화카드 받기`, `대화 시작하기` 버튼 면, 하단 탭에서 고른 탭의
  /// 아이콘, 글자와 막대, 고른 대화 카드의 테두리와 체크 원, `○개 선택함` 칩.
  /// 흰 글자 6.6:1, 흰 탭 바탕 위 6.6:1.
  static const accent = Color(0xFF4E6347);

  /// [accent] 버튼이 도는 중일 때의 면. 흰 글자 4.6:1.
  static const accentLoading = Color(0xFF677A60);

  /// 어르신 알약과 연초록 면. 회색이 섞인 아주 연한 초록이다. 본문 글자 16.4:1.
  /// 홈 캐릭터 말풍선은 흰색([AppColors.background])으로 둔다.
  static const bubble = Color(0xFFEDF0E9);

  /// 어르신 알약의 연한 테두리.
  static const bubbleLine = Color(0xFFC5CDBC);

  /// 오프화이트 바탕에서도 보이는 진한 테두리. 보조 버튼, 녹음 버튼, 카드
  /// 부채, 리포트의 카드와 칸 테두리에 쓴다. 오프화이트 위 2.4:1.
  static const outline = Color(0xFF9AA68E);

  /// 뒤 언덕.
  static const hillBack = Color(0xFFEEF0E9);

  /// 앞 언덕. 그 위 보조 글자 5.0:1, 오류 글자 5.3:1.
  static const hillFront = Color(0xFFDCE1D5);
}

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

  /// 만남 사진 화면과 녹음 안내 화면의 제목 위 여백. 두 화면을 넘길 때 제목이
  /// 같은 자리에 오게 한다.
  static const visitTitleTop = 56.0;

  /// 섹션 사이.
  static const section = 32.0;

  /// 같은 섹션 안의 항목 사이.
  static const item = 12.0;
}

abstract final class AppRadius {
  static const button = 14.0;
  static const card = 16.0;
  static const image = 16.0;

  /// 칩과 뱃지는 완전한 둥근 모양이다.
  static const pill = 999.0;
}

abstract final class AppShadows {
  /// 목록 카드와 대화 카드.
  static const low = [
    BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2)),
  ];

  /// 팝업 메뉴와 하단 탭바.
  static const high = [
    BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 4)),
  ];

  /// 오프화이트 바탕 위의 흰 대화 카드. [low] 보다 조금 진하다.
  static const card = [
    BoxShadow(color: Color(0x1F000000), blurRadius: 10, offset: Offset(0, 3)),
  ];

  /// 대화 카드 받기와 추가 화면의 흰 대화 카드. [card] 보다 살짝 옅다.
  static const cardSoft = [
    BoxShadow(color: Color(0x17000000), blurRadius: 9, offset: Offset(0, 2)),
  ];
}

/// 50~60대가 주 사용자다. 본문은 17이고 캡션 13보다 작게 쓰지 않는다.
abstract final class AppTypography {
  static const _height = 1.5;

  static const screenTitle = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.35,
    letterSpacing: -0.4,
    color: AppColors.ink,
  );

  static const sectionTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.4,
    color: AppColors.ink,
  );

  static const body = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w400,
    height: _height,
    color: AppColors.ink,
  );

  static const bodyStrong = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: _height,
    color: AppColors.ink,
  );

  static const sub = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: _height,
    color: AppColors.textSub,
  );

  /// 가장 작은 글자다.
  static const caption = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: _height,
    color: AppColors.textSub,
  );

  static const button = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: AppColors.ink,
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
