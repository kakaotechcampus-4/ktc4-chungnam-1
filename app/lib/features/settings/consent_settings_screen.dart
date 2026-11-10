import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// 계정 약관 동의. 설정의 `계정 약관 동의` 줄을 누르면 들어온다.
///
/// 동의는 어르신마다가 아니라 보호자 계정에 한 번 받으므로 어르신이 없어도
/// 열린다. 네 항목과 전체 동의, 저장하기를 둔다.
///
/// [pointAtPush] 면 알림 수신 동의 줄로 끌어와 깜빡인다. 설정에서 동의 없이
/// 알림을 켜려 한 뒤 들어온 경우다.
class ConsentSettingsScreen extends ConsumerWidget {
  const ConsentSettingsScreen({this.pointAtPush = false, super.key});

  final bool pointAtPush;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider);
    return Scaffold(
      backgroundColor: HomeColors.background,
      appBar: const AppTopBar(
        backgroundColor: HomeColors.background,
        title: '계정 약관 동의',
      ),
      body: account.when(
        // 체크 상태는 처음 받은 값에서 시작하므로, 저장 뒤 다시 읽는 중에는
        // 이전 값을 보여주지 않고 기다린다.
        skipLoadingOnRefresh: false,
        loading: () => const LoadingView(),
        error: (error, _) => ErrorStateView(
          message: '계정 정보를 불러오지 못했어요.',
          onRetry: () => ref.invalidate(accountProvider),
        ),
        data: (account) => _Body(account: account, pointAtPush: pointAtPush),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.account, required this.pointAtPush});

  final Account account;
  final bool pointAtPush;

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

  /// 알림 수신 동의 줄을 강조한다. 그 줄에 체크하면 사라진다.
  late bool _needsPush = widget.pointAtPush && !_pushAgreed;

  /// 알림 수신 동의 줄. 안내할 때 보이는 자리로 끌어온다.
  final _pushRowKey = GlobalKey();

  /// 알림 수신 동의 줄을 깜빡인다.
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );

  @override
  void initState() {
    super.initState();
    if (_needsPush) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_pointAtPush());
      });
    }
  }

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

  /// 알림 수신 동의 줄을 보이는 자리로 끌어와 두 번 깜빡인다.
  Future<void> _pointAtPush() async {
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

  void _toggle(String key, bool? value) {
    setState(() {
      if (value ?? false) {
        _agreed.add(key);
      } else {
        _agreed.remove(key);
      }
      if (_pushAgreed) _needsPush = false;
    });
  }

  void _toggleAll(bool? value) {
    setState(() {
      if (value ?? false) {
        _agreed.addAll(consentTerms.map((t) => t.key));
      } else {
        _agreed.clear();
      }
      if (_pushAgreed) _needsPush = false;
    });
  }

  /// 로그인했으면 바꾼 선택 동의를 서버에 저장한다(1-6). 저장하지 못하면
  /// 알린다. 저장한 뒤에도 화면을 닫지 않는다. 그사이 다른 화면을 열었어도
  /// 그 화면을 건드리지 않는다.
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
    // 서버의 새 동의 이력을 다시 읽는다. 설정의 알림 스위치도 이 값을 따른다.
    container.invalidate(accountProvider);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('동의를 저장했어요.')));
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return ScreenBody(
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.lg),
          const Text('함께하는 모든 분에게 똑같이 적용돼요.', style: AppTypography.sub),
          if (_needsPush) ...[
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              liveRegion: true,
              child: Text(
                '알림 수신 동의에 체크하고 저장하면 알림이 켜져요.',
                style: AppTypography.sub.copyWith(color: AppColors.danger),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          for (final term in consentTerms) ...[
            if (term.key == _pushKey)
              AnimatedBuilder(
                key: _pushRowKey,
                animation: _flash,
                builder: (context, child) => _Highlight(
                  strength: _needsPush
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
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  /// 동의 한 줄. 알림 항목의 쓰임새(note)는 설정의 알림 설정이 말하므로 여기서는
  /// 두지 않는다.
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
