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
import '../auth/consent_form.dart';
import '../auth/consent_terms.dart';
import '../profile_setup/setup_controller.dart';
import '../push/push_registration.dart';

/// 리포트 완성 알림을 켰는지. `null` 이면 아직 고르지 않아 알림 수신 동의를
/// 따른다.
///
/// 서버에 알림 설정을 저장하는 API 가 없고 앱은 아직 알림을 보내지 않는다.
/// 그래서 앱을 켜 둔 동안만 기억한다. 어디에 저장할지는 PM, BE 와 정한다.
final reportAlertOnProvider = NotifierProvider<ReportAlertOn, bool?>(
  ReportAlertOn.new,
);

class ReportAlertOn extends Notifier<bool?> {
  @override
  bool? build() => null;

  // ignore: use_setters_to_change_properties
  void set(bool on) => state = on;
}

/// 설정. 하단 탭 맨 오른쪽의 톱니바퀴로 들어온다.
///
/// 알림 설정과 계정 약관 동의 두 구역이다. 동의는 어르신마다가 아니라 보호자
/// 계정에 한 번 받으므로 어르신이 없어도 열린다. 아래에 저장하기, 로그아웃,
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
        // 체크 상태는 처음 받은 값에서 시작하므로, 저장 뒤 다시 읽는 중에는
        // 이전 값을 보여주지 않고 기다린다.
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

class _BodyState extends ConsumerState<_Body>
    with SingleTickerProviderStateMixin {
  static const _pushKey = 'pushNotification';

  /// 지금 화면에서 동의한 항목의 키. 계정의 동의에서 시작한다.
  late final Set<String> _agreed = {
    for (final entry in widget.account.consent.entries)
      if (entry.value.granted) entry.key,
  };

  /// 서버에 저장하는 중이다. 같은 요청을 두 번 보내지 않는다.
  bool _saving = false;

  /// 동의 없이 알림을 켜려 했다. 빨간 안내와 동의 줄 강조를 보인다.
  bool _needsConsent = false;

  /// 알림 수신 동의 줄. 안내할 때 보이는 자리로 끌어온다.
  final _pushRowKey = GlobalKey();

  /// 알림 수신 동의 줄을 깜빡인다.
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  bool get _pushAgreed => _agreed.contains(_pushKey);

  bool get _requiredAgreed => consentTerms
      .where((term) => term.required)
      .every((term) => _agreed.contains(term.key));

  bool get _allAgreed => _agreed.length == consentTerms.length;

  /// 처음 값과 달라진 선택 동의. 필수 동의는 1-6 으로 바꿀 수 없어 담지 않는다.
  Map<String, bool> get _changedOptional => {
    for (final term in consentTerms)
      if (!term.required &&
          _agreed.contains(term.key) !=
              (widget.account.consent[term.key]?.granted ?? false))
        term.key: _agreed.contains(term.key),
  };

  // ── 알림 설정 ──────────────────────────────────

  void _setAlert(bool on) {
    if (on && !_pushAgreed) {
      setState(() => _needsConsent = true);
      unawaited(_pointAtConsent());
      return;
    }
    ref.read(reportAlertOnProvider.notifier).set(on);
  }

  /// 알림 수신 동의 줄을 보이는 자리로 끌어와 두 번 깜빡인다.
  Future<void> _pointAtConsent() async {
    final row = _pushRowKey.currentContext;
    if (row != null) {
      unawaited(
        Scrollable.ensureVisible(
          row,
          alignment: 0.4,
          duration: const Duration(milliseconds: 300),
        ),
      );
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _flash.value = 1;
      return;
    }
    try {
      for (var i = 0; i < 2; i++) {
        await _flash.forward(from: 0).orCancel;
        await _flash.reverse().orCancel;
      }
    } on TickerCanceled {
      // 화면을 떠났다.
    }
  }

  // ── 동의 ──────────────────────────────────────

  void _toggle(String key, bool? value) {
    setState(() {
      if (value ?? false) {
        _agreed.add(key);
      } else {
        _agreed.remove(key);
      }
      if (_pushAgreed) _needsConsent = false;
    });
    if (key == _pushKey) _syncAlert();
  }

  /// 알림 수신 동의를 누르면 알림 스위치도 같이 켜고 끈다.
  void _syncAlert() =>
      ref.read(reportAlertOnProvider.notifier).set(_pushAgreed);

  void _toggleAll(bool? value) {
    setState(() {
      if (value ?? false) {
        _agreed.addAll(consentTerms.map((t) => t.key));
      } else {
        _agreed.clear();
      }
      if (_pushAgreed) _needsConsent = false;
    });
    _syncAlert();
  }

  /// 로그인했으면 바꾼 선택 동의를 서버에 저장한다(1-6). 저장하지 못하면
  /// 알린다. 설정은 탭 화면이라 저장한 뒤에도 그대로 둔다.
  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final changes = _changedOptional;
    final online = ref.read(sessionProvider) != null;
    if (!online || changes.isEmpty) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('바꾼 동의가 없어요.')));
      return;
    }

    setState(() => _saving = true);
    // 화면을 떠난 뒤에는 ref 를 쓸 수 없어 미리 잡아 둔다.
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await ref.read(accountApiProvider).updateConsents(changes);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(consentFailureMessage(failure))));
      return;
    }
    // 서버의 새 동의 이력을 다시 읽는다.
    container.invalidate(accountProvider);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('동의를 저장했어요.')));
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    // 동의가 없으면 알림은 늘 꺼져 있다.
    final alertOn = _pushAgreed && (ref.watch(reportAlertOnProvider) ?? true);

    return ScreenBody(
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.lg),

          // ── 알림 설정
          // 제목과 안내 글을 한 묶음으로 두고 스위치는 그 오른쪽 가운데에 둔다.
          // 제목과 안내 글 사이는 아래 계정 약관 동의와 같은 간격이고, 스위치의
          // 누름 영역(48)이 그 간격을 벌리지 않는다.
          MergeSemantics(
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('알림 설정', style: AppTypography.sectionTitle),
                      SizedBox(height: AppSpacing.sm),
                      Text('만남 리포트가 완성되면 알려드려요.', style: AppTypography.sub),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Switch(
                  value: alertOn,
                  onChanged: _setAlert,
                  activeTrackColor: HomeColors.accent,
                ),
              ],
            ),
          ),
          if (_needsConsent) ...[
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              liveRegion: true,
              child: Text(
                '아래 알림 수신 동의에 체크해야 알림을 켤 수 있어요.',
                style: AppTypography.sub.copyWith(color: AppColors.danger),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.section),

          // ── 계정 약관 동의
          // 동의는 어르신마다가 아니라 보호자 계정에 한 번 받는다.
          const Text('계정 약관 동의', style: AppTypography.sectionTitle),
          const SizedBox(height: AppSpacing.sm),
          const Text('함께하는 모든 분에게 똑같이 적용돼요.', style: AppTypography.sub),
          const SizedBox(height: AppSpacing.lg),
          for (final term in consentTerms) ...[
            if (term.key == _pushKey)
              AnimatedBuilder(
                key: _pushRowKey,
                animation: _flash,
                builder: (context, child) => _Highlight(
                  strength: _needsConsent
                      ? (_flash.value > 0.3 ? _flash.value : 0.3)
                      : 0,
                  child: child!,
                ),
                child: _row(term),
              )
            else
              _row(term),
            const SizedBox(height: AppSpacing.xs),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Divider(),
          ),
          _CheckLine(
            checked: _allAgreed,
            onChanged: _toggleAll,
            label: const Text('전체 동의', style: AppTypography.bodyStrong),
          ),
          const SizedBox(height: AppSpacing.section),

          PrimaryButton(
            color: HomeColors.accent,
            loadingColor: HomeColors.accentLoading,
            label: _saving ? '저장하는 중이에요' : '저장하기',
            // 필수 동의를 모두 유지해야 저장할 수 있다. 회원가입과 같은 규칙이다.
            onPressed: _requiredAgreed && !_saving ? _save : null,
          ),
          const SizedBox(height: AppSpacing.lg),
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

  /// 동의 한 줄. 쓰임새(note)는 위 알림 설정이 말하므로 여기서는 두지 않는다.
  Widget _row(ConsentTerm term) => _CheckLine(
    checked: _agreed.contains(term.key),
    onChanged: (value) => _toggle(term.key, value),
    label: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: term.required ? '[필수] ' : '[선택] ',
            style: AppTypography.body.copyWith(
              fontWeight: FontWeight.w600,
              color: term.required ? AppColors.danger : AppColors.textSub,
            ),
          ),
          TextSpan(text: term.label, style: AppTypography.body),
        ],
      ),
    ),
    below: TextButton(
      onPressed: () => showConsentDetails(context, term),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textSub,
        padding: EdgeInsets.zero,
        alignment: Alignment.centerLeft,
        minimumSize: const Size(0, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('자세히 보기', style: AppTypography.sub),
          const Icon(Icons.chevron_right, size: 18, color: AppColors.textSub),
        ],
      ),
    ),
  );
}

