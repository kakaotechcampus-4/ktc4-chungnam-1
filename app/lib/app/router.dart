import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/auth_api.dart';
import '../data/providers.dart';
import '../features/auth/google_consent_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/cards/cards_screen.dart';
import '../features/home/home_screen.dart';
import '../features/home/notice_screen.dart';
import '../features/life_story/life_story.dart';
import '../features/life_story/life_story_book_screen.dart';
import '../features/life_story/life_story_category_screen.dart';
import '../features/life_story/life_story_cover_screen.dart';
import '../features/life_story/life_story_edit_screen.dart';
import '../features/life_story/life_story_story_screen.dart';
import '../features/profile/profile_basic_edit_screen.dart';
import '../features/profile/profile_delete_screen.dart';
import '../features/profile/profile_details_edit_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile/profile_switch_screen.dart';
import '../features/profile_setup/onboarding_screen.dart';
import '../features/report/changes_screen.dart';
import '../features/report/story_edit_screen.dart';
import '../features/report/report_list_screen.dart';
import '../features/report/report_screen.dart';
import '../features/review/comfort_screen.dart';
import '../features/review/review_screen.dart';
import '../features/review/upload_retry_screen.dart';
import '../features/profile_setup/profile_setup_screen.dart';
import '../features/visit/add_cards_screen.dart';
import '../features/visit/record_screen.dart';
import '../features/visit/visit_photo_screen.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/app_states.dart';
import '../widgets/care_profiles_loading.dart';
import 'routes.dart';

