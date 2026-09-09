import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../design/tokens.dart';
import '../../widgets/app_text_field.dart';
import 'setup_controller.dart';

/// B-2 기본 정보 입력. 이름, 성별, 생년월일, 현재 상태를 받는다.
///
/// 현재 상태의 선택지는 계약의 `ConditionStage` 셋뿐이다. 화면에서 값을 늘리지
/// 않는다.
class BasicInfoStep extends StatefulWidget {
  const BasicInfoStep({
    required this.draft,
    required this.onChanged,
    super.key,
  });

  final SetupDraft draft;
  final ValueChanged<SetupDraft> onChanged;

  @override
  State<BasicInfoStep> createState() => _BasicInfoStepState();
}

class _BasicInfoStepState extends State<BasicInfoStep> {
  late final _name = TextEditingController(text: widget.draft.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  SetupDraft get _draft => widget.draft;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('기본 정보 입력', style: AppTypography.screenTitle),
        const SizedBox(height: AppSpacing.section),

        AppTextField(
          label: '이름',
          controller: _name,
          required: true,
          hintText: '어르신의 성함을 입력해주세요',
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
                onTap: () => widget.onChanged(_draft.copyWith(gender: 'female')),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxl),

        const FieldLabel('생년월일', required: true),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: _NumberPicker(
                hint: '년',
                value: _draft.birthYear,
                values: [for (var y = 1920; y <= 1980; y++) y],
                suffix: '년',
                onChanged: (v) =>
                    widget.onChanged(_draft.copyWith(birthYear: v)),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _NumberPicker(
                hint: '월',
                value: _draft.birthMonth,
                values: [for (var m = 1; m <= 12; m++) m],
                suffix: '월',
                onChanged: (v) =>
                    widget.onChanged(_draft.copyWith(birthMonth: v)),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _NumberPicker(
                hint: '일',
                value: _draft.birthDay,
                values: [for (var d = 1; d <= 31; d++) d],
                suffix: '일',
                onChanged: (v) => widget.onChanged(_draft.copyWith(birthDay: v)),
              ),
            ),
          ],
        ),
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
}

class _ChoiceBox extends StatelessWidget {
  const _ChoiceBox({
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
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        height: AppSizes.control,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.surface : AppColors.background,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: selected ? AppColors.ink : AppColors.line,
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        height: AppSizes.control,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        decoration: BoxDecoration(
          color: selected ? AppColors.surface : AppColors.background,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: selected ? AppColors.ink : AppColors.line,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: selected ? AppColors.ink : AppColors.background,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.ink : AppColors.line,
                  width: 2,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 15, color: AppColors.background)
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
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value,
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
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