/// 체크박스와 이름 한 줄. 이름을 체크박스와 같은 줄에서 세로 가운데에 맞춘다.
/// [below] 는 이름 아래, 이름과 같은 왼쪽 선에 둔다. 줄 전체를 눌러 체크한다.
class _CheckLine extends StatelessWidget {
  const _CheckLine({
    required this.checked,
    required this.onChanged,
    required this.label,
    this.below,
  });

  final bool checked;
  final ValueChanged<bool?> onChanged;
  final Widget label;
  final Widget? below;

  /// 줄인 체크박스 자리(40)와 이름 사이 간격을 더한 왼쪽 들여쓰기. 자세히 보기가
  /// 이름과 같은 왼쪽 선에 온다.
  static const _indent = 40 + AppSpacing.xs;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!checked),
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 줄 전체를 눌러 체크하므로 체크박스 자리는 40 으로 줄여 이름과
              // 아래 자세히 보기 사이를 좁힌다.
              Checkbox(
                value: checked,
                onChanged: onChanged,
                activeColor: HomeColors.accent,
                side: const BorderSide(color: HomeColors.outline, width: 2),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: label),
            ],
          ),
          if (below case final below?)
            Padding(
              padding: const EdgeInsets.only(left: _indent),
              child: Transform.translate(
                offset: const Offset(0, -AppSpacing.xs),
                child: below,
              ),
            ),
        ],
      ),
    );
  }
}

/// 연한 빨간 바탕과 테두리로 감싼다. [strength] 0 이면 아무 표시도 없다.
class _Highlight extends StatelessWidget {
  const _Highlight({required this.strength, required this.child});

  final double strength;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 평소에는 바탕을 비워 둔다. 흰 바탕을 깔면 줄에 커서를 올렸을 때의 회색
    // 표시가 가려진다. 강조하는 동안에도 보이도록 투명한 Material 위에 그린다.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.dangerSurface.withValues(alpha: strength),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.danger.withValues(alpha: strength),
          width: 1.5,
        ),
      ),
      child: Material(type: MaterialType.transparency, child: child),
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
