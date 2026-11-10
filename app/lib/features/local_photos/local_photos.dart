/// 보호자가 고른 어르신 사진과 이야기 사진을 이 기기에만 둔다.
///
/// 서버에 올리지 않는다. 그래서 다른 기기, 앱을 다시 설치한 뒤와 다른 보호자의
/// 휴대폰에서는 보이지 않고, 대화 카드와 AI 사진 분석에도 쓰지 않는다. 사진이
/// 없으면 화면은 지금까지의 기본 그림(성별 사진, 분류별 그림)을 그린다.
///
/// 앨범에서 고른 사진은 앱 전용 공간의 `local_photos/` 로 복사한다. 앨범 원본을
/// 지워도 사진이 깨지지 않게 하려는 것이다. 같은 폴더의 작은 기록
/// (`local-photos.json`)에 계정 ID, 어르신 ID, 자리([LocalPhotoSlot])와 파일
/// 이름만 적는다. 파일 이름에는 시각만 넣는다(저장소 공통 지침).
///
/// 지우는 때: 사진을 바꾸거나 기본 그림으로 되돌릴 때, 이야기를 지울 때
/// ([LocalPhotos.remove]), 어르신을 지울 때([LocalPhotos.forgetProfile]), 탈퇴할
/// 때([LocalPhotos.forgetAccount]). 로그아웃은 지우지 않는다. 기록이 계정별이라
/// 다른 계정은 보지 못한다. 폴더는 자동 백업에서 뺐다(`android/app/src/main/res/xml/`).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../auth/auth_providers.dart';

/// 어르신 한 분 안에서 사진이 놓이는 자리.
abstract final class LocalPhotoSlot {
  /// 어르신의 원형 프로필 사진.
  static const avatar = 'avatar';

  /// 일대기 이야기 한 편의 그림. 세부 정보 이야기(`detail-occupation` 등)도
  /// 같은 방식이다.
  static String story(String storyId) => 'story:$storyId';
}

/// [LocalPhotoIndex] 의 열쇠.
String localPhotoKey(String profileId, String slot) => '$profileId/$slot';

abstract interface class LocalPhotos {
  /// 이 기기에서 사진을 둘 수 있는가. 웹 미리보기는 파일을 둘 곳이 없다.
  bool get supported;

  /// 지금 계정의 사진. 열쇠는 [localPhotoKey], 값은 파일 경로다.
  Future<Map<String, String>> load();

  /// [pickedPath] 를 앱 공간에 복사해 그 자리의 사진으로 적고 새 경로를
  /// 돌려준다. 그 자리에 있던 사진은 지운다.
  Future<String> keep(String profileId, String slot, String pickedPath);

  /// 그 자리의 사진과 기록을 지운다. 없으면 그대로다.
  Future<void> remove(String profileId, String slot);

  /// 지금 계정에서 그 어르신의 사진을 모두 지운다.
  Future<void> forgetProfile(String profileId);

  /// 탈퇴한 계정의 사진과 기록을 모두 지운다. 기록이 없는 파일도 함께 지운다.
  Future<void> forgetAccount(String accountId);
}

/// 앱 전용 공간의 `local_photos/` 에 둔다.
///
/// [accountId] 는 지금 로그인한 계정이다. `null` 이면 서버 세션 없이 들어온
/// 경우다(디버그 빌드의 로그인 건너뛰기).
class DeviceLocalPhotos implements LocalPhotos {
  DeviceLocalPhotos({this.accountId, Future<Directory> Function()? directory})
    : _directory = directory ?? _photosDirectory;

  final String? accountId;

  final Future<Directory> Function() _directory;

  static const directoryName = 'local_photos';
  static const fileName = 'local-photos.json';

