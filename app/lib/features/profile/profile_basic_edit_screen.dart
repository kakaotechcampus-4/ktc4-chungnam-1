import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api_client.dart';
import '../../data/profile_api.dart';
import '../../data/providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
import '../profile_setup/basic_info_step.dart';
import '../profile_setup/setup_controller.dart';

/// 지금 보고 있는 어르신의 이름과 기본 정보를 고친다. 피그마 설계 없음.
///
/// 처음 입력할 때의 기본 정보 폼(B-2)을 그대로 쓴다. 고친 값은 그 어르신에게만
/// 남고 세부 정보는 그대로다. 서버에 저장한 분이면 프로필 수정 API
/// (`api-spec.md` 2-4)로 저장한 뒤 반영한다.
class ProfileBasicEditScreen extends ConsumerStatefulWidget {
  const ProfileBasicEditScreen({super.key});

  @override
  ConsumerState<ProfileBasicEditScreen> createState() =>
      _ProfileBasicEditScreenState();
}

class _ProfileBasicEditScreenState
    extends ConsumerState<ProfileBasicEditScreen> {
  /// 고치기 시작한 어르신. 화면을 여는 동안 다른 분으로 바뀌어도 이 분을 고친다.
  late final CareProfileEntry? _entry = ref.read(careProfilesProvider).selected;

  late final SetupDraft _original = _entry?.basicInfo == null
      ? const SetupDraft()
      : SetupDraft.fromBasicInfo(_entry!.basicInfo!);

  late SetupDraft _draft = _original;

  bool get _changed {
    final now = _draft.toBasicInfo();
    final before = _original.toBasicInfo();
    if (now == null || before == null) return true;
    return now.name != before.name ||
        now.gender != before.gender ||
        now.birthDate != before.birthDate ||
        now.stage != before.stage;
  }

  /// 서버에 저장하는 중이다. 같은 요청을 두 번 보내지 않는다.
  bool _saving = false;

  bool get _canSave => _draft.basicInfoFilled && _changed && !_saving;

  Future<void> _save() async {
    final entry = _entry;
    var info = _draft.toBasicInfo();
    if (entry == null || info == null) return;

    final remoteId = entry.remoteId;
    if (remoteId != null) {
      setState(() => _saving = true);
      try {
        final saved = await ref
            .read(profileApiProvider)
            .updateBasicInfo(remoteId, info);
        info = saved.basicInfo;
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

    ref.read(careProfilesProvider.notifier).updateBasicInfo(entry.id, info);
    final messenger = ScaffoldMessenger.of(context);
    context.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('기본 정보를 저장했어요.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppTopBar(),
      body: ScreenBody(
        scrollable: true,
        // 처음 입력할 때와 같이 입력란이 많아 버튼을 본문과 함께 흘려보낸다.
        child: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BasicInfoStep(
                title: '기본 정보 수정',
                draft: _draft,
                onChanged: (draft) => setState(() => _draft = draft),
              ),
              const SizedBox(height: AppSpacing.xxl),
              PrimaryButton(
                label: _saving ? '저장하는 중이에요' : '저장하기',
                onPressed: _canSave ? _save : null,
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}
