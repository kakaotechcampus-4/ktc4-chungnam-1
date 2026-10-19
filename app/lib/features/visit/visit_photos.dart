/// 면회 전에 찍은 사진을 기기에 남긴다(D-1).
///
/// 면회 녹음([PendingUploads])과 같은 기준으로 보관한다(PR #136 리뷰). 카메라
/// 앱이 남긴 파일은 기기가 언제든 비울 수 있는 임시 폴더에 있으므로 찍자마자
/// 앱 전용 공간의 `visit_photos/` 로 옮긴다. 같은 폴더에 작은 기록
/// (`visit-photos.json`)을 두며, 담는 것은 계정 ID, 파일 이름, 올린 회차 ID뿐이다.
///
/// 서버가 받은 뒤에도, 새 면회를 시작하거나 로그아웃해도 지우지 않는다. 탈퇴하면
/// 그 계정의 사진과 기록을 지운다([VisitPhotos.forgetAccount]). 올리기 전에 다시
/// 찍은 사진만 바로 지운다. 서버에 간 적이 없는 사진이라 남길 이유가 없다.
/// 사진 폴더는 자동 백업에서 뺐다(`android/app/src/main/res/xml/`).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../auth/auth_providers.dart';

abstract interface class VisitPhotos {
  /// 찍은 사진을 앱 전용 공간으로 옮기고 지금 계정의 사진으로 적는다. 옮긴
  /// 경로를 돌려준다. 카메라가 남긴 원본은 지운다.
  Future<String> keep(String capturedPath);

  /// 회차에 올린 사진이라고 적는다. 파일은 지우지 않는다.
  Future<void> markUploaded(String path, String sessionId);

  /// 올리지 않은 사진이면 파일과 기록을 지운다. 올린 사진은 그대로 둔다.
  Future<void> discard(String path);

  /// 탈퇴한 계정의 사진과 기록을 모두 지운다.
  ///
  /// 기록이 없는 사진 파일도 함께 지운다. 어느 계정 것인지 알 수 없다.
  Future<void> forgetAccount(String accountId);
}

/// 앱 전용 공간의 `visit_photos/` 에 둔다.
///
/// [accountId] 는 지금 로그인한 계정이다. `null` 이면 서버 세션 없이 들어온
/// 경우다(디버그 빌드의 로그인 건너뛰기).
class DeviceVisitPhotos implements VisitPhotos {
  DeviceVisitPhotos({this.accountId, Future<Directory> Function()? directory})
    : _directory = directory ?? _photosDirectory;

  final String? accountId;

  final Future<Directory> Function() _directory;

  static const directoryName = 'visit_photos';
  static const fileName = 'visit-photos.json';

  static Future<Directory> _photosDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory('${documents.path}/$directoryName');
  }

  static String _nameOf(String path) => path.split(RegExp(r'[/\\]')).last;

  @override
  Future<String> keep(String capturedPath) async {
    final directory = await _directory();
    await directory.create(recursive: true);

    // 파일 이름에는 시각만 넣는다. 사람을 알아볼 값은 남기지 않는다(저장소 공통 지침).
    final stamp = DateTime.now().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    final name = 'visit-photo-$stamp.jpg';
    final kept = '${directory.path}/$name';

    // 임시 폴더와 문서 폴더가 다른 저장소일 수 있어 옮기지 않고 복사한 뒤 지운다.
    final captured = File(capturedPath);
    await captured.copy(kept);
    try {
      await captured.delete();
    } on FileSystemException {
      // 원본은 기기가 비우는 임시 파일이다.
    }

    final entries = await _read(directory)
      ..add({'accountId': accountId, 'fileName': name, 'sessionId': null});
    await _write(directory, entries);
    return kept;
  }

  @override
  Future<void> markUploaded(String path, String sessionId) async {
    final directory = await _directory();
    final name = _nameOf(path);
    final entries = await _read(directory)
      ..removeWhere((e) => e['fileName'] == name);
    entries.add({
      'accountId': accountId,
      'fileName': name,
      'sessionId': sessionId,
    });
    await _write(directory, entries);
  }

  @override
  Future<void> discard(String path) async {
    final directory = await _directory();
    final name = _nameOf(path);
    final entries = await _read(directory);
    if (entries.any((e) => e['fileName'] == name && e['sessionId'] != null)) {
      return;
    }

    entries.removeWhere((e) => e['fileName'] == name);
    await _write(directory, entries);
    try {
      await File('${directory.path}/$name').delete();
    } on FileSystemException {
      // 이미 없으면 그대로 둔다.
    }
  }

  @override
  Future<void> forgetAccount(String accountId) async {
    final directory = await _directory();
    if (!await directory.exists()) return;

    final entries = await _read(directory)
      ..removeWhere((e) => e['accountId'] == accountId);
    await _write(directory, entries);

    // 남은 기록이 가리키지 않는 사진은 모두 지운다.
    final kept = {
      for (final e in entries)
        if (e['fileName'] is String) e['fileName'] as String,
    };
    await for (final item in directory.list()) {
      if (item is! File) continue;
      final name = item.uri.pathSegments.last;
      if (!name.endsWith('.jpg')) continue;
      if (kept.contains(name)) continue;
      await item.delete();
    }
  }

  /// 읽지 못하는 기록은 빈 것으로 본다. 기록 때문에 면회를 막지 않는다.
  Future<List<Map<String, dynamic>>> _read(Directory directory) async {
    final file = File('${directory.path}/$fileName');
    if (!await file.exists()) return [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      return decoded.whereType<Map<String, dynamic>>().toList();
    } on FormatException {
      return [];
    }
  }

  /// 쓰다 앱이 꺼져도 반쯤 쓴 기록이 남지 않게 옆에 쓴 뒤 바꿔 끼운다.
  Future<void> _write(
    Directory directory,
    List<Map<String, dynamic>> entries,
  ) async {
    final file = File('${directory.path}/$fileName');
    if (entries.isEmpty) {
      if (await file.exists()) await file.delete();
      return;
    }
    await directory.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(entries), flush: true);
    await temp.rename(file.path);
  }
}

/// 지금 로그인한 계정의 사진 보관소다. 계정이 바뀌면 새로 만든다.
///
/// 테스트는 이 provider 를 override 해 실제 파일을 건드리지 않는다.
final visitPhotosProvider = Provider<VisitPhotos>(
  (ref) => DeviceVisitPhotos(
    accountId: ref.watch(sessionProvider.select((s) => s?.account.accountId)),
  ),
);