  static Future<Directory> _photosDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory('${documents.path}/$directoryName');
  }

  /// 기록을 읽고 고쳐 쓰는 일을 한 번에 하나씩 한다. 계정이 바뀌어 보관소를
  /// 새로 만들어도 같은 폴더라 함께 줄 세운다.
  static Future<void> _queue = Future.value();

  static Future<T> _serially<T>(Future<T> Function() task) {
    final result = _queue.then((_) => task());
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  @override
  bool get supported => true;

  @override
  Future<Map<String, String>> load() => _serially(_load);

  @override
  Future<String> keep(String profileId, String slot, String pickedPath) =>
      _serially(() => _keep(profileId, slot, pickedPath));

  @override
  Future<void> remove(String profileId, String slot) =>
      _serially(() => _remove((e) => _isMine(e, profileId, slot)));

  @override
  Future<void> forgetProfile(String profileId) => _serially(
    () => _remove(
      (e) => e['accountId'] == accountId && e['profileId'] == profileId,
    ),
  );

  @override
  Future<void> forgetAccount(String accountId) =>
      _serially(() => _forgetAccount(accountId));

  bool _isMine(Map<String, dynamic> entry, String profileId, String slot) =>
      entry['accountId'] == accountId &&
      entry['profileId'] == profileId &&
      entry['slot'] == slot;

  Future<Map<String, String>> _load() async {
    final directory = await _directory();
    if (!await directory.exists()) return {};
    final entries = await _read(directory);
    return {
      for (final e in entries)
        if (e['accountId'] == accountId &&
            e['profileId'] is String &&
            e['slot'] is String &&
            e['fileName'] is String)
          localPhotoKey(e['profileId'] as String, e['slot'] as String):
              '${directory.path}/${e['fileName']}',
    };
  }

  Future<String> _keep(String profileId, String slot, String pickedPath) async {
    final directory = await _directory();
    await directory.create(recursive: true);

    // 바꿀 때마다 이름이 달라야 화면이 앞 사진을 캐시에서 다시 꺼내지 않는다.
    final stamp = DateTime.now().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    final name = 'local-photo-$stamp${_extensionOf(pickedPath)}';
    final kept = '${directory.path}/$name';
    // 앨범 선택기가 준 파일은 선택기의 임시 사본이다. 복사만 하고 두면 기기가 비운다.
    await File(pickedPath).copy(kept);

    final entries = await _read(directory);
    final replaced = {
      for (final e in entries)
        if (_isMine(e, profileId, slot) && e['fileName'] is String)
          e['fileName'] as String,
    };
    entries
      ..removeWhere((e) => _isMine(e, profileId, slot))
      ..add({
        'accountId': accountId,
        'profileId': profileId,
        'slot': slot,
        'fileName': name,
      });
    await _write(directory, entries);
    await _deleteFiles(directory, replaced);
    return kept;
  }

  /// 알 수 있는 그림 확장자만 남긴다. 모르면 `.jpg` 로 둔다. 디코더는 확장자가
  /// 아니라 파일 내용을 본다.
  static String _extensionOf(String path) {
    final name = path.split(RegExp(r'[/\\]')).last.toLowerCase();
    final dot = name.lastIndexOf('.');
    final ext = dot < 0 ? '' : name.substring(dot);
    const known = {'.jpg', '.jpeg', '.png', '.webp', '.heic', '.heif', '.gif'};
    return known.contains(ext) ? ext : '.jpg';
  }

  /// [matches] 의 기록을 먼저 지우고 파일을 지운다. 기록만 남아 없는 파일을
  /// 가리키지 않게 한다.
  Future<void> _remove(bool Function(Map<String, dynamic>) matches) async {
    final directory = await _directory();
    if (!await directory.exists()) return;
    final entries = await _read(directory);
    final names = {
      for (final e in entries)
        if (matches(e) && e['fileName'] is String) e['fileName'] as String,
    };
    if (names.isEmpty) return;
    entries.removeWhere(matches);
    await _write(directory, entries);
    await _deleteFiles(directory, names);
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
      if (!name.startsWith('local-photo-')) continue;
      if (kept.contains(name)) continue;
      await item.delete();
    }
  }

  Future<void> _deleteFiles(Directory directory, Set<String> names) async {
    for (final name in names) {
      try {
        await File('${directory.path}/$name').delete();
      } on FileSystemException {
        // 이미 없으면 그대로 둔다.
      }
    }
  }

  /// 읽지 못하는 기록은 빈 것으로 본다. 기록 때문에 화면을 막지 않는다.
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

