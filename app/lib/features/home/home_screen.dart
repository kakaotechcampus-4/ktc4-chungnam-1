import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/api_client.dart';
import '../../data/card_api.dart';
import '../../data/providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/profile_avatar.dart';
import '../cards/card_generation_controller.dart';
import '../profile/profile_dialogs.dart';
import 'home_talk.dart';

/// 시작 화면.
///
/// 리포트 도착 알림은 별도 데이터가 아니라 이 화면의 상태다(피그마 `HOME`,
/// `HOME-1`). 알림을 눌러야 리포트로 들어갈 수 있고, 확인하면 사라진다.
///
/// 왼쪽 상단 알림 아이콘을 누르면 같은 상태를 다시 보여주는 `notice_screen.dart`
/// 가 뜬다. 상태를 새로 만들지 않고 `reportNoticeProvider` 를 그대로 본다.
///
/// 등록한 어르신이 없으면 이름 없이 묻고, 알림, 일대기와 대화 카드 받기를
/// 누르면 등록부터 안내한다.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(reportNoticeProvider);
    final info = ref.watch(reportNoticeInfoProvider);
    // 서버의 알림은 리포트와 날짜를 함께 안다. 목 데이터의 알림은 목 리포트를
    // 가리킨다.
    final mockReport = info?.fromServer ?? false
        ? null
        : ref.watch(visitReportProvider).value;
    final date = info?.visitDate ?? mockReport?.visitDate;
    final reportId = info?.reportId ?? mockReport?.reportId;
    final hasProfile = ref.watch(
      careProfilesProvider.select((p) => p.hasSelected),
    );
    final shown = ref.watch(profileProvider).value?.profile;
    final name = shown?.name;
    final profileKey = shown?.profileId;

    // 어르신이 있어야 쓰는 기능이다. 없으면 등록부터 안내한다.
    void needsProfile(VoidCallback open) =>
        hasProfile ? open() : showProfileRequiredDialog(context);

    return Scaffold(
      body: Column(
        children: [
          // 만드는 중에는 아직 볼 것이 없으므로 점을 찍지 않는다.
          _TopBar(
            hasNotice: notice == ReportNotice.ready,
            onNotice: () =>
                needsProfile(() => context.push(AppRoutes.notifications)),
          ),
          Expanded(
            child: ScreenBody(
              bottom: Column(
                children: [
                  _CardButton(needsProfile: needsProfile),
                  // 같은 자리에서 만드는 중이 도착으로 바뀐다. 로딩 화면을
                  // 없앤 뒤로 만드는 중을 알리는 자리가 여기뿐이다.
                  if (notice != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    switch (notice) {
                      // 리포트를 아직 읽는 중이면 날짜 없이 보여준다.
                      ReportNotice.generating => _GeneratingNotice(date: date),
                      ReportNotice.ready => _ReportNotice(
                        date: date,
                        // 여기서는 지우지 않는다. 변경 사항을 반영해야 사라진다.
                        onTap: () {
                          if (reportId == null) return;
                          context.push(AppRoutes.reportOf(reportId));
                        },
                      ),
                      ReportNotice.failed => _ResumeNotice(
                        date: date,
                        title: '리포트를 만들지 못했어요',
                        hint: '눌러서 분석 다시 요청하기',
                        icon: Icons.error_outline,
                        onTap: () {
                          final analysisId = info?.analysisId;
                          if (reportId == null || analysisId == null) return;
                          context.push(
                            AppRoutes.analysisRetryOf(reportId, analysisId),
                          );
                        },
                      ),
                      // 앱을 다시 켠 뒤 서버의 회차로 면회 흐름을 이어간다.
                      // 서버의 알림이라 회차 ID 가 있다.
                      ReportNotice.evaluationPending => _ResumeNotice(
                        date: date,
                        title: '평가 이어서 하기',
                        hint: '평가를 마치면 리포트를 만들어요',
                        onTap: () {
                          if (reportId == null) return;
                          context.push(AppRoutes.visitReviewOf(reportId));
                        },
                      ),
                      ReportNotice.audioPending => _ResumeNotice(
                        date: date,
                        title: '음성 다시 보내기',
                        hint: '녹음을 보내면 리포트를 만들어요',
                        onTap: () {
                          if (reportId == null) return;
                          context.push(AppRoutes.visitUploadOf(reportId));
                        },
                      ),
                      // 묻지 못한 것을 알릴 것이 없는 것처럼 두지 않는다.
                      ReportNotice.checkFailed => _ResumeNotice(
                        date: null,
                        icon: Icons.refresh,
                        title: '리포트 상태를 확인하지 못했어요',
                        hint: '눌러서 다시 확인하기',
                        onTap: () =>
                            ref.read(reportNoticeProvider.notifier).retry(),
                      ),
                    },
                  ],
                ],
              ),
              // 남는 높이를 위 2, 아래 3 으로 나눈다. 높이가 모자라면 그림이
              // 줄어든다. 그림이 크기를 고집하면 화면이 낮을 때 알림 배너가
              // 붙는 순간 아래로 넘친다.
              //
              // 글자를 크게 키웠거나 남는 높이가 아주 낮으면 그림을 줄여도 안내
              // 문구와 말풍선만으로 넘친다. 그때는 그림 크기를 정해 두고 본문을
              // 스크롤한다. 글자를 잘리게 두지 않는다(`app/DESIGN.md`).
              child: LayoutBuilder(
                builder: (context, box) {
                  final roomy =
                      MediaQuery.textScalerOf(context).scale(1) <= 1.3 &&
                      box.maxHeight >= 300;
                  final content = Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 어느 어르신의 대화 카드를 받는지 가장 큰 안내에서 알린다.
                      // 이름을 읽는 동안에는 이름 없이 묻는다.
                      Text(
                        name == null
                            ? '오늘은 무슨 주제로\n대화를 나눠볼까요?'
                            : '오늘은 $name 어르신과\n무슨 주제로 대화를 나눠볼까요?',
                        // '새록' 제목을 뺀 뒤로 이 문구가 화면의 제목이다.
                        style: AppTypography.sectionTitle,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      // 어르신을 바꾸면 인사말부터 다시 시작한다.
                      if (roomy)
                        Flexible(child: HomeTalk(key: ValueKey(profileKey)))
                      else
                        HomeTalk(key: ValueKey(profileKey), mascotSize: 140),
                    ],
                  );
                  const alignment = Alignment(0, -0.2);
                  if (roomy) return Align(alignment: alignment, child: content);
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: box.maxHeight),
                      child: Align(alignment: alignment, child: content),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `오늘의 대화카드 받기`. 카드 화면으로 가기 전에 여기서 쓸 묶음을 준비한다.
///
/// 바로 쓸 묶음이 있으면 카드 화면으로 간다. 만들어야 하면(처음, 다 쓴 뒤,
/// 받은 뒤 정보를 고친 뒤) 이 버튼이 도는 표시로 바뀌고, 그동안 일대기나
/// 프로필을 볼 수 있다. 다 되면 알림창으로 알리고 카드 화면으로 데려가지
/// 않는다. 보호자가 다른 화면에 있을 수 있어서다. 다시 누르면 들어간다.
/// 실패는 버튼 아래 빨간 글로 남긴다. 알림창은 버튼을 가린다.
///
/// 받은 뒤 정보를 고친 묶음이면 옛 카드를 보여주지 않고 12장을 모두 새로
/// 만든다(2026-11-01 #171 에서 PM 확인). 만드는 동안 버튼 아래 회색 상자에
/// 까닭을 둔다.
///
/// 버튼은 지금 고른 어르신의 상태를 보여준다. 다른 분으로 바꿔도 앞의 분은
/// 서버와 앱 모두에서 이어서 만든다.
class _CardButton extends ConsumerWidget {
  const _CardButton({required this.needsProfile});

  final void Function(VoidCallback open) needsProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileId = ref.watch(serverProfileIdProvider).value;
    final generation = profileId == null
        ? null
        : ref.watch(cardGenerationProvider(profileId));
    final loading = generation?.isLoading ?? false;
    // 상태를 묻는 짧은 동안은 모양을 바꾸지 않는다. 이미 준비됐으면 곧 카드
    // 화면으로 가므로 바꾸면 깜빡인다. 그동안 다시 눌러도 생성 흐름이 무시한다.
    final stage = loading
        ? ref.watch(cardMakingProvider(profileId!))
        : CardMaking.checking;
    final making = stage != CardMaking.checking;
    // 만드는 동안은 지난 결과를 보이지 않는다.
    final notice = profileId == null || loading
        ? null
        : ref.watch(cardNoticeProvider(profileId));
    final name = ref.watch(profileProvider).value?.profile.name;

    return Column(
      children: [
        PrimaryButton(
          label: making ? '대화 카드를 만들고 있어요' : '오늘의 대화카드 받기',
          loading: making,
          onPressed: () => needsProfile(() => _getCards(context, ref)),
        ),
        if (stage == CardMaking.remaking) ...[
          const SizedBox(height: AppSpacing.md),
          const _RemakingNotice(),
        ] else if (notice != null) ...[
          const SizedBox(height: AppSpacing.md),
          _CardResult(notice: notice, name: name),
        ],
      ],
    );
  }

  Future<void> _getCards(BuildContext context, WidgetRef ref) async {
    // 기다리는 동안 볼 이야기를 말풍선에 꺼낸다.
    ref.read(homeTalkNudgeProvider.notifier).nudge();
    // 이미 읽은 값이 있으면 기다리지 않는다. 누르자마자 버튼이 돌게 한다.
    final profileId =
        ref.read(serverProfileIdProvider).value ??
        await ref.read(serverProfileIdProvider.future);
    if (profileId == null || !context.mounted) return;
    final name = ref.read(profileProvider).value?.profile.name;
    final provider = cardGenerationProvider(profileId);
    final notice = ref.read(cardNoticeProvider(profileId).notifier)..set(null);

    final waited = await ref.read(provider.notifier).prepare();
    if (!context.mounted) return;
    final result = ref.read(provider);
    // 다른 흐름이 이어서 묻는 중이거나, 로그아웃으로 지웠다.
    if (result.isLoading || !result.hasValue && !result.hasError) return;

    final status = result.value;
    final opens =
        !result.hasError &&
        (status == CardGenerationStatus.ready ||
            status == CardGenerationStatus.inVisit);
    final stillSelected = ref.read(serverProfileIdProvider).value == profileId;
    if (opens && !waited && stillSelected) {
      unawaited(context.push(AppRoutes.cards));
      return;
    }

    // 다 만든 것은 알림창으로 알린다. 기다리는 동안 다른 화면에 있어도 보인다.
    if (opens) {
      final who = name == null ? '' : '$name 어르신의 ';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('$who대화 카드가 준비됐어요.')));
      return;
    }

    // 실패는 버튼 아래에 빨간 글로 남긴다. 알림창은 버튼을 가려 "다시 누르면"
    // 이라고 하는 동안 누를 버튼이 보이지 않았다.
    notice.set(switch (result) {
      AsyncError(error: ApiNetworkFailure()) => CardNotice.offline,
      AsyncError() => CardNotice.error,
      _ when status == CardGenerationStatus.failed => CardNotice.failed,
      _ => null,
    });
  }
}

/// 받은 뒤 정보를 고친 묶음을 새로 만드는 까닭이다. 버튼 바로 아래 연한 회색
/// 상자에 둔다(#171 코멘트의 예시 화면).
class _RemakingNotice extends StatelessWidget {
  const _RemakingNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 22, color: AppColors.textSub),
          SizedBox(width: AppSpacing.md),
          // 낱말 가운데서 줄이 바뀌지 않게 끊을 곳을 정한다.
          Expanded(
            child: Text(
              '카드를 받은 뒤 어르신 정보가 바뀌어서\n'
              '대화 카드를 새로 만들고 있어요.',
              style: AppTypography.sub,
            ),
          ),
        ],
      ),
    );
  }
}

