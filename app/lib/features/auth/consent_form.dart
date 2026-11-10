/// 동의 항목을 보여주는 조각들이다.
///
/// 구글 로그인 뒤의 동의 화면이 쓰는 조각과 안내 문구다. 문구 자체는
/// `consent_terms.dart` 에 있고 여기서 새로 쓰지 않는다.
library;

import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
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
  /// 동의 화면은 서버가 준 `requiredConsents` 를 넘긴다. 표시와 제출 판정이
  /// 갈리지 않도록 한 곳에서 받는다.
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
            activeColor: HomeColors.accent,
            side: const BorderSide(color: HomeColors.outline, width: 2),
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
                // 내리고 글자를 보조 글자색으로 둔다(오프화이트 위 비활성 회색은 4.3:1).
                TextButton(
                  onPressed: onDetails,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSub,
                    padding: EdgeInsets.zero,
                    alignment: Alignment.centerLeft,
                    minimumSize: const Size(0, _detailsHeight),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('자세히 보기', style: AppTypography.sub),
                      const Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: AppColors.textSub,
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
///
/// 가입 동의 화면과 설정의 계정 약관 동의가 함께 쓴다. 약관이 길면 시트 안에서
/// 스크롤하고, 제목과 `닫기` 는 그 자리에 둔다. 전에는 스크롤되지 않아 작은
/// 화면이나 큰 글자에서 보유 기간 같은 아래 줄이 잘렸다(2026-11-10 UX 점검 14번).
Future<void> showConsentDetails(BuildContext context, ConsentTerm term) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.background,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    barrierLabel: '닫기',
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
    ),
    builder: (context) => _ConsentDetailsSheet(term: term),
  );
}

class _ConsentDetailsSheet extends StatefulWidget {
  const _ConsentDetailsSheet({required this.term});

  final ConsentTerm term;

  @override
  State<_ConsentDetailsSheet> createState() => _ConsentDetailsSheetState();
}

class _ConsentDetailsSheetState extends State<_ConsentDetailsSheet> {
  /// 스크롤 막대를 늘 보이게 하려면 막대와 목록이 같은 컨트롤러를 봐야 한다.
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final term = widget.term;
    return SafeArea(
      child: ConstrainedBox(
        // 사진 올리기 전 동의 시트(`photo_consent_prompt.dart`)와 같은 높이까지다.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screen,
              ),
              child: Text(term.label, style: AppTypography.sectionTitle),
            ),
            const SizedBox(height: AppSpacing.md),
            Flexible(
              // 넘칠 때만 막대가 그려진다. 아래에 더 읽을 글이 있다는 표시다.
              // 여백을 목록 안에 두어 막대가 글자 위에 겹치지 않게 한다.
              child: Scrollbar(
                controller: _scroll,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screen,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen,
                AppSpacing.lg,
                AppSpacing.screen,
                AppSpacing.section,
              ),
              child: SecondaryButton(
                borderColor: HomeColors.outline,
                label: '닫기',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
