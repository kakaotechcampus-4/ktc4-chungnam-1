/// AI 사진 분석에 동의하지 않은 계정이 사진을 올리기 직전에 동의를 묻는 시트를 띄운다.
///
/// 사진을 올리는 데에는 동의가 필요 없다. 동의하지 않으면 사진은 분석 없이
/// 저장되고, 보호자가 직접 쓴 설명만 대화 카드에 쓴다(#261). 그래서 어느 쪽을
/// 골라도 사진은 올린다. 문구는 가입 화면과 같은 [consentTerms] 의
/// `photoAnalysis` 항목을 그대로 쓴다(새로 쓰지 않는다).
///
/// - 동의하고 올리기: 1-6 으로 동의를 저장하고 올린다.
/// - 동의하지 않고 올리기, 시트를 그냥 닫기: 거절이다. 지금까지처럼 분석 없이 올린다.
/// - 다시 띄우지 않기: 거절하고, 이 휴대폰에서 그 계정에는 다시 묻지 않는다.
///
/// 거절하면 앱이 켜져 있는 동안 다시 묻지 않는다. 동의는 설정의 계정 약관
/// 동의에서 언제든 바꿀 수 있다.
///
/// 2026-11-08 PM 결정. 그 전에는 동의하지 않은 계정이 사진을 올려도 묻지 않고
/// 갤러리 안내 문구만 보였다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/account_api.dart';
import '../../data/api_client.dart';
import '../../data/providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../auth/auth_providers.dart';
import '../auth/consent_terms.dart';

/// 이번에 앱을 켠 뒤 사진 분석 동의를 이미 물었는지.
final photoConsentAskedProvider = NotifierProvider<PhotoConsentAsked, bool>(
  PhotoConsentAsked.new,
);

class PhotoConsentAsked extends Notifier<bool> {
  @override
  bool build() => false;

  void mark() => state = true;
}

/// 계정을 아직 읽지 않았을 때 기다리는 한도. 넘기면 묻지 않고 올린다.
const _accountWait = Duration(seconds: 5);

/// 단말 저장소를 읽는 한도. 넘기면 묻는다(다시 띄우지 않기를 모르는 것과 같다).
const _storeWait = Duration(seconds: 2);

/// "다시 띄우지 않기"를 계정마다 이 휴대폰에 기억한다. 값은 켜짐 여부뿐이다.
abstract interface class PhotoConsentPromptStore {
  /// [accountId] 가 다시 띄우지 않기를 골랐는지.
  Future<bool> muted(String accountId);

  /// [accountId] 에 다시 띄우지 않는다.
  Future<void> mute(String accountId);
}

/// 단말의 보안 저장소에 둔다. 세션, 관계 값과 같은 곳이다.
class SecurePhotoConsentPromptStore implements PhotoConsentPromptStore {
  SecurePhotoConsentPromptStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  static String _keyOf(String accountId) =>
      'saerok.photo_consent_prompt.muted.$accountId';

  @override
  Future<bool> muted(String accountId) async {
    try {
      return await _storage.read(key: _keyOf(accountId)) == 'true';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> mute(String accountId) async {
    try {
      await _storage.write(key: _keyOf(accountId), value: 'true');
    } catch (_) {
      // 기억하지 못하면 다음에 앱을 켰을 때 한 번 더 물을 뿐이다.
    }
  }
}

final photoConsentPromptStoreProvider = Provider<PhotoConsentPromptStore>(
  (ref) => SecurePhotoConsentPromptStore(),
);

enum _Choice { agree, decline, mute }

ConsentTerm get _term =>
    consentTerms.firstWhere((term) => term.key == 'photoAnalysis');

/// 사진을 올리기 직전에 부른다. 끝나면 어느 쪽을 골랐든 사진을 올린다.
///
/// 로그인하지 않았거나, 이미 동의했거나, 이번에 이미 물었거나, 다시 띄우지 않기를
/// 골랐거나, 계정의 동의 상태를 알 수 없으면 묻지 않는다. 동의를 저장하지
/// 못하면 알리고, 사진은 동의 없이 올린 것과 같다.
Future<void> askPhotoAnalysisBeforeUpload(
  BuildContext context,
  WidgetRef ref,
) async {
  final session = ref.read(sessionProvider);
  if (session == null) return;
  if (ref.read(photoConsentAskedProvider)) return;
  final wanted = await _photoAnalysisWanted(ref);
  if (wanted != false || !context.mounted) return;
  final accountId = session.account.accountId;
  final store = ref.read(photoConsentPromptStoreProvider);
  final muted = await store
      .muted(accountId)
      .timeout(_storeWait, onTimeout: () => false);
  if (muted || !context.mounted) return;

  final choice = await showModalBottomSheet<_Choice>(
    context: context,
    backgroundColor: AppColors.background,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
    ),
    builder: (context) => const _PhotoConsentSheet(),
  );
  // 그냥 닫아도 거절이다.
  ref.read(photoConsentAskedProvider.notifier).mark();
  if (choice == _Choice.mute) unawaited(store.mute(accountId));
  if (choice != _Choice.agree || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  // 저장을 기다리는 동안 화면이 바뀌어도 계정을 다시 읽도록 미리 잡아 둔다.
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    await ref.read(accountApiProvider).updateConsents({'photoAnalysis': true});
  } on ApiFailure catch (failure) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(consentFailureMessage(failure))));
    return;
  }
  // 갤러리의 "분석 중" 표시와 설명 기다리기가 이 값을 따른다(#261).
  container.invalidate(accountProvider);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(content: Text('AI 사진 분석에 동의했어요. 사진 설명을 만들어 드려요.')),
    );
}

/// 계정의 사진 분석 동의. 아직 읽지 않았으면 잠깐 기다린다. 모르면 `null`.
Future<bool?> _photoAnalysisWanted(WidgetRef ref) async {
  final known = ref.read(photoAnalysisWantedProvider);
  if (known != null) return known;
  try {
    final account = await ref
        .read(accountProvider.future)
        .timeout(_accountWait);
    return account.consent['photoAnalysis']?.granted ?? false;
  } on Object {
    return null;
  }
}

class _PhotoConsentSheet extends StatelessWidget {
  const _PhotoConsentSheet();

  @override
  Widget build(BuildContext context) {
    final term = _term;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen,
            0,
            AppSpacing.screen,
            AppSpacing.section,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(term.label, style: AppTypography.sectionTitle),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(term.statement, style: AppTypography.body),
                      const SizedBox(height: AppSpacing.xl),
                      for (final line in term.details) ...[
                        Text(line, style: AppTypography.sub),
                        const SizedBox(height: AppSpacing.md),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                color: HomeColors.accent,
                loadingColor: HomeColors.accentLoading,
                label: '동의하고 올리기',
                onPressed: () => Navigator.of(context).pop(_Choice.agree),
              ),
              const SizedBox(height: AppSpacing.sm),
              SecondaryButton(
                borderColor: HomeColors.outline,
                label: '동의하지 않고 올리기',
                onPressed: () => Navigator.of(context).pop(_Choice.decline),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(_Choice.mute),
                child: Text('다시 띄우지 않기', style: AppTypography.sub),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
