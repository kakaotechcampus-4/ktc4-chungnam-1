/// 구글 로그인 뒤 받는 필수 동의 화면.
///
/// `POST /auth/google` 이 `consentRequired` 를 준 다음 자리다. 이 시점에는 아직
/// 계정이 없고, 여기서 필수 동의를 제출해야 계정과 동의 이력이 함께 만들어진다
/// (ADR-007). 중간에 나가면 계정은 남지 않는다.
///
/// 보여주는 문구는 A-3 회원가입과 같은 `consent_terms.dart` 를 쓴다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/auth_api.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_text_field.dart';
import 'auth_messages.dart';
import 'auth_providers.dart';
import 'consent_form.dart';
import 'consent_terms.dart';

class GoogleConsentScreen extends ConsumerStatefulWidget {
  const GoogleConsentScreen({required this.pending, super.key});

  /// `POST /auth/google` 이 준 등록 정보다. 저장하지 않고 이 화면에서만 쓴다.
  final ConsentRequiredResult pending;

  @override
  ConsumerState<GoogleConsentScreen> createState() =>
      _GoogleConsentScreenState();
}

class _GoogleConsentScreenState extends ConsumerState<GoogleConsentScreen> {
  final _name = TextEditingController();
  final _agreed = <String>{};

  bool _submitting = false;
  AuthFailure? _failure;

  /// 필수 동의를 하지 않은 채 제출을 눌렀다.
  bool _missingShown = false;

  /// 앱이 보여주는 약관과 서버가 제시한 약관이 다르다.
  ///
  /// 이때는 보여주지 않은 문구에 동의를 받는 셈이라 제출하지 않는다.
  bool get _versionMismatch => widget.pending.consentVersion != consentVersion;

  bool get _requiredAgreed => consentTerms
      .where((term) => term.required)
      .every((term) => _agreed.contains(term.key));

  bool get _allAgreed => _agreed.length == consentTerms.length;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _toggleAll(bool? value) {
    setState(() {
      if (value ?? false) {
        _agreed.addAll(consentTerms.map((t) => t.key));
      } else {
        _agreed.clear();
      }
    });
  }

  void _toggle(String key, bool? value) {
    setState(() {
      if (value ?? false) {
        _agreed.add(key);
      } else {
        _agreed.remove(key);
      }
      if (_requiredAgreed) _missingShown = false;
    });
  }

  Future<void> _submit() async {
    if (!_requiredAgreed) {
      setState(() => _missingShown = true);
      return;
    }

    setState(() {
      _submitting = true;
      _failure = null;
    });

    try {
      final result = await ref
          .read(authApiProvider)
          .submitConsent(
            registrationToken: widget.pending.registrationToken,
            consentVersion: widget.pending.consentVersion,
            // 계약의 네 항목을 모두 보낸다. 고르지 않은 것은 거부로 보낸다.
            consents: {
              for (final term in consentTerms)
                term.key: _agreed.contains(term.key),
            },
            displayName: _name.text,
          );
      ref.read(sessionProvider.notifier).start(result);
      if (!mounted) return;
      // 방금 만들어진 계정이라 프로필부터 만든다.
      context.go(AppRoutes.onboarding);
    } on AuthFailure catch (failure) {
      logAuthFailure(failure);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _failure = failure;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final failure = _failure;
    final restart =
        _versionMismatch || (failure != null && needsRestart(failure));

    return Scaffold(
      appBar: const AppTopBar(),
      body: ScreenBody(
        scrollable: true,
        // A-3 과 같은 이유로 버튼을 아래에 고정하지 않는다. 약관까지 읽고
        // 내려와야 누를 수 있어 버튼이 늘 보일 이유가 없다.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.sm),
            const Text('약관 동의', style: AppTypography.screenTitle),
            const SizedBox(height: AppSpacing.md),
            const Text(
              '구글 계정을 확인했어요.\n아래 항목에 동의하면 새록 계정이 만들어져요.',
              style: AppTypography.sub,
            ),
            const SizedBox(height: AppSpacing.section),

            if (_versionMismatch) ...[
              const AuthNotice(message: '약관이 새로 바뀌었어요. 앱을 업데이트한 뒤 다시 시도해주세요.'),
              const SizedBox(height: AppSpacing.xl),
            ] else ...[
              AppTextField(
                label: '이름',
                controller: _name,
                hintText: '보호자분의 이름을 입력해주세요',
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                '새록이 보호자님을 부를 때 써요. 비워두어도 괜찮아요.',
                style: AppTypography.caption,
              ),
              const SizedBox(height: AppSpacing.section),

              const Text('약관 동의', style: AppTypography.sectionTitle),
              const SizedBox(height: AppSpacing.lg),

              for (final term in consentTerms) ...[
                ConsentRow(
                  term: term,
                  checked: _agreed.contains(term.key),
                  onChanged: (value) => _toggle(term.key, value),
                  onDetails: () => showConsentDetails(context, term),
                ),
                const SizedBox(height: AppSpacing.xs),
              ],

              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Divider(),
              ),

              InkWell(
                onTap: () => _toggleAll(!_allAgreed),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _allAgreed,
                        onChanged: _toggleAll,
                        activeColor: AppColors.ink,
                        side: const BorderSide(color: AppColors.line, width: 2),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      const Text('전체 동의', style: AppTypography.bodyStrong),
                    ],
                  ),
                ),
              ),

              if (_missingShown && !_requiredAgreed) ...[
                const SizedBox(height: AppSpacing.lg),
                const AuthNotice(message: '필수 항목에 모두 동의해야 가입할 수 있어요.'),
              ],

              if (failure != null) ...[
                const SizedBox(height: AppSpacing.lg),
                AuthNotice(message: authFailureMessage(failure)),
              ],

              const SizedBox(height: AppSpacing.xxl),

              PrimaryButton(
                label: _submitting ? '가입하는 중이에요' : '동의하고 시작하기',
                onPressed: _submitting ? null : _submit,
              ),
            ],

            if (restart) ...[
              const SizedBox(height: AppSpacing.lg),
              SecondaryButton(
                label: '로그인으로 돌아가기',
                onPressed: () => context.go(AppRoutes.login),
              ),
            ],

            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
    );
  }
}
