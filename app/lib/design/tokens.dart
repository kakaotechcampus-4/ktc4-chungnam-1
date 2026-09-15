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
