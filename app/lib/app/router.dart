import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/cards/cards_screen.dart';
import '../features/home/home_screen.dart';
import '../features/profile_setup/onboarding_screen.dart';
import '../features/profile_setup/profile_setup_screen.dart';
import '../features/visit/add_cards_screen.dart';
import '../features/visit/record_screen.dart';
import '../features/visit/visit_photo_screen.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/app_states.dart';
import 'routes.dart';

/// 화면 이동을 한곳에 선언한다. 화면이 늘어나면 여기에 경로도 함께 등록한다.
///
/// 아직 만들지 않은 화면은 [PlaceholderView.upcoming] 으로 자리를 잡아 두었다.
/// 그 화면을 만들 때 이 파일의 `builder` 를 실제 화면으로 바꾼다.
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
        path: AppRoutes.signup,
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.profileCreate,
        builder: (context, state) => const ProfileSetupScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.cards,
        builder: (context, state) => const CardsScreen(),
      ),
      GoRoute(
        path: AppRoutes.visitPhoto,
        builder: (context, state) => const VisitPhotoScreen(),
      ),
      GoRoute(
        path: AppRoutes.visitRecord,
        builder: (context, state) => const RecordScreen(),
      ),
      GoRoute(
        path: AppRoutes.visitAddCards,
        builder: (context, state) => const AddCardsScreen(),
      ),
      GoRoute(
        path: AppRoutes.visitReview,
        builder: (context, state) => const _Upcoming(
          unit: 6,
          screen: '보호자 소감 작성',
          title: 'F',
        ),
      ),
      GoRoute(
        path: AppRoutes.visitProcessing,
        builder: (context, state) => const _Upcoming(
          unit: 6,
          screen: '리포트를 만드는 중',
          title: '로딩',
        ),
      ),
      GoRoute(
        path: AppRoutes.report,
        builder: (context, state) => const _Upcoming(
          unit: 6,
          screen: '리포트',
          title: 'G',
        ),
      ),
      GoRoute(
        path: AppRoutes.profile,
        builder: (context, state) => const _Upcoming(
          unit: 7,
          screen: '프로필 설정',
          title: '프로필 설정',
        ),
      ),
      GoRoute(
        path: AppRoutes.reports,
        builder: (context, state) => const _Upcoming(
          unit: 7,
          screen: '리포트 기록',
          title: '리포트 기록',
        ),
      ),
      // H 일대기는 기획이 보류된 화면이라 안내만 보여준다. 구현 대상이 아니다.
      GoRoute(
        path: AppRoutes.album,
        builder: (context, state) => const Scaffold(
          appBar: AppTopBar(title: '일대기'),
          body: PlaceholderView.designPending(),
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

/// 아직 만들지 않은 화면의 자리다. 단위 7이 끝나면 이 위젯은 사라진다.
class _Upcoming extends StatelessWidget {
  const _Upcoming({
    required this.unit,
    required this.screen,
    required this.title,
  });

  final int unit;
  final String screen;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: title),
      body: PlaceholderView.upcoming(unit: unit, screen: screen),
    );
  }
}