/// 버튼을 누른 결과다. 실패와 연결 끊김은 경고라 빨간 글로 쓴다.
class _CardResult extends StatelessWidget {
  const _CardResult({required this.notice, required this.name});

  final CardNotice notice;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final who = name == null ? '' : '$name 어르신의 ';
    final message = switch (notice) {
      // 4-2 는 실패 이유를 주지 않으므로 공통 문구만 둔다.
      CardNotice.failed => '$who대화 카드를 만들지 못했어요.\n다시 누르면 새로 만들어요.',
      CardNotice.offline => '서버에 연결하지 못했어요.\n인터넷 연결을 확인한 뒤 다시 눌러주세요.',
      CardNotice.error => '대화 카드를 불러오지 못했어요.\n잠시 후 다시 눌러주세요.',
    };
    return Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: AppTypography.sub.copyWith(color: AppColors.danger),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.hasNotice, required this.onNotice});

  final bool hasNotice;
  final VoidCallback onNotice;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      // 알약이 상태바에 붙어 보이지 않게 위를 띄운다. 양 끝 아이콘은 버튼 안쪽
      // 여백이 있어 좌우는 덜 띄운다. 오른쪽 아이콘이 없을 때의 알약 간격은
      // [_ProfileSwitcher] 가 채운다.
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.sm,
          0,
        ),
        child: ConstrainedBox(
          // 글자를 키워 알약이 높아지면 함께 늘어나도록 높이를 못 박지 않는다.
          constraints: const BoxConstraints(minHeight: AppSizes.topBar),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: onNotice,
                tooltip: '알림',
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.notifications_none, size: 32),
                    if (hasNotice)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: AppColors.danger,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.background,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const _ProfileSwitcher(),
            ],
          ),
        ),
      ),
    );
  }
}

