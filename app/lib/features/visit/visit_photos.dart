/// 면회 전에 찍은 사진을 서버에 올리려고 앱에 둔 사본이다(D-1).
///
/// 사진 원본은 갤러리에 남긴다([VisitGallery], PR #136 리뷰). 여기 두는 것은
/// 서버에 올리고 다시 올리는 데 쓰는 작업용 사본이다. 카메라 앱이 남긴 파일은
/// 기기가 언제든 비울 수 있는 임시 폴더에 있으므로 찍자마자 앱 전용 공간의
/// `visit_photos/` 로 옮긴다. 같은 폴더에 작은 기록(`visit-photos.json`)을 두며,
/// 담는 것은 계정 ID, 파일 이름, 올린 회차 ID, 갤러리에 남겼는지뿐이다.
///
/// 갤러리에 남긴 사진의 사본은 필요 없어지면 지운다. 서버가 받았을 때, 올리기
/// 전에 다시 찍었을 때, 새 면회를 시작할 때다([VisitPhotos.tidy]). 갤러리에
/// 남기지 못한 사진은 사본이 유일한 파일이라 탈퇴 때까지 지우지 않는다. 탈퇴하면
/// 그 계정의 사본과 기록을 모두 지운다([VisitPhotos.forgetAccount]). 갤러리의
/// 원본은 어느 때도 건드리지 않는다.
/// 사진 폴더는 자동 백업에서 뺐다(`android/app/src/main/res/xml/`).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../auth/auth_providers.dart';
import 'visit_gallery.dart';

abstract interface class VisitPhotos {
  /// 찍은 사진을 앱 전용 공간으로 옮기고 지금 계정의 사진으로 적는다. 옮긴
  /// 경로를 돌려준다. 카메라가 남긴 임시 파일은 지운다.
  ///
  /// [inGallery] 는 갤러리에 원본을 남겼는지다. 남기지 못했으면 사본을
  /// 탈퇴 때까지 지우지 않는다.
  Future<String> keep(String capturedPath, {required bool inGallery});

  /// 회차에 올린 사진이라고 적는다. 갤러리에 원본이 있으면 사본을 지운다.
  Future<void> markUploaded(String path, String sessionId);

  /// 더 쓰지 않는 사진이다. 갤러리에 원본이 있으면 사본과 기록을 지운다.
  /// 없으면 그대로 둔다.
  Future<void> discard(String path);

  /// 새 면회를 시작할 때 지난 면회의 사본 가운데 갤러리에 원본이 있는 것을
  /// 지운다. 올리지 못하고 남은 사본이다.
  Future<void> tidy();

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

  /// 기록을 읽고 고쳐 쓰는 일을 한 번에 하나씩 한다. 새 면회의 정리([tidy])와
  /// 촬영([keep])이 겹쳐도 서로의 기록을 덮지 않는다. 계정이 바뀌어 보관소를
  /// 새로 만들어도 같은 폴더라 함께 줄 세운다.
  static Future<void> _queue = Future.value();

  static Future<T> _serially<T>(Future<T> Function() task) {
    final result = _queue.then((_) => task());
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  @override
  Future<String> keep(String capturedPath, {required bool inGallery}) =>
      _serially(() => _keep(capturedPath, inGallery: inGallery));

  @override
  Future<void> markUploaded(String path, String sessionId) =>
      _serially(() => _markUploaded(path, sessionId));

  @override
  Future<void> discard(String path) => _serially(() => _discard(path));

  @override
  Future<void> tidy() => _serially(_tidy);

  @override
  Future<void> forgetAccount(String accountId) =>
      _serially(() => _forgetAccount(accountId));

  Future<String> _keep(String capturedPath, {required bool inGallery}) async {
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
      // 기기가 비우는 임시 파일이다.
    }

    final entries = await _read(directory)
      ..add({
        'accountId': accountId,
        'fileName': name,
        'sessionId': null,
        'inGallery': inGallery,
      });
    await _write(directory, entries);
    return kept;
  }

  Future<void> _markUploaded(String path, String sessionId) async {
    final directory = await _directory();
    final name = _nameOf(path);
    final entries = await _read(directory);
    if (entries.any((e) => e['fileName'] == name && _inGallery(e))) {
      await _delete(directory, entries, {name});
      return;
    }

    entries
      ..removeWhere((e) => e['fileName'] == name)
      ..add({
        'accountId': accountId,
        'fileName': name,
        'sessionId': sessionId,
        'inGallery': false,
      });
    await _write(directory, entries);
  }

  Future<void> _discard(String path) async {
    final directory = await _directory();
    final name = _nameOf(path);
    final entries = await _read(directory);
    if (!entries.any((e) => e['fileName'] == name && _inGallery(e))) return;
    await _delete(directory, entries, {name});
  }

  Future<void> _tidy() async {
    final directory = await _directory();
    if (!await directory.exists()) return;
    final entries = await _read(directory);
    final names = {
      for (final e in entries)
        if (_inGallery(e) && e['fileName'] is String) e['fileName'] as String,
    };
    if (names.isEmpty) return;
    await _delete(directory, entries, names);
  }

  /// 갤러리에 원본을 남긴 사진인가. 이 값이 없는 기록은 남기지 않은 것으로
  /// 본다. 사본이 유일한 파일일 수 있어서다.
  static bool _inGallery(Map<String, dynamic> entry) =>
      entry['inGallery'] == true;

  /// [names] 의 기록을 먼저 지우고 파일을 지운다. 기록만 남아 없는 파일을
  /// 가리키지 않게 한다.
  Future<void> _delete(
    Directory directory,
    List<Map<String, dynamic>> entries,
    Set<String> names,
  ) async {
    entries.removeWhere((e) => names.contains(e['fileName']));
    await _write(directory, entries);
    for (final name in names) {
      try {
        await File('${directory.path}/$name').delete();
      } on FileSystemException {
        // 이미 없으면 그대로 둔다.
      }
    }
  }

  Future<void> _forgetAccount(String accountId) async {
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