/// 웹 미리보기용이다. 사진을 두지 않고 화면도 고르는 버튼을 보이지 않는다.
class UnsupportedLocalPhotos implements LocalPhotos {
  const UnsupportedLocalPhotos();

  @override
  bool get supported => false;

  @override
  Future<Map<String, String>> load() async => const {};

  @override
  Future<String> keep(String profileId, String slot, String pickedPath) =>
      throw UnsupportedError('이 기기에는 사진을 둘 수 없어요');

  @override
  Future<void> remove(String profileId, String slot) async {}

  @override
  Future<void> forgetProfile(String profileId) async {}

  @override
  Future<void> forgetAccount(String accountId) async {}
}

/// 지금 로그인한 계정의 사진 보관소다. 계정이 바뀌면 새로 만든다.
///
/// 테스트는 이 provider 를 override 해 실제 파일을 건드리지 않는다.
final localPhotosProvider = Provider<LocalPhotos>(
  (ref) => kIsWeb
      ? const UnsupportedLocalPhotos()
      : DeviceLocalPhotos(
          accountId: ref.watch(
            sessionProvider.select((s) => s?.account.accountId),
          ),
        ),
);

/// 지금 계정의 사진 목록. 화면은 [localPhotoKey] 로 찾는다.
///
/// 읽지 못하면 사진이 없는 것으로 보고 기본 그림을 그린다. 고치는 일은 모두
/// 여기를 거쳐 화면이 바로 바뀐다.
class LocalPhotoIndex extends AsyncNotifier<Map<String, String>> {
  @override
  Future<Map<String, String>> build() async {
    try {
      return await ref.watch(localPhotosProvider).load();
    } on Exception {
      return const {};
    }
  }

  LocalPhotos get _store => ref.read(localPhotosProvider);

  Map<String, String> get _current => state.value ?? const {};

  /// 실패하면 그대로 던진다. 화면이 안내한다.
  Future<void> keep(String profileId, String slot, String pickedPath) async {
    final path = await _store.keep(profileId, slot, pickedPath);
    state = AsyncData({..._current, localPhotoKey(profileId, slot): path});
  }

  /// 실패하면 그대로 던진다. 화면이 안내한다.
  Future<void> remove(String profileId, String slot) async {
    await _store.remove(profileId, slot);
    state = AsyncData({..._current}..remove(localPhotoKey(profileId, slot)));
  }

  /// 이야기나 어르신을 지운 뒤에 부른다. 실패해도 지운 일을 되돌리지 않으므로
  /// 삼킨다. 남은 파일은 탈퇴 때 지운다.
  Future<void> forget(String profileId, {String? slot}) async {
    try {
      if (slot == null) {
        await _store.forgetProfile(profileId);
      } else {
        await _store.remove(profileId, slot);
      }
    } on Exception {
      return;
    }
    final prefix = localPhotoKey(profileId, slot ?? '');
    state = AsyncData({
      for (final entry in _current.entries)
        if (slot == null ? !entry.key.startsWith(prefix) : entry.key != prefix)
          entry.key: entry.value,
    });
  }
}

final localPhotoIndexProvider =
    AsyncNotifierProvider<LocalPhotoIndex, Map<String, String>>(
      LocalPhotoIndex.new,
    );

/// 그 자리의 사진 경로. 없거나 아직 읽는 중이면 `null` 이다.
final localPhotoPathProvider = Provider.family<String?, String>(
  (ref, key) => ref.watch(localPhotoIndexProvider.select((s) => s.value?[key])),
);
