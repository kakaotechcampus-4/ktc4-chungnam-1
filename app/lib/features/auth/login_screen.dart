import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_text_field.dart';

/// A-2 로그인.
///
/// 인증은 아직 붙지 않았다. 아이디와 비밀번호를 채우면 홈으로 넘어간다.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _loginId = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  bool get _canSubmit =>
      _loginId.text.trim().isNotEmpty && _password.text.isNotEmpty;

  @override
  void dispose() {
    _loginId.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ScreenBody(
        scrollable: true,
        bottom: Column(
          children: [
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
          ],
        ),
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
                  _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: AppColors.textSub,
                ),
                tooltip: _obscure ? '비밀번호 보기' : '비밀번호 가리기',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
