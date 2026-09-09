// 목 데이터 사본이 원본과 같은지 확인한다.
//
// 원본: docs/architecture/mock/  — 공통 데이터 계약과 함께 FE, BE, AI 리더가 공동 관리한다.
// 사본: app/assets/mock/         — Flutter 는 패키지 루트 밖을 asset 으로 읽지 못해 복사해 둔다.
//
// 두 벌이 갈라지면 화면이 계약과 다른 데이터를 쓰게 된다. 사람이 기억하는 대신
// 이 테스트가 확인한다.
//
// 원본이 아직 이 브랜치에 없으면(공통 데이터 계약 PR 미머지) 건너뛴다.
// develop 을 가져와 원본이 생기면 코드 수정 없이 비교가 시작된다.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// `flutter test` 의 작업 디렉터리는 패키지 루트(`app/`)다.
const _sourceDirPath = '../docs/architecture/mock';
const _copyDirPath = 'assets/mock';

const _fileNames = <String>[
  'account.json',
  'caregiver-evaluation.json',
  'conversation-cards.json',
  'profile.json',
  'visit-report.json',
  'visit-session.json',
];

/// 줄 끝 문자와 파일 끝 공백만 맞춘다. 그 밖의 차이는 실제 차이로 본다.
String _normalize(String raw) => raw.replaceAll('\r\n', '\n').trimRight();

void main() {
  final sourceDir = Directory(_sourceDirPath);
  final sourceMissing = !sourceDir.existsSync();

  group('목 데이터 사본이 원본과 같은지', () {
    for (final name in _fileNames) {
      test(
        name,
        () {
          final source = File('$_sourceDirPath/$name');
          final copy = File('$_copyDirPath/$name');

          expect(
            copy.existsSync(),
            isTrue,
            reason: '사본이 없다: ${copy.path}. 원본에서 복사한다.',
          );
          expect(
            _normalize(copy.readAsStringSync()),
            _normalize(source.readAsStringSync()),
            reason: '$name 이 원본과 다르다. 원본을 기준으로 사본을 다시 복사한다.',
          );
        },
        skip: sourceMissing
            ? '원본 $_sourceDirPath 이 이 브랜치에 없다. 공통 데이터 계약이 develop 에 머지되면 동작한다.'
            : false,
      );
    }
  });

  group('목 데이터를 asset 으로 읽을 수 있는지', () {
    // pubspec.yaml 의 assets 선언이 실제로 동작하는지 확인한다.
    setUp(TestWidgetsFlutterBinding.ensureInitialized);

    for (final name in _fileNames) {
      test(name, () async {
        final raw = await rootBundle.loadString('$_copyDirPath/$name');
        final decoded = jsonDecode(raw);

        expect(decoded, isA<Map<String, dynamic>>());
        expect(
          (decoded as Map<String, dynamic>)['schemaVersion'],
          isNotNull,
          reason: '$name 에 최상위 schemaVersion 이 없다.',
        );
      });
    }
  });
}
