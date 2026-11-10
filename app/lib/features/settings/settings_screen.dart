import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/account_api.dart';
import '../../data/api_client.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_states.dart';
import '../auth/auth_providers.dart';
import '../profile_setup/onboarding_tutorial.dart';
import '../profile_setup/setup_controller.dart';
import '../push/push_registration.dart';

/// 설정. 하단 탭 맨 오른쪽의 톱니바퀴로 들어온다.
///
/// 위에서부터 알림 설정, 도움말, 계정 약관 동의 세 구역이다. 도움말은 새록
/// 소개를 다시 띄우고, 계정 약관 동의는 한 단계 들어가
/// ([AppRoutes.settingsConsents]) 확인하고 바꾼다. 동의는 어르신마다가 아니라
/// 보호자 계정에 한 번 받으므로 어르신이 없어도 열린다. 아래에 로그아웃과
/// 회원탈퇴를 둔다.
///
/// 계정 정보를 읽지 못해도 로그아웃은 둔다. 세션이 만료돼 다시 시도해도 같은
/// 오류가 나면 로그아웃한 뒤 다시 로그인할 길이 있어야 한다.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider);
    return Scaffold(
      backgroundColor: HomeColors.background,
      appBar: const AppTopBar(
        backgroundColor: HomeColors.background,
        title: '설정',
      ),
      body: account.when(
        // 스위치는 서버의 동의를 보여주므로, 저장 뒤 다시 읽는 중에는 이전 값을
        // 보여주지 않고 기다린다.
        skipLoadingOnRefresh: false,
        loading: () => const LoadingView(),
        error: (error, _) => Column(
          children: [
            Expanded(
              child: ErrorStateView(
                message: '계정 정보를 불러오지 못했어요.',
                onRetry: () => ref.invalidate(accountProvider),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(AppSpacing.screen),
              child: _SignOutLink(),
            ),
          ],
        ),
        data: (account) => _Body(account: account),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.account});

  final Account account;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  static const _pushKey = 'pushNotification';

  /// 서버에 저장하는 중이다. 같은 요청을 두 번 보내지 않는다.
  bool _saving = false;

  /// 서버에 저장된 알림 수신 동의.
  bool get _pushAgreed => widget.account.consent[_pushKey]?.granted ?? false;

  /// 알림 스위치. 서버에 저장된 알림 수신 동의(1-6 `pushNotification`)다.
  ///
  /// 리포트 완료 알림은 이 동의로만 정한다. 동의가 있으면 앱이 기기를 등록하고
  /// (`push_registration.dart`), 동의를 거두면 서버가 그 계정의 기기 등록을 같은
  /// 트랜잭션에서 지운다. 그래서 스위치는 따로 기억하지 않고 이 동의를 바로
  /// 저장한다. 계정 약관 동의 화면에서 이 동의를 저장해도 따라 바뀐다.
  bool get _alertOn => _offlineAlert ?? _pushAgreed;

  /// 로그인하지 않은 목 모드에서 바꾼 스위치. 서버가 없어 화면에서만 기억한다.
  bool? _offlineAlert;

  /// 동의 없이 알림을 켜려 했다. 빨간 안내를 보이고, 계정 약관 동의에 들어가면
  /// 알림 수신 동의 줄을 강조한다.
  bool _needsConsent = false;

  // ── 알림 설정 ──────────────────────────────────

  /// 스위치를 켜고 끈다. 켤 때는 알림 수신 동의가 저장돼 있어야 한다. 끄면 그
  /// 동의를 거둔다. 어느 쪽이든 동의를 바로 저장한다(1-6).
  void _setAlert(bool on) {
    if (_saving) return;
    if (on && !_pushAgreed) {
      setState(() => _needsConsent = true);
      return;
    }
    unawaited(_saveAlert(on));
  }

  /// 알림 수신 동의만 서버에 저장한다. 다른 동의는 계정 약관 동의에서 저장한다.
  Future<void> _saveAlert(bool on) async {
    if (ref.read(sessionProvider) == null) {
      // 로그인하지 않은 목 모드는 서버도 알림도 없다. 화면에서만 바꾼다.
      setState(() => _offlineAlert = on);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await ref.read(accountApiProvider).updateConsents({_pushKey: on});
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      // 끄지 못했으면 스위치는 서버 값 그대로 켜져 있다. 알림은 계속 온다.
      setState(() => _saving = false);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(consentFailureMessage(failure))));
      return;
    }
    // 서버의 새 동의를 다시 읽는다. 기기 등록도 이 값을 따라 바뀐다.
    container.invalidate(accountProvider);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(on ? '알림을 켰어요.' : '알림을 껐어요.')));
    if (mounted) setState(() => _saving = false);
  }

  void _openConsents() => context.push(
    AppRoutes.settingsConsents,
    extra: _needsConsent && !_pushAgreed,
  );

  @override
  Widget build(BuildContext context) {
    return ScreenBody(
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.lg),

          // ── 알림 설정
          // 제목과 안내 글을 한 묶음으로 두고 스위치는 그 오른쪽 가운데에 둔다.
          // 제목과 안내 글 사이는 아래 구역들과 같은 간격이고, 스위치의 누름
          // 영역(48)이 그 간격을 벌리지 않는다.
          MergeSemantics(
            child: Row(
              children: [
                const Expanded(
                  child: _SectionText(
                    title: '알림 설정',
                    sub: '만남 리포트가 완성되면 알려드려요.',
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Switch(
                  value: _alertOn,
                  onChanged: _saving ? null : _setAlert,
                  activeTrackColor: HomeColors.accent,
                ),
              ],
            ),
          ),
          if (_needsConsent && !_pushAgreed) ...[
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              liveRegion: true,
              child: Text(
                '아래 계정 약관 동의에서 알림 수신 동의에 체크하고 저장해야 알림을 켤 수 있어요.',
                style: AppTypography.sub.copyWith(color: AppColors.danger),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.section),

          // ── 도움말
          _MenuRow(
            title: '도움말',
            sub: '새록 소개를 다시 볼 수 있어요.',
            onTap: () => showOnboardingTutorial(context, replay: true),
          ),
          const SizedBox(height: AppSpacing.section),

          // ── 계정 약관 동의
          // 동의는 어르신마다가 아니라 보호자 계정에 한 번 받는다.
          _MenuRow(
            title: '계정 약관 동의',
            sub: '함께하는 모든 분에게 똑같이 적용돼요.',
            onTap: _openConsents,
          ),
          const SizedBox(height: AppSpacing.section),

          // 로그아웃과 회원탈퇴를 가운데 점으로 나눠 한 줄에 놓는다. 글자를 키워 한
          // 줄에 들어가지 않으면 다음 줄로 넘긴다.
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.xs,
            children: [
              const _SignOutLink(),
              // 나누는 표시라 화면 읽기에서는 뺀다.
              const ExcludeSemantics(
                child: Text(
                  '·',
                  style: TextStyle(fontSize: 17, color: AppColors.textSub),
                ),
              ),
              AppTextButton(
                label: '회원탈퇴',
                onPressed: () => context.push(AppRoutes.profileDelete),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

/// 구역 제목과 그 아래 작은 회색 글.
class _SectionText extends StatelessWidget {
  const _SectionText({required this.title, required this.sub});

  final String title;
  final String sub;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: AppTypography.sectionTitle),
        const SizedBox(height: AppSpacing.sm),
        Text(sub, style: AppTypography.sub),
      ],
    );
  }
}

/// 눌러서 들어가는 구역. 제목과 글 오른쪽 가운데에 꺾쇠를 둔다. 알림 설정의
/// 스위치와 같은 자리다.
class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.title, required this.sub, required this.onTap});

  final String title;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Row(
          children: [
            Expanded(
              child: _SectionText(title: title, sub: sub),
            ),
            const SizedBox(width: AppSpacing.md),
            // 스위치의 누름 영역(48)과 같은 폭에 맞춰 오른쪽 선을 맞춘다.
            const SizedBox(
              width: AppSizes.minTouch,
              height: AppSizes.minTouch,
              child: Icon(Icons.chevron_right, color: AppColors.textSub),
            ),
          ],
        ),
      ),
    );
  }
}

