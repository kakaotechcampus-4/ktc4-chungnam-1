/// 구글 로그인 버튼.
///
/// 구글이 배포한 버튼 이미지를 그대로 쓴다. 색을 바꾸거나 비율을 늘이지 않는다.
/// 쓰는 이미지는 글자가 없는 동그란 것이라, 무엇을 하는 버튼인지는 아래 한 줄과
/// 스크린 리더용 이름으로 알린다.
library;

import 'package:flutter/material.dart';

import '../../design/tokens.dart';

class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    required this.onPressed,
    this.busy = false,
    super.key,
  });

  /// `null` 이면 누를 수 없는 상태로 흐리게 보여준다.
  final VoidCallback? onPressed;

  /// 로그인을 기다리는 중이다. 버튼 자리에 진행 표시를 둔다.
  final bool busy;

  static const asset =
      'assets/signin-assets/Android/png@4x/light/android_light_rd_na@4x.png';

  static const label = '구글 계정으로 로그인';

  /// 이미지가 정사각형(@4x 기준 160x160)이라 가로세로를 같게 둔다.
  /// 구글 기준 최소 높이는 40 이고, 여기서는 누르는 요소 최소 48 에 맞춘다.
  static const _size = AppSizes.minTouch;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;

    return Column(
      children: [
        SizedBox(
          width: _size,
          height: _size,
          child: busy
              ? const Padding(
                  padding: EdgeInsets.all(AppSpacing.sm),
                  child: CircularProgressIndicator(strokeWidth: 3),
                )
              // 그림뿐인 버튼이라 읽어 줄 이름을 붙인다. 이름과 누름이 한 덩어리로
              // 읽히도록 묶는다. 나누면 스크린 리더가 이름 없는 버튼으로 읽는다.
              : MergeSemantics(
                  child: Semantics(
                    button: true,
                    enabled: enabled,
                    label: label,
                    child: InkWell(
                      onTap: onPressed,
                      customBorder: const CircleBorder(),
                      child: Opacity(
                        opacity: enabled ? 1 : 0.4,
                        child: Image.asset(
                          asset,
                          width: _size,
                          height: _size,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          busy ? '로그인하는 중이에요' : label,
          style: AppTypography.sub,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
