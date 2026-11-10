/// 등록하다 멈춘 세부 정보의 답을 계정과 서버 프로필마다 단말에 둔다.
///
/// 하시던 일, 고향, 취미, 가족 네 항목은 사진 단계를 마칠 때 서버에 저장한다
/// (2-4). 그 전에 앱이 꺼지면 항목마다 길게 말한 답이 사라져, 입력하는 동안 여기
/// 초안을 둔다(2026-11-10 UX 점검 15). 다시 열면 서버의 기본 정보에 이 초안을
/// 더해 멈춘 단계부터 이어서 입력한다. 등록을 마치거나 그만두면 지운다.
///
/// 보관하는 값은 글로 된 답, 가 본 가장 먼 단계, 올린 사진 수다. 녹음 파일과
/// 고른 사진의 경로, 기본 정보는 두지 않는다. 기본 정보는 서버에 이미 있다. 화면과
/// 테스트는 [SetupDraftStore] 만 보고 저장소를 직접 부르지 않는다(`ADR-005` 의
/// 주입 방식과 같다).
///
/// 단말 보관 범위는 아직 정해지지 않아(`docs/architecture/README.md`) 개발과
/// 테스트를 위한 가정이다. 저장한 값은 로그에 남기지 않는다(`CLAUDE.md`).
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 단말에 둔 입력 초안 하나다.
class SavedSetupDraft {
  const SavedSetupDraft({
    this.facts = const {},
    this.reachedIndex = 0,
    this.uploadedPhotos = 0,
  });

  /// `LifeFact.category` 별로 적거나 말해 얻은 글. 건너뛴 항목은 없다.
  final Map<String, String> facts;

  /// 가 본 가장 먼 단계(`SetupState.reachedIndex`). 다시 열 때 이 단계부터 연다.
  final int reachedIndex;

  /// 이 프로필에 이미 올린 사진 수. 다시 열면 이만큼 덜 고르게 한다.
  final int uploadedPhotos;

  String encode() => jsonEncode({
    'version': 1,
    'facts': facts,
    'reachedIndex': reachedIndex,
    'uploadedPhotos': uploadedPhotos,
  });

  /// 읽지 못하는 값이면 `null` 이다. 앱을 멈출 일은 아니다.
  static SavedSetupDraft? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, Object?>) return null;
      final facts = json['facts'];
      return SavedSetupDraft(
        facts: {
          if (facts is Map)
            for (final MapEntry(:key, :value) in facts.entries)
              if (key is String && value is String && value.trim().isNotEmpty)
                key: value,
        },
        reachedIndex: _intOf(json['reachedIndex']),
        uploadedPhotos: _intOf(json['uploadedPhotos']),
      );
    } on FormatException {
      return null;
    }
  }

  static int _intOf(Object? value) => value is int && value > 0 ? value : 0;
}

abstract interface class SetupDraftStore {
  /// [accountId] 의 서버 프로필 [profileId] 에 남긴 초안이다. 없거나 읽을 수
  /// 없으면 `null` 이다.
  Future<SavedSetupDraft?> read(String accountId, String profileId);

  Future<void> write(String accountId, String profileId, SavedSetupDraft draft);

  /// 등록을 마쳤거나 그만두었을 때 쓴다.
  Future<void> clear(String accountId, String profileId);

  /// 계정을 탈퇴했을 때 그 계정의 초안을 모두 지운다.
  Future<void> clearAccount(String accountId);
}

/// 단말의 보안 저장소에 둔다. 세션, 고른 분, 관계와 같은 곳이다.
class SecureSetupDraftStore implements SetupDraftStore {
  SecureSetupDraftStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  /// 계정마다 앞부분을 나눠 다른 계정의 초안을 읽지 않는다. 프로필마다 키를
  /// 따로 두어 서로 덮지 않는다.
  static String _prefixOf(String accountId) =>
      'saerok.profile.setupDraft.$accountId.';

  static String _keyOf(String accountId, String profileId) =>
      '${_prefixOf(accountId)}$profileId';

  @override
  Future<SavedSetupDraft?> read(String accountId, String profileId) async {
    try {
      return SavedSetupDraft.decode(
        await _storage.read(key: _keyOf(accountId, profileId)),
      );
    } catch (_) {
      // 읽지 못하면 서버 값으로 연다. 앱을 멈출 일은 아니다.
      return null;
    }
  }

  @override
  Future<void> write(
    String accountId,
    String profileId,
    SavedSetupDraft draft,
  ) async {
    try {
      await _storage.write(
        key: _keyOf(accountId, profileId),
        value: draft.encode(),
      );
    } catch (_) {
      // 남기지 못해도 지금 입력은 그대로 이어진다. 앱이 꺼지면 서버 값으로 열릴
      // 뿐이다.
    }
  }

  @override
  Future<void> clear(String accountId, String profileId) async {
    try {
      await _storage.delete(key: _keyOf(accountId, profileId));
    } catch (_) {
      // 남은 초안은 그 프로필을 이어서 입력할 때만 읽힌다.
    }
  }

  @override
  Future<void> clearAccount(String accountId) async {
    final prefix = _prefixOf(accountId);
    try {
      final all = await _storage.readAll();
      for (final key in all.keys.where((k) => k.startsWith(prefix))) {
        await _storage.delete(key: key);
      }
    } catch (_) {
      // 남은 값은 그 계정으로 다시 로그인해야만 읽힌다.
    }
  }
}

final setupDraftStoreProvider = Provider<SetupDraftStore>(
  (ref) => SecureSetupDraftStore(),
);
