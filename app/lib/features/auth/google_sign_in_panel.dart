import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/auth_api.dart';
import '../../design/tokens.dart';
import 'auth_messages.dart';
import 'auth_providers.dart';
import 'consent_form.dart';
import 'google_sign_in_button.dart';

/// 구글 로그인 버튼과 실패 안내다. 스플래시(A-1)가 로그인이 필요할 때 보여준다.
///
/// 따로 있던 로그인 화면(A-2)을 스플래시에 합치면서 화면이 아니라 조각으로 뒀다.
/// 구글 로그인 하나만 둔다. 아이디와 비밀번호는 받지 않는다(ADR-007).
class GoogleSignInPanel extends ConsumerStatefulWidget {
  const GoogleSignInPanel({super.key});

  @override
  ConsumerState<GoogleSignInPanel> createState() => _GoogleSignInPanelState();
}

class _GoogleSignInPanelState extends ConsumerState<GoogleSignInPanel> {
  /// 구글 로그인을 기다리는 중이다.
  bool _busy = false;

  AuthFailure? _failure;

  /// 구글 계정으로 로그인한다.
  ///
  /// 계정이 이미 있으면 바로 홈으로 가고, 없으면 동의 화면으로 넘긴다. 구글
  /// 인증만으로는 계정이 만들어지지 않는다(ADR-007).
  Future<void> _signInWithGoogle() async {
    // 구글 설정이 준비되기 전까지 화면을 확인하기 위한 임시 길이다.
    if (ref.read(skipGoogleLoginProvider)) {
      context.go(AppRoutes.profileCreate);
      return;
    }

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
          // 보관을 마친 뒤 넘어간다. 먼저 넘어가면 앱이 곧바로 꺼졌을 때
          // 세션이 남지 않는다.
          await ref.read(sessionProvider.notifier).start(result);
          if (!mounted) return;
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
    final skipping = ref.watch(skipGoogleLoginProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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

        if (skipping) ...[
          const SizedBox(height: AppSpacing.lg),
          const Text(
            '개발용: 구글 로그인 설정이 없어 누르면 바로 정보 입력으로 넘어가요.',
            style: AppTypography.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