/// 로그아웃. 단말 세션과 구글 쪽을 지우고 서버에서도 세션을 폐기한다.
/// 회원탈퇴와 같은 밑줄 글자로 둔다.
///
/// 서버에 닿지 못해도 로그아웃은 된다(`SessionNotifier.signOut`).
class _SignOutLink extends ConsumerStatefulWidget {
  const _SignOutLink();

  @override
  ConsumerState<_SignOutLink> createState() => _SignOutLinkState();
}

class _SignOutLinkState extends ConsumerState<_SignOutLink> {
  bool _busy = false;

  /// 세션을 지우면 계정 정보가 바뀌어 설정 화면이 다시 그려지고, 이 버튼은
  /// 서버 응답을 기다리는 동안 사라질 수 있다. 그래도 한 번의 로그아웃으로
  /// 로그인 화면까지 가도록 필요한 것을 미리 잡아 둔다.
  Future<void> _signOut() async {
    setState(() => _busy = true);
    final container = ProviderScope.containerOf(context, listen: false);
    final router = GoRouter.of(context);
    // 세션이 남아 있을 때 이 기기의 푸시 등록을 서버에서 지운다(1-8). 짧게만
    // 기다리고 실패해도 로그아웃을 이어간다.
    await container.read(pushRegistrationProvider.notifier).releaseForSignOut();
    await container.read(sessionProvider.notifier).signOut();
    forgetCareProfilesIn(container);
    router.go(AppRoutes.signIn);
  }

  @override
  Widget build(BuildContext context) {
    return AppTextButton(
      label: _busy ? '로그아웃하는 중이에요' : '로그아웃',
      onPressed: _busy ? null : _signOut,
    );
  }
}
