import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// 앱 언어. 한국어 하나만 둔다.
///
/// 언어를 두지 않으면 `en_US` 로 잡혀 TalkBack 이 앱 글자를 영어 음성으로 읽고,
/// Flutter 가 넣는 메뉴 손잡이와 닫기 같은 기본 문구도 영어가 된다(접근성
/// 보고서 8쪽, 12쪽). 기기 언어와 관계없이 이 언어를 쓴다.
const appLocale = Locale('ko', 'KR');

const appSupportedLocales = [appLocale];

const appLocalizationsDelegates = <LocalizationsDelegate<Object>>[
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];
