import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/auth_api.dart';
import '../../data/providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_surfaces.dart';
import '../auth/auth_messages.dart';
import '../auth/auth_providers.dart';
import '../auth/consent_form.dart';
import '../profile_setup/setup_controller.dart';

/// 회원 탈퇴 확인. 프로필 설정의 `회원탈퇴`를 누르면 뜬다(피그마 설계 없음).
///
/// `탈퇴하기`는 `DELETE /auth/me` 를 부른다. 서버가 계정을 지웠다고 답한 뒤에만
/// 단말 세션을 지우고 로그인 화면으로 간다. 실패하면 이 화면에 남아 이유를
/// 알린다.
///
/// 탈퇴 후 보유 기간과 재가입 가능 여부는 `docs/legal/` 어디에도 정해진 내용이
/// 없어 여기서 임의로 짓지 않는다. 탈퇴 이유는 계약이나 법률 문서에 속하는 값이
/// 아니라 화면에서만 쓰는 설문이라 이 파일에 그대로 둔다. 서버로 보내지 않는다.
///
/// 탈퇴는 보호자 계정 전체를 지운다(`api-spec.md` 1-5). 함께하는 분이 여럿일 수
/// 있어 특정 어르신의 이름을 부르지 않는다.
class ProfileDeleteScreen extends StatelessWidget {
  const ProfileDeleteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(appBar: AppTopBar(), body: _Body());
  }
}

/// 탈퇴 이유 하나. 마지막 [other]만 직접 입력을 받는다.
class _Reason {
  const _Reason(this.label, {this.other = false});

  final String label;
  final bool other;
}

const _reasons = <_Reason>[
  _Reason('부모님의 인지 상태가 변화하여 더 이상 대화 카드가 필요 없어요 (퇴원, 증상 악화 등)'),
  _Reason('생성된 대화 카드가 부모님과 대화하는 데 실제 도움이 되지 않아요'),
  _Reason('면회를 자주 가지 않거나 정기적으로 쓰기 어려워요'),
  _Reason('앱 사용법이 어렵거나 원하는 기능을 찾기 불편해요'),
  _Reason('면회 중 녹음하거나 리포트를 확인하는 과정이 번거롭고 부담돼요'),
  _Reason('기타 (직접 입력)', other: true),
];

class _Body extends ConsumerStatefulWidget {
  const _Body();

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  final _selected = <int>{};
  final _otherReason = TextEditingController();

  /// 서버의 답을 기다리는 중이다. 성공하면 화면을 떠날 때까지 그대로 둔다.
  bool _deleting = false;

  AuthFailure? _failure;

  Future<void> _delete() async {
    setState(() {
      _deleting = true;
      _failure = null;
    });

    // 탈퇴가 끝나면 세션이 비므로 지울 계정을 먼저 붙잡아 둔다.
    final accountId = ref.read(sessionProvider)?.account.accountId;
    try {
      await ref.read(sessionProvider.notifier).deleteAccount();
    } on AuthFailure catch (failure) {
      logAuthFailure(failure);
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _failure = failure;
      });
      return;
    }

    if (!mounted) return;
    forgetCareProfiles(ref);
    if (accountId != null) {
      ref.read(reportNoticeProvider.notifier).forgetAccount(accountId);
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('탈퇴가 완료됐어요.')));
    context.go(AppRoutes.login);
  }

  /// 세션이 풀렸거나 계정이 이미 없다. 남은 세션을 버리고 로그인부터 한다.
  ///
  /// 로그아웃과 같이 단말의 어르신과 고른 분도 비운다. 남겨 두면 다른 계정으로
  /// 로그인했을 때 앞 계정의 어르신이 보인다.
  Future<void> _backToLogin() async {
    await ref.read(sessionProvider.notifier).discard();
    if (!mounted) return;
    forgetCareProfiles(ref);
    context.go(AppRoutes.login);
  }

  void _toggle(int i) {
    setState(() {
      if (_selected.contains(i)) {
        _selected.remove(i);
      } else {
        _selected.add(i);
      }
    });
  }

  @override
  void dispose() {
    _otherReason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final failure = _failure;
    // 서버 세션 없이 이 화면에 온 경우다. 지울 계정을 가리킬 세션이 없으므로
    // 탈퇴된 것처럼 넘기지 않는다.
    final signedOut = ref.watch(sessionProvider) == null && !_deleting;
    final restart = signedOut || (failure != null && needsRestart(failure));

    final String? notice;
    if (signedOut) {
      notice = '로그인 정보가 없어요. 로그인한 뒤 다시 시도해주세요.';
    } else if (failure != null) {
      notice = accountDeletionFailureMessage(failure);
    } else {
      notice = null;
    }

    return ScreenBody(
      scrollable: true,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (notice != null) ...[
            AuthNotice(message: notice),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (restart)
            PrimaryButton(label: '로그인으로 돌아가기', onPressed: _backToLogin)
          else
            PrimaryButton(
              label: _deleting ? '탈퇴하는 중이에요' : '탈퇴하기',
              onPressed: _deleting ? null : _delete,
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.sm),
          const Text('새록과 이별인가요?\n너무 아쉬워요.', style: AppTypography.screenTitle),
          const SizedBox(height: AppSpacing.lg),
          const Text(
            '계정을 삭제하면 함께하는 모든 분의 대화 카드, 이야기 앨범 등 활동 정보와 '
            '개인 정보가 삭제돼요.',
            style: AppTypography.body,
          ),
          const SizedBox(height: AppSpacing.section),

          const Text('탈퇴하려는 이유가 궁금해요.', style: AppTypography.sectionTitle),
          const SizedBox(height: AppSpacing.lg),

          for (final (i, reason) in _reasons.indexed) ...[
            _ReasonRow(
              label: reason.label,
              selected: _selected.contains(i),
              onTap: () => _toggle(i),
            ),
            const SizedBox(height: AppSpacing.md),
            if (reason.other && _selected.contains(i)) ...[
              TextField(
                controller: _otherReason,
                maxLines: 3,
                style: AppTypography.body,
                decoration: InputDecoration(
                  hintText: '이유를 적어주세요',
                  hintStyle: AppTypography.body.copyWith(
                    color: AppColors.textDisabled,
                  ),
                  contentPadding: const EdgeInsets.all(AppSpacing.lg),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    borderSide: const BorderSide(color: AppColors.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    borderSide: const BorderSide(color: AppColors.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    borderSide: const BorderSide(
                      color: AppColors.ink,
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ],

          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

class _ReasonRow extends StatelessWidget {
  const _ReasonRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: SelectionMark(selected: selected, size: 24),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(label, style: AppTypography.body)),
        ],
      ),
    );
  }
}
