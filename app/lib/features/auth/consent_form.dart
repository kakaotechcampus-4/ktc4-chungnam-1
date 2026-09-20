/// 동의 항목을 보여주는 조각들이다.
///
/// 아이디와 비밀번호로 가입하는 A-3 회원가입과 구글 로그인 뒤의 동의 화면이
/// 같은 문구를 같은 모양으로 보여야 해서 한곳에 둔다. 문구 자체는
/// `consent_terms.dart` 에 있고 여기서 새로 쓰지 않는다.
library;

import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import 'consent_terms.dart';

/// 동의 항목 한 줄. 체크박스, 이름, 자세히 보기다.
class ConsentRow extends StatelessWidget {
  const ConsentRow({
    required this.term,
    required this.required,
    required this.checked,
    required this.onChanged,
    required this.onDetails,
    super.key,
  });

  final ConsentTerm term;

  /// 이 화면에서 필수로 취급할 항목인지.
  ///
  /// 항목을 정의한 [ConsentTerm.required] 대신 화면이 넘긴 값을 쓴다. 구글
  /// 동의 화면은 서버가 준 `requiredConsents` 를 넘기고, 아직 서버에 보내지
  /// 않는 A-3 회원가입은 [ConsentTerm.required] 를 그대로 넘긴다. 표시와
  /// 제출 판정이 갈리지 않도록 한 곳에서 받는다.
  final bool required;

  final bool checked;
  final ValueChanged<bool?> onChanged;
  final VoidCallback onDetails;

  /// 항목 이름을 체크박스 한가운데에 맞추는 높이.
  ///
  /// 이름을 체크박스와 같은 줄(Row)에 두면 48 짜리 체크박스가 줄 높이를 정해
  /// 이름 아래에 11dp 가 남는다. 이름부터 자세히 보기까지를 한 세로 묶음으로
  /// 두고 그 빈 자리를 이 값으로 직접 정한다.
  static const _labelOffset = 12.0;

  /// 자세히 보기의 높이. 누르는 요소 최소 48 의 예외다(`app/DESIGN.md`).
  static const _detailsHeight = 28.0;

  @override
  Widget build(BuildContext context) {
    // 항목 전체가 체크 영역이다. 자세히 보기는 제 몫의 누름을 따로 받는다.
    return InkWell(
      onTap: () => onChanged(!checked),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: checked,
            onChanged: onChanged,
            activeColor: AppColors.ink,
            side: const BorderSide(color: AppColors.line, width: 2),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: _labelOffset),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: required ? '[필수] ' : '[선택] ',
                        style: AppTypography.body.copyWith(
                          fontWeight: FontWeight.w600,
                          color: required
                              ? AppColors.danger
                              : AppColors.textSub,
                        ),
                      ),
                      TextSpan(text: term.label, style: AppTypography.body),
                    ],
                  ),
                ),

                if (term.note != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(term.note!, style: AppTypography.sub),
                ],

                const SizedBox(height: AppSpacing.sm),

                // 자세히 보기를 이름과 같은 줄에 두면 이름이 쓸 수 있는 폭이
                // 316 에서 245 로 줄어 네 항목 중 셋이 줄바꿈된다. 아래 줄로
                // 내리고 글자를 한 단계 흐리게 둔다.
                TextButton(
                  onPressed: onDetails,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textDisabled,
                    padding: EdgeInsets.zero,
                    alignment: Alignment.centerLeft,
                    minimumSize: const Size(0, _detailsHeight),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '자세히 보기',
                        style: AppTypography.sub.copyWith(
                          color: AppColors.textDisabled,
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: AppColors.textDisabled,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 동의문 전문을 아래에서 올라오는 시트로 보여준다.
Future<void> showConsentDetails(BuildContext context, ConsentTerm term) {
  return showModalBottomSheet<void>(
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

/// 진행을 막는 이유를 한 칸에 보여준다. 필수 동의 안내와 로그인 실패에 쓴다.
class AuthNotice extends StatelessWidget {
  const AuthNotice({required this.message, super.key});

  final String message;

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
              message,
              style: AppTypography.sub.copyWith(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }
}