/// 화면 이동을 한곳에 선언한다. 화면이 늘어나면 여기에 경로도 함께 등록한다.
GoRouter buildRouter() {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => SplashScreen(
          // 같은 경로로 다시 오면 화면을 새로 만들어 복원 확인을 다시 한다.
          key: ValueKey(state.uri.toString()),
          signedOut: state.uri.queryParameters['signedOut'] == 'true',
        ),
      ),
      GoRoute(
        path: AppRoutes.googleConsent,
        builder: (context, state) {
          final pending = state.extra;
          // 등록 정보는 스플래시의 로그인 버튼에서만 넘어온다. 주소로 직접 들어오거나 앱을
          // 다시 띄우면 비어 있으므로, 빈 동의 화면을 보여주지 않고 되돌린다.
          if (pending is! ConsentRequiredResult) {
            return Scaffold(
              appBar: const AppTopBar(title: '약관 동의'),
              body: ErrorStateView(
                message: '로그인 정보가 없어요.\n로그인부터 다시 해주세요.',
                onRetry: () => context.go(AppRoutes.signIn),
              ),
            );
          }
          return GoogleConsentScreen(pending: pending);
        },
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.profileCreate,
        builder: (context, state) =>
            ProfileSetupScreen(addingId: state.uri.queryParameters['adding']),
      ),
      GoRoute(
        path: AppRoutes.home,
        // 서버에서 어르신을 불러오기 전에는 등록 안내를 띄우지 않는다.
        builder: (context, state) =>
            const CareProfilesLoading(child: HomeScreen()),
      ),
      GoRoute(
        path: AppRoutes.cards,
        builder: (context, state) => const _NeedsProfile(child: CardsScreen()),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        builder: (context, state) => const _NeedsProfile(child: NoticeScreen()),
      ),
      GoRoute(
        path: AppRoutes.visitPhoto,
        builder: (context, state) =>
            const _NeedsProfile(child: VisitPhotoScreen()),
      ),
      GoRoute(
        path: AppRoutes.visitRecord,
        builder: (context, state) => const _NeedsProfile(child: RecordScreen()),
      ),
      GoRoute(
        path: AppRoutes.visitAddCards,
        builder: (context, state) =>
            const _NeedsProfile(child: AddCardsScreen()),
      ),
      GoRoute(
        path: AppRoutes.visitReview,
        builder: (context, state) => _NeedsProfile(
          child: ReviewScreen(sessionId: state.uri.queryParameters['session']),
        ),
      ),
      GoRoute(
        path: AppRoutes.visitUpload,
        builder: (context, state) => _NeedsProfile(
          child: UploadRetryScreen(
            sessionId: state.uri.queryParameters['session'],
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.visitReviewDone,
        builder: (context, state) =>
            const _NeedsProfile(child: ComfortScreen()),
      ),
      GoRoute(
        path: AppRoutes.report,
        builder: (context, state) => _NeedsProfile(
          child: ReportScreen(reportId: state.pathParameters['reportId'] ?? ''),
        ),
      ),
      GoRoute(
        path: AppRoutes.reportChanges,
        builder: (context, state) => _NeedsProfile(
          child: ReportChangesScreen(
            reportId: state.pathParameters['reportId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.storyEdit,
        builder: (context, state) {
          // 고칠 이야기는 변경 사항 확인에서만 넘어온다. 주소로 직접 들어오거나
          // 앱을 다시 띄우면 비어 있다.
          final initial = state.extra;
          if (initial is! StoryDraft) {
            return const _NeedsProfile(child: StoryEditMissingView());
          }
          return _NeedsProfile(child: StoryEditScreen(initial: initial));
        },
      ),
      GoRoute(
        path: AppRoutes.profile,
        builder: (context, state) =>
            const CareProfilesLoading(withTopBar: true, child: ProfileScreen()),
      ),
      GoRoute(
        path: AppRoutes.profileEditBasic,
        builder: (context, state) =>
            const _NeedsProfile(child: ProfileBasicEditScreen()),
      ),
      GoRoute(
        path: AppRoutes.profileEditDetails,
        builder: (context, state) =>
            const _NeedsProfile(child: ProfileDetailsEditScreen()),
      ),
      GoRoute(
        path: AppRoutes.profileSwitch,
        builder: (context, state) => const CareProfilesLoading(
          withTopBar: true,
          child: ProfileSwitchScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.profileDelete,
        builder: (context, state) => const ProfileDeleteScreen(),
      ),
      GoRoute(
        path: AppRoutes.reports,
        builder: (context, state) =>
            const _NeedsProfile(child: ReportListScreen()),
      ),
      GoRoute(
        path: AppRoutes.album,
        builder: (context, state) =>
            const _NeedsProfile(child: LifeStoryCoverScreen()),
      ),
      GoRoute(
        path: AppRoutes.albumBook,
        builder: (context, state) =>
            const _NeedsProfile(child: LifeStoryBookScreen()),
      ),
      GoRoute(
        path: AppRoutes.albumCategory,
        builder: (context, state) => _NeedsProfile(
          child: _withCategory(
            state,
            (category) => LifeStoryCategoryScreen(category: category),
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.albumStoryNew,
        builder: (context, state) =>
            const _NeedsProfile(child: LifeStoryEditScreen()),
      ),
      GoRoute(
        path: AppRoutes.albumStoryEdit,
        builder: (context, state) => _NeedsProfile(
          child: LifeStoryEditScreen(storyId: state.pathParameters['storyId']!),
        ),
      ),
      GoRoute(
        path: AppRoutes.albumStory,
        builder: (context, state) => _NeedsProfile(
          child: _withCategory(
            state,
            (category) => LifeStoryStoryScreen(
              category: category,
              storyId: state.pathParameters['storyId']!,
            ),
          ),
        ),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: const AppTopBar(title: '새록'),
      body: ErrorStateView(
        message: '찾을 수 없는 화면이에요.\n${state.uri}',
        onRetry: () => context.go(AppRoutes.home),
      ),
    ),
  );
}

/// 어르신을 고른 뒤에만 쓰는 화면이다. 대화 카드, 면회, 리포트, 알림과
/// 일대기 경로의 `:category` 를 읽는다. 모르는 분류면 화면 대신 안내를 띄운다.
Widget _withCategory(
  GoRouterState state,
  Widget Function(LifeStoryCategory category) builder,
) {
  final category = LifeStoryCategory.parse(state.pathParameters['category']!);
  if (category != null) return builder(category);
  return const Scaffold(
    appBar: AppTopBar(),
    body: EmptyStateView(message: '찾을 수 없는 이야기 묶음이에요.'),
  );
}

/// 일대기가 여기에 든다.
///
/// 화면 안의 버튼은 먼저 등록을 안내하므로 보통은 여기까지 오지 않는다.
/// 주소로 바로 들어오면 화면 대신 등록 안내를 보여준다.
class _NeedsProfile extends ConsumerWidget {
  const _NeedsProfile({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasProfile = ref.watch(
      careProfilesProvider.select((p) => p.hasSelected),
    );
    if (hasProfile) return child;

    // 불러오는 중이거나 실패했으면 등록 안내 대신 그 상태를 보여준다.
    return CareProfilesLoading(
      withTopBar: true,
      child: Scaffold(
      appBar: const AppTopBar(),
      body: EmptyStateView(
        message: '함께하는 소중한 분을 등록한 뒤\n이용할 수 있어요.',
        icon: Icons.person_add_alt_1_outlined,
        actionLabel: '등록하러 가기',
        onAction: () => context.pushReplacement(AppRoutes.profileSwitch),
      ),
      ),
    );
  }
}
