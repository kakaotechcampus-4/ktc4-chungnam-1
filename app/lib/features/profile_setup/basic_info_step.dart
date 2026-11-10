import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/birth_date.dart';
import '../../data/models.dart';
import '../../design/tokens.dart';
import '../../widgets/app_text_field.dart';
import 'setup_controller.dart';

/// B-2 기본 정보 입력. 이름, 성별, 관계, 생년월일, 현재 상태를 받는다.
///
/// 관계는 보호자가 자유롭게 적는 선택 항목이다. 예시는 안내 글자로만 보여주고
/// 고르게 하지 않는다. 앱에서 부를 때만 쓰고 이 휴대폰에만 저장한다.
///
/// 생년월일은 날짜로 고르거나 나이로 적는다. 날짜는 달력에 있는 날만, 서버가
/// 받는 범위(만 10세 이상, 미래가 아님)에서만 고른다. 나이로 적으면 오늘에서
/// 그 나이만큼 뺀 날을 보낸다(`birth_date.dart`, 2026-11-10 PM 결정).
///
/// 현재 상태의 선택지는 계약의 `ConditionStage` 셋뿐이다. 화면에서 값을 늘리지
/// 않는다.
class BasicInfoStep extends StatefulWidget {
  const BasicInfoStep({
    required this.draft,
    required this.onChanged,
    this.title = '기본 정보 입력',
    this.now,
    super.key,
  });

  final SetupDraft draft;
  final ValueChanged<SetupDraft> onChanged;

  /// 처음 입력할 때의 큰 제목. 프로필 설정에서 고칠 때는 상단바에 화면 이름을
  /// 두므로 `null` 로 넘겨 그리지 않는다.
  final String? title;

  /// 고를 수 있는 날짜를 셀 때의 지금. 테스트만 넘긴다.
  final DateTime? now;

  @override
  State<BasicInfoStep> createState() => _BasicInfoStepState();
}

class _BasicInfoStepState extends State<BasicInfoStep> {
  late final _name = TextEditingController(text: widget.draft.name);
  late final _relationship = TextEditingController(
    text: widget.draft.relationship,
  );
  late final _age = TextEditingController(
    text: widget.draft.age?.toString() ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    _relationship.dispose();
    _age.dispose();
    super.dispose();
  }