/// 지금 보고 있는 어르신과 어르신을 바꾸는 버튼이다.
///
/// 사진만으로는 같은 성별의 어르신을 구분할 수 없어 이름을 함께 둔다. 다른
/// 어르신의 대화 카드를 받는 실수를 막으려는 자리다.
///
/// 원형 화살표는 목록 순서대로 다음 어르신으로 바로 바꾼다. 어르신이 한
/// 분이면 바꿀 대상이 없어 두지 않는다.
///
/// 등록한 어르신이 없으면 같은 자리에 `어르신 등록` 알약을 둔다. 누르면 함께
/// 하는 소중한 분 화면으로 간다.
class _ProfileSwitcher extends ConsumerWidget {
  const _ProfileSwitcher();

  static const _photo = 32.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasProfile = ref.watch(
      careProfilesProvider.select((p) => p.hasSelected),
    );
    final profile = ref.watch(profileProvider).value?.profile;
    final canSwitch = ref.watch(
      careProfilesProvider.select((p) => p.ready.length > 1),
    );
    if (!hasProfile) return const _RegisterPill();
    if (profile == null) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 누르면 어르신을 고르는 화면으로 간다.
        Material(
          color: AppColors.surface,
          shape: const StadiumBorder(side: BorderSide(color: AppColors.line)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push(AppRoutes.profileSwitch),
            child: Container(
              constraints: const BoxConstraints(minHeight: AppSizes.minTouch),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.xs,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ProfileAvatar(gender: profile.gender, size: _photo),
                  const SizedBox(width: AppSpacing.sm),
                  ConstrainedBox(
                    // 이름이 길어도 알림 아이콘을 밀어내지 않게 폭을 묶는다.
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      '${profile.name} 어르신',
                      style: AppTypography.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // 엄지가 닿기 쉬운 오른쪽 끝에 둔다.
        if (canSwitch)
          IconButton(
            onPressed: () => _switchToNext(context, ref),
            tooltip: '다음 분 보기',
            // 알림 아이콘과 같은 크기다.
            icon: const Icon(Icons.sync, size: 32),
          )
        else
          // 아이콘이 없으면 알약이 벽에 붙지 않게 화면 여백만큼 띄운다.
          const SizedBox(width: AppSpacing.screen - AppSpacing.sm),
      ],
    );
  }

  /// 다음 어르신으로 바꾸고 누구로 바뀌었는지 알린다.
  ///
  /// 한 번 누르면 바로 바뀌므로, 잘못 눌러도 알아챌 수 있게 이름을 말해 준다.
  Future<void> _switchToNext(BuildContext context, WidgetRef ref) async {
    ref.read(careProfilesProvider.notifier).selectNext();
    final next = await ref.read(profileProvider.future);
    if (next == null || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('지금부터 ${next.profile.name} 어르신과 함께해요')),
      );
  }
}

