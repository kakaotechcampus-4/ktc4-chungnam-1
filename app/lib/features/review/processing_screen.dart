import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/providers.dart';
import '../../widgets/app_states.dart';

/// 소감을 제출하고 리포트가 만들어지는 동안 보여주는 화면이다.
///
/// 기획이 보류된 "보호자 토닥토닥"이 들어올 자리이기도 하다. 지금은 로딩 표시만
/// 둔다. `app/DESIGN.md` 상 앱에서 움직이는 것은 이 표시뿐이다.
///
/// 끝나면 홈으로 돌아가고 홈에 리포트 도착 알림이 뜬다.
class ProcessingScreen extends ConsumerStatefulWidget {
  const ProcessingScreen({super.key});

  @override
  ConsumerState<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends ConsumerState<ProcessingScreen> {
  /// 실제 분석 시간은 AI 영역이 정한다. 목 데이터에서는 이만큼만 보여준다.
  static const _delay = Duration(seconds: 3);

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_delay, () {
      if (!mounted) return;
      // 리포트가 도착했음을 홈에서 알린다.
      ref.read(reportNoticeProvider.notifier).show();
      context.go(AppRoutes.home);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: LoadingView(
          message: '오늘의 이야기를 정리하고 있어요.\n다 되면 알려드릴게요.',
        ),
      ),
    );
  }
}