  SetupDraft get _draft => widget.draft;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.title case final title?) ...[
          Text(title, style: AppTypography.screenTitle),
          const SizedBox(height: AppSpacing.section),
        ],

        AppTextField(
          borderColor: HomeColors.outline,
          focusColor: HomeColors.accent,
          label: '이름',
          controller: _name,
          required: true,
          hintText: '함께하는 분의 성함을 입력해주세요',
          errorText: _draft.nameTooLong
              ? '이름은 ${SetupDraft.maxNameLength}자까지 적을 수 있어요.'
              : null,
          onChanged: (value) => widget.onChanged(_draft.copyWith(name: value)),
        ),
        const SizedBox(height: AppSpacing.xxl),

        const FieldLabel('성별', required: true),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: _ChoiceBox(
                label: '남성',
                selected: _draft.gender == 'male',
                onTap: () => widget.onChanged(_draft.copyWith(gender: 'male')),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _ChoiceBox(
                label: '여성',
                selected: _draft.gender == 'female',
                onTap: () =>
                    widget.onChanged(_draft.copyWith(gender: 'female')),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxl),

        AppTextField(
          borderColor: HomeColors.outline,
          focusColor: HomeColors.accent,
          label: '관계',
          description: '이름 옆에 붙여 불러요. 이 휴대폰에만 저장돼요.',
          controller: _relationship,
          hintText: '예) 아버지, 어머니',
          errorText: _draft.relationshipTooLong
              ? '관계는 ${SetupDraft.maxRelationshipLength}자까지 적을 수 있어요.'
              : null,
          onChanged: (value) =>
              widget.onChanged(_draft.copyWith(relationship: value)),
        ),
        const SizedBox(height: AppSpacing.xxl),

        const FieldLabel('생년월일', required: true),
        const SizedBox(height: AppSpacing.md),
        // 날짜를 모르면 나이로 적는다. 두 방식의 값은 따로 남아 오가도 지워지지
        // 않는다.
        _inputModeChoice(context),
        const SizedBox(height: AppSpacing.md),
        if (_draft.birthByAge) _ageInput() else _datePickers(),
        const SizedBox(height: AppSpacing.xxl),

        const FieldLabel('현재 상태', required: true),
        const SizedBox(height: AppSpacing.md),
        for (final stage in ConditionStage.values) ...[
          _RadioRow(
            label: stage.label,
            selected: _draft.stage == stage,
            onTap: () => widget.onChanged(_draft.copyWith(stage: stage)),
          ),
          if (stage != ConditionStage.values.last)
            const SizedBox(height: AppSpacing.md),
        ],
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }

  /// `날짜로 입력` 과 `나이로 입력` 중 하나를 고른다. 글자를 크게 키우면
  /// 나란히 두었을 때 `나이로 입 / 력` 처럼 낱자에서 꺾여 위아래로 쌓는다.
  Widget _inputModeChoice(BuildContext context) {
    final byDate = _ChoiceBox(
      label: '날짜로 입력',
      selected: !_draft.birthByAge,
      exclusive: true,
      onTap: () => widget.onChanged(_draft.copyWith(birthByAge: false)),
    );
    final byAge = _ChoiceBox(
      label: '나이로 입력',
      selected: _draft.birthByAge,
      exclusive: true,
      onTap: () => widget.onChanged(_draft.copyWith(birthByAge: true)),
    );
    final scale = MediaQuery.textScalerOf(context).scale(1);
    if (scale > 1.5) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          byDate,
          const SizedBox(height: AppSpacing.md),
          byAge,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: byDate),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: byAge),
      ],
    );
  }

  /// 년, 월, 일 세 칸. 월은 고른 해에, 일은 고른 달과 윤년에 맞춰 있는 날만
  /// 보여준다. 해 목록은 오늘 만 10세가 되는 해까지다(서버 기준).
  Widget _datePickers() {
    final now = widget.now ?? DateTime.now();
    final latest = latestBirthDate(now);
    final year = _draft.birthYear;
    final month = _draft.birthMonth;
    final lastMonth = year == latest.year ? latest.month : 12;
    final lastDay = month == null
        ? 31
        : year == null
        ? daysInMonth(2000, month)
        : year == latest.year && month == latest.month
        ? latest.day
        : daysInMonth(year, month);
    void pick({int? y, int? m, int? d}) => widget.onChanged(
      _draft.withBirthPart(year: y, month: m, day: d, now: now),
    );
    return Row(
      children: [
        Expanded(
          child: _NumberPicker(
            hint: '년',
            value: year,
            values: [
              for (var y = earliestBirthYear(now); y <= latest.year; y++) y,
            ],
            suffix: '년',
            onChanged: (v) => pick(y: v),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _NumberPicker(
            hint: '월',
            value: month,
            values: [for (var m = 1; m <= lastMonth; m++) m],
            suffix: '월',
            onChanged: (v) => pick(m: v),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _NumberPicker(
            hint: '일',
            value: _draft.birthDay,
            values: [for (var d = 1; d <= lastDay; d++) d],
            suffix: '일',
            onChanged: (v) => pick(d: v),
          ),
        ),
      ],
    );
  }

  /// 나이 한 칸. 적은 나이로 생년월일을 만든다.
  Widget _ageInput() {
    return AppTextField(
      borderColor: HomeColors.outline,
      focusColor: HomeColors.accent,
      label: '나이',
      description: '정확한 날짜를 모를 때 지금 나이를 적어요. 해마다 한 살씩 늘어요.',
      controller: _age,
      hintText: '예) 82',
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(3),
      ],
      // 입력 글자와 같은 줄 높이에 오도록 가운데 둔다.
      suffix: Center(
        widthFactor: 1,
        child: Padding(
          padding: const EdgeInsets.only(right: AppSpacing.lg),
          child: Text('세', style: AppTypography.body),
        ),
      ),
      errorText: _draft.ageOutOfRange
          ? '$minAgeInput세에서 $maxAgeInput세 사이로 적어주세요.'
          : null,
      onChanged: (value) => widget.onChanged(_draft.withAgeText(value)),
    );
  }
}