/// 등록한 어르신이 없을 때 알약 자리에 둔다. 어르신 알약과 같은 모양이다.
class _RegisterPill extends StatelessWidget {
  const _RegisterPill();

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 오른쪽 아이콘이 없을 때의 알약과 같은 간격이다.
      padding: const EdgeInsets.only(right: AppSpacing.screen - AppSpacing.sm),
      child: Material(
        color: AppColors.surface,
        shape: const StadiumBorder(side: BorderSide(color: AppColors.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(AppRoutes.profileSwitch),
          child: Container(
            constraints: const BoxConstraints(minHeight: AppSizes.minTouch),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 24, color: AppColors.ink),
                SizedBox(width: AppSpacing.xs),
                Text('어르신 등록', style: AppTypography.bodyStrong),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 배너 안의 글 묶음이다.
///
/// 날짜를 제목에 붙이면 어떤 문구로도 한 줄에 들어가지 않는다. 쓸 수 있는 폭이
/// 230 인데 가장 짧은 조합인 `8월 21일 리포트를 만들고 있어요` 가 323 이다.
/// 날짜를 위 줄로 빼고 제목을 짧게 둔다.
class _NoticeText extends StatelessWidget {
  const _NoticeText({
    required this.date,
    required this.title,
    required this.hint,
  });

  final String? date;
  final String title;

  /// 할 일이 없으면 `null` 이다.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (date != null) ...[
          Text(_friendlyDate(date!), style: AppTypography.caption),
          const SizedBox(height: AppSpacing.xs),
        ],
        Text(title, style: AppTypography.bodyStrong),
        if (hint != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(hint!, style: AppTypography.sub),
        ],
      ],
    );
  }
}

