import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/auth_api.dart';
import '../data/providers.dart';
import '../features/auth/google_consent_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/cards/cards_screen.dart';
import '../features/home/home_screen.dart';
import '../features/home/notice_screen.dart';
import '../features/profile/profile_delete_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile/profile_switch_screen.dart';
import '../features/profile_setup/onboarding_screen.dart';
import '../features/report/changes_screen.dart';
import '../features/report/report_list_screen.dart';
import '../features/report/report_screen.dart';
import '../features/review/comfort_screen.dart';
import '../features/review/review_screen.dart';
import '../features/profile_setup/profile_setup_screen.dart';
import '../features/visit/add_cards_screen.dart';
import '../features/visit/record_screen.dart';
import '../features/visit/visit_photo_screen.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/app_states.dart';
import 'routes.dart';

/// 화면 이동을 한곳에 선언한다. 화면이 늘어나면 여기에 경로도 함께 등록한다.
GoRouter buildRouter() {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.googleConsent,
        builder: (context, state) {
          final pending = state.extra;
          // 등록 정보는 로그인 화면에서만 넘어온다. 주소로 직접 들어오거나 앱을
          // 다시 띄우면 비어 있으므로, 빈 동의 화면을 보여주지 않고 되돌린다.
          if (pending is! ConsentRequiredResult) {
            return Scaffold(
              appBar: const AppTopBar(title: '약관 동의'),
              body: ErrorStateView(
                message: '로그인 정보가 없어요.\n로그인부터 다시 해주세요.',
                onRetry: () => context.go(AppRoutes.login),
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
        builder: (context, state) => const HomeScreen(),
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
        builder: (context, state) => const _NeedsProfile(child: ReviewScreen()),
      ),
      GoRoute(
        path: AppRoutes.visitReviewDone,
        builder: (context, state) =>
            const _NeedsProfile(child: ComfortScreen()),
      ),
      GoRoute(
        path: AppRoutes.report,
        builder: (context, state) => _NeedsProfile(
          child: ReportScreen(
            reportId: state.pathParameters['reportId'] ?? '',
            fromHistory: state.uri.queryParameters['from'] == 'history',
          ),
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
        path: AppRoutes.profile,
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.profileSwitch,
        builder: (context, state) => const ProfileSwitchScreen(),
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
      // H 일대기는 기획이 보류된 화면이라 안내만 보여준다. 구현 대상이 아니다.
      GoRoute(
        path: AppRoutes.album,
        builder: (context, state) => const _NeedsProfile(
          child: Scaffold(
            appBar: AppTopBar(title: '일대기'),
            body: PlaceholderView.designPending(),
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

    return Scaffold(
      appBar: const AppTopBar(),
      body: EmptyStateView(
        message: '함께하는 소중한 분을 등록한 뒤\n이용할 수 있어요.',
        icon: Icons.person_add_alt_1_outlined,
        actionLabel: '등록하러 가기',
        onAction: () => context.pushReplacement(AppRoutes.profileSwitch),
      ),
    );
  }
}
