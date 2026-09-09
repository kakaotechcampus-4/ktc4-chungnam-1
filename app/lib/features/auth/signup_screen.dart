import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_text_field.dart';
import 'consent_terms.dart';

/// A-3 회원가입과 동의.
///
/// 받는 동의 항목은 `consent_terms.dart` 를 따른다. 필수 항목을 모두 수락해야
/// 가입을 진행한다.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  static const _domains = ['naver.com', 'gmail.com', 'daum.net', '직접 입력'];

  final _name = TextEditingController();
  final _emailLocal = TextEditingController();
  final _emailDomain = TextEditingController();
  final _loginId = TextEditingController();
  final _password = TextEditingController();

  String _selectedDomain = _domains.first;
  final _agreed = <String>{};

  bool get _domainIsCustom => _selectedDomain == _domains.last;

  bool get _fieldsFilled =>
      _name.text.trim().isNotEmpty &&
      _emailLocal.text.trim().isNotEmpty &&
      (!_domainIsCustom || _emailDomain.text.trim().isNotEmpty) &&
      _loginId.text.trim().isNotEmpty &&
      _password.text.isNotEmpty;

  bool get _requiredAgreed => consentTerms
      .where((term) => term.required)
      .every((term) => _agreed.contains(term.key));

  bool get _allAgreed => _agreed.length == consentTerms.length;

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
    });
  }

  void _showDetails(ConsentTerm term) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.background,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen,
            0,
            AppSpacing.screen,
            AppSpacing.section,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(term.label, style: AppTypography.sectionTitle),
              const SizedBox(height: AppSpacing.md),
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
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _emailLocal.dispose();
    _emailDomain.dispose();
    _loginId.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _fieldsFilled && _requiredAgreed;

    return Scaffold(
      appBar: const AppTopBar(),
      body: ScreenBody(
        scrollable: true,
        bottom: Column(
          children: [
            PrimaryButton(
              label: '회원가입',
              // 필수 동의를 모두 수락해야 가입을 진행한다.
              onPressed: canSubmit ? () => context.go(AppRoutes.onboarding) : null,
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('이미 계정이 있으신가요?', style: AppTypography.sub),
                const SizedBox(width: AppSpacing.sm),
                AppTextButton(
                  label: '로그인',
                  onPressed: () => context.go(AppRoutes.login),
                ),
              ],
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.sm),
            const Text('회원가입', style: AppTypography.screenTitle),
            const SizedBox(height: AppSpacing.section),

            AppTextField(
              label: '이름',
              controller: _name,
              required: true,
              hintText: '보호자분의 이름을 입력해주세요',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.xl),

            _EmailField(
              local: _emailLocal,
              custom: _emailDomain,
              domains: _domains,
              selected: _selectedDomain,
              isCustom: _domainIsCustom,
              onDomainChanged: (value) =>
                  setState(() => _selectedDomain = value),
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.xl),

            AppTextField(
              label: '아이디',
              controller: _loginId,
              required: true,
              hintText: '사용하실 아이디를 입력해주세요',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.xl),

            AppTextField(
              label: '비밀번호',
              controller: _password,
              required: true,
              obscureText: true,
              hintText: '비밀번호를 입력해주세요',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.section),

            const Text('약관 동의', style: AppTypography.sectionTitle),
            const SizedBox(height: AppSpacing.lg),

            for (final term in consentTerms) ...[
              _ConsentRow(
                term: term,
                checked: _agreed.contains(term.key),
                onChanged: (value) => _toggle(term.key, value),
                onDetails: () => _showDetails(term),
              ),
              const SizedBox(height: AppSpacing.sm),
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

            if (_fieldsFilled && !_requiredAgreed) ...[
              const SizedBox(height: AppSpacing.lg),
              const _RequiredNotice(),
            ],

            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}

class _ConsentRow extends StatelessWidget {
  const _ConsentRow({
    required this.term,
    required this.checked,
    required this.onChanged,
    required this.onDetails,
  });

  final ConsentTerm term;
  final bool checked;
  final ValueChanged<bool?> onChanged;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Checkbox(
          value: checked,
          onChanged: onChanged,
          activeColor: AppColors.ink,
          side: const BorderSide(color: AppColors.line, width: 2),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: GestureDetector(
            onTap: () => onChanged(!checked),
            behavior: HitTestBehavior.opaque,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: term.required ? '[필수] ' : '[선택] ',
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: term.required
                          ? AppColors.danger
                          : AppColors.textSub,
                    ),
                  ),
                  TextSpan(text: term.label, style: AppTypography.body),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: onDetails,
          icon: const Icon(Icons.chevron_right, color: AppColors.textSub),
          tooltip: '자세히 보기',
        ),
      ],
    );
  }
}

class _RequiredNotice extends StatelessWidget {
  const _RequiredNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.dangerSurface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 22, color: AppColors.danger),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              '필수 항목에 모두 동의해야 가입할 수 있어요.',
              style: AppTypography.sub.copyWith(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }
}

/// 아이디와 도메인을 나눠 입력한다. 피그마 A-3 의 구성을 따랐다.
class _EmailField extends StatelessWidget {
  const _EmailField({
    required this.local,
    required this.custom,
    required this.domains,
    required this.selected,
    required this.isCustom,
    required this.onDomainChanged,
    required this.onChanged,
  });

  final TextEditingController local;
  final TextEditingController custom;
  final List<String> domains;
  final String selected;
  final bool isCustom;
  final ValueChanged<String> onDomainChanged;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('이메일', required: true),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                controller: local,
                onChanged: (_) => onChanged(),
                style: AppTypography.body,
                decoration: _decoration('이메일'),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Text('@', style: AppTypography.body),
            ),
            Expanded(
              child: Container(
                height: AppSizes.control,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.line),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selected,
                    isExpanded: true,
                    style: AppTypography.body,
                    icon: const Icon(
                      Icons.keyboard_arrow_down,
                      color: AppColors.textSub,
                    ),
                    items: [
                      for (final domain in domains)
                        DropdownMenuItem(value: domain, child: Text(domain)),
                    ],
                    onChanged: (value) {
                      if (value != null) onDomainChanged(value);
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
        if (isCustom) ...[
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: custom,
            onChanged: (_) => onChanged(),
            style: AppTypography.body,
            decoration: _decoration('도메인을 직접 입력해주세요'),
          ),
        ],
      ],
    );
  }

  static InputDecoration _decoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: AppTypography.body.copyWith(color: AppColors.textDisabled),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.lg,
    ),
    border: _border(AppColors.line),
    enabledBorder: _border(AppColors.line),
    focusedBorder: _border(AppColors.ink, width: 2),
  );

  static OutlineInputBorder _border(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        borderSide: BorderSide(color: color, width: width),
      );
}