/// 리포트를 만드는 중임을 알리는 배너다.
///
/// 도착 배너와 같은 자리에 서고, 다 만들어지면 그 자리에서 도착 배너로 바뀐다.
/// 아직 들어갈 곳이 없으므로 누르지 않는다.
class _GeneratingNotice extends StatelessWidget {
  const _GeneratingNotice({required this.date});

  final String? date;

  static const _character = 64.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/images/logo.webp',
            width: _character,
            // 옆 글자가 같은 것을 말한다.
            excludeFromSemantics: true,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _NoticeText(
              date: date,
              title: '리포트를 만들고 있어요',
              hint: '조금만 기다려 주세요',
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ],
      ),
    );
  }
}

/// `2026-08-21` 을 `8월 21일 만남` 으로 바꾼다.
String _friendlyDate(String isoDate) {
  final parts = isoDate.split('-');
  if (parts.length != 3) return isoDate;
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (month == null || day == null) return isoDate;
  return '$month월 $day일 만남';
}

/// 리포트가 도착했음을 알리는 배너다. 이것을 눌러야 리포트로 들어간다.
class _ReportNotice extends StatelessWidget {
  const _ReportNotice({required this.date, required this.onTap});

  final String? date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          children: [
            const Icon(Icons.mail_outline, size: 32, color: AppColors.ink),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _NoticeText(
                date: date,
                title: '리포트가 도착했어요',
                hint: '눌러서 확인하기',
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSub),
          ],
        ),
      ),
    );
  }
}

/// 눌러서 이어갈 일이 있는 배너다. 앱을 떠난 사이 멈춘 면회 흐름
/// (`api-spec.md` 5-4 의 `evaluationPending`, `audioPending`)을 그 회차의 화면에서
/// 이어가고, 회차 상태를 묻지 못했으면 다시 묻는다.
class _ResumeNotice extends StatelessWidget {
  const _ResumeNotice({
    required this.date,
    required this.title,
    required this.hint,
    required this.onTap,
    this.icon = Icons.history,
  });

  final String? date;
  final String title;
  final String hint;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          children: [
            Icon(icon, size: 32, color: AppColors.ink),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _NoticeText(date: date, title: title, hint: hint),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSub),
          ],
        ),
      ),
    );
  }
}
