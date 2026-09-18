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
import 'google_sign_in_button.dart';

/// A-2 로그인.
///
/// 구글 로그인만 서버에 붙어 있다. 아이디와 비밀번호는 아직 인증이 붙지 않아,
/// 채우면 홈으로 넘어가는 목 화면이다.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _loginId = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  /// 구글 로그인을 기다리는 중이다.
  bool _busy = false;

  AuthFailure? _failure;

  bool get _canSubmit =>
      _loginId.text.trim().isNotEmpty && _password.text.isNotEmpty;

  @override
  void dispose() {
    _loginId.dispose();
    _password.dispose();
    super.dispose();
  }

  /// 구글 계정으로 로그인한다.
  ///
  /// 계정이 이미 있으면 바로 홈으로 가고, 없으면 동의 화면으로 넘긴다. 구글
  /// 인증만으로는 계정이 만들어지지 않는다(ADR-007).
  Future<void> _signInWithGoogle() async {
    setState(() {
      _busy = true;
      _failure = null;
    });

    try {
      final idToken = await ref.read(googleAuthenticatorProvider).idToken();
      // 사용자가 그만두었다. 실패가 아니므로 아무것도 띄우지 않는다.
      if (idToken == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }

      final result = await ref.read(authApiProvider).signInWithGoogle(idToken);
      if (!mounted) return;

      switch (result) {
        case AuthenticatedResult():
          ref.read(sessionProvider.notifier).start(result);
          context.go(AppRoutes.home);
        case ConsentRequiredResult():
          setState(() => _busy = false);
          context.push(AppRoutes.googleConsent, extra: result);
      }
    } on AuthFailure catch (failure) {
      logAuthFailure(failure);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = failure;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final failure = _failure;

    return Scaffold(
      body: ScreenBody(
        scrollable: true,
        // 로그인 버튼과 가입 안내를 아래에 고정하지 않고 본문과 함께 흘려보낸다.
        // 고정 영역이 168dp 를 가져가서, 화면이 작은 기기에 키보드가 올라오면
        // 비밀번호 칸이 스크롤 영역 밖으로 밀렸다.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.xxxl),
            const Text('로그인', style: AppTypography.screenTitle),
            const SizedBox(height: AppSpacing.section),
            AppTextField(
              label: '아이디',
              controller: _loginId,
              hintText: '아이디를 입력해주세요',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.xl),
            AppTextField(
              label: '비밀번호',
              controller: _password,
              hintText: '비밀번호를 입력해주세요',
              obscureText: _obscure,
              onChanged: (_) => setState(() {}),
              suffix: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: AppColors.textSub,
                ),
                tooltip: _obscure ? '비밀번호 보기' : '비밀번호 가리기',
              ),
            ),

            const SizedBox(height: AppSpacing.xxl),

            PrimaryButton(
              label: '로그인',
              onPressed: _canSubmit ? () => context.go(AppRoutes.home) : null,
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('계정이 없으신가요?', style: AppTypography.sub),
                const SizedBox(width: AppSpacing.sm),
                AppTextButton(
                  label: '회원가입',
                  onPressed: () => context.push(AppRoutes.signup),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.xxl),
            const _OrDivider(),
            const SizedBox(height: AppSpacing.xl),

            if (failure != null) ...[
              AuthNotice(message: authFailureMessage(failure)),
              const SizedBox(height: AppSpacing.xl),
            ],

            Center(
              child: GoogleSignInButton(
                onPressed: _busy ? null : _signInWithGoogle,
                busy: _busy,
              ),
            ),

            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: Divider()),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text('또는', style: AppTypography.sub),
        ),
        Expanded(child: Divider()),
      ],
    );
  }
}
