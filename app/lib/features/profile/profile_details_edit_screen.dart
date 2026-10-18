import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api_client.dart';
import '../../data/profile_api.dart';
import '../../data/providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_text_field.dart';
import '../profile_setup/setup_steps.dart';

/// 지금 보고 있는 어르신의 세부 정보 네 항목을 고친다. 피그마 설계 없음.
///
/// 항목은 `Profile` 의 `occupation`, `hometown`, `hobby`, `family` 다
/// (`api-spec.md` 2-4). 칸을 비우면 그 항목을 지운다(`null`). 계약이 빈 문자열을
/// 받지 않기 때문이다. 서버에 저장한 분이면 프로필 수정 API 로 저장한 뒤 반영한다.
class ProfileDetailsEditScreen extends ConsumerStatefulWidget {
  const ProfileDetailsEditScreen({super.key});

  @override
  ConsumerState<ProfileDetailsEditScreen> createState() =>
      _ProfileDetailsEditScreenState();
}

class _ProfileDetailsEditScreenState
    extends ConsumerState<ProfileDetailsEditScreen> {
  /// 고치기 시작한 어르신. 화면을 여는 동안 다른 분으로 바뀌어도 이 분을 고친다.
  late final CareProfileEntry? _entry = ref.read(careProfilesProvider).selected;

  late final Map<String, TextEditingController> _fields = {
    for (final step in lifeFactSteps)
      step.category: TextEditingController(
        text: _entry?.details.of(step.category) ?? '',
      ),
  };

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  EnteredDetails get _edited => EnteredDetails.fromFacts({
    for (final entry in _fields.entries) entry.key: entry.value.text,
  });

  bool get _changed {
    final before = _entry?.details ?? const EnteredDetails();
    final now = _edited;
    return lifeFactSteps.any(
      (step) => before.of(step.category) != now.of(step.category),
    );
  }

  /// 서버에 저장하는 중이다. 같은 요청을 두 번 보내지 않는다.
  bool _saving = false;

  Future<void> _save() async {
    final entry = _entry;
    if (entry == null) return;

    var details = _edited;
    final remoteId = entry.remoteId;
    if (remoteId != null) {
      setState(() => _saving = true);
      try {
        final saved = await ref
            .read(profileApiProvider)
            .updateDetails(remoteId, details);
        details = saved.details;
      } on ApiFailure catch (failure) {
        if (!mounted) return;
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(profileFailureMessage(failure))),
          );
        return;
      }
      if (!mounted) return;
    }

    ref.read(careProfilesProvider.notifier).updateDetails(entry.id, details);
    final messenger = ScaffoldMessenger.of(context);
    context.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('세부 정보를 저장했어요.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppTopBar(),
      body: ScreenBody(
        scrollable: true,
        // 입력칸이 넷이라 버튼을 아래에 고정하지 않고 본문과 함께 흘려보낸다.
        child: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('세부 정보 수정', style: AppTypography.screenTitle),
              const SizedBox(height: AppSpacing.md),
              const Text('비워 두면 그 항목을 지워요.', style: AppTypography.sub),
              const SizedBox(height: AppSpacing.section),
              for (final step in lifeFactSteps) ...[
                AppTextField(
                  label: step.label,
                  controller: _fields[step.category],
                  maxLines: null,
                  // 처음 입력할 때 보여준 예시를 그대로 쓴다.
                  hintText: step.examples.first.replaceAll('"', ''),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.xxl),
              ],
              PrimaryButton(
                label: _saving ? '저장하는 중이에요' : '저장하기',
                onPressed: _changed && !_saving ? _save : null,
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}