class _ChoiceBox extends StatelessWidget {
  const _ChoiceBox({
    required this.label,
    required this.selected,
    required this.onTap,
    this.exclusive = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// 둘 중 하나를 고르는 항목이다. 화면 낭독기가 선택 여부를 함께 읽는다.
  final bool exclusive;

  @override
  Widget build(BuildContext context) {
    final box = _box();
    if (!exclusive) return box;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      child: box,
    );
  }

  Widget _box() {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      // 글자를 키우면 칸이 함께 커지고 줄을 바꾼다. 높이를 고정하면 2배 글자에서
      // `나이로 입력` 이 `나이로 입` 으로 잘렸다(360dp).
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSizes.control),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? HomeColors.bubble : AppColors.background,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: selected ? HomeColors.accent : HomeColors.outline,
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: selected ? AppTypography.bodyStrong : AppTypography.body,
        ),
      ),
    );
  }
}

class _RadioRow extends StatelessWidget {
  const _RadioRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 화면 낭독기가 셋 중 하나를 고르는 항목과 선택 여부를 함께 읽는다.
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          height: AppSizes.control,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          decoration: BoxDecoration(
            color: selected ? HomeColors.bubble : AppColors.background,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: selected ? HomeColors.accent : HomeColors.outline,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: selected ? HomeColors.accent : AppColors.background,
                  shape: BoxShape.circle,
                  // 빈 동그라미도 흰 배경과 3:1 이상 대비가 나도록 공용 선택
                  // 표시(`SelectionMark`)와 같은 색을 쓴다(접근성 보고서 14쪽).
                  border: Border.all(
                    color: selected
                        ? HomeColors.accent
                        : AppColors.selectionRing,
                    width: 2,
                  ),
                ),
                child: selected
                    ? const Icon(
                        Icons.check,
                        size: 15,
                        color: AppColors.background,
                      )
                    : null,
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                label,
                style: selected ? AppTypography.bodyStrong : AppTypography.body,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NumberPicker extends StatelessWidget {
  const _NumberPicker({
    required this.hint,
    required this.value,
    required this.values,
    required this.suffix,
    required this.onChanged,
  });

  final String hint;
  final int? value;
  final List<int> values;
  final String suffix;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppSizes.control,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      // 흰 칸이라 안내 글자의 비활성 회색이 4.5:1 을 지킨다.
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: HomeColors.outline),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          // 목록에 없는 값(예전 범위 밖의 해, 달력에 없는 날)이 들어와도 화면이
          // 멈추지 않게 비운 칸으로 보여준다. 그 값으로는 마칠 수 없다.
          value: values.contains(value) ? value : null,
          isExpanded: true,
          hint: Text(
            hint,
            style: AppTypography.body.copyWith(color: AppColors.textDisabled),
          ),
          style: AppTypography.body,
          icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.textSub),
          items: [
            for (final v in values)
              DropdownMenuItem(value: v, child: Text('$v$suffix')),
          ],
          // 고른 값은 칸 안에서 한 줄로 보인다. 세 칸으로 나눈 폭에서는 "1933년"이
          // 두 줄로 꺾였다(Galaxy S22). 길면 칸에 맞게 줄인다.
          selectedItemBuilder: (context) => [
            for (final v in values)
              Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('$v$suffix', maxLines: 1, softWrap: false),
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
