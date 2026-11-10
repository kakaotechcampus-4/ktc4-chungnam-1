/// 구글 로그인 버튼.
///
/// 구글 G 그림과 `구글 계정으로 로그인` 글자를 한 버튼에 담는다. 글자를 눌러도
/// 로그인하고, 화면 낭독기는 이름 하나의 버튼으로 읽는다. 전에는 글자 없는 48
/// 짜리 동그라미 하나에 아래 글자가 따로 있어, 글자를 누르면 아무 일이 없었고
/// 같은 이름을 두 번 읽었다(2026-11-10 UX 점검 13번).
///
/// G 는 구글이 배포한 버튼 이미지를 그대로 쓴다. 색을 바꾸거나 비율을 늘이지
/// 않고 직접 그리지도 않는다. 면, 테두리와 글자 색은 구글 브랜딩 가이드라인의
/// 밝은 버튼 색이고(테두리는 배포 이미지의 동그라미 선과 같은 색), 높이와 모서리,
/// 글자 크기는 `app/DESIGN.md` 의 버튼 기준을 따른다.
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

  /// 로그인을 기다리는 중이다. G 자리에 진행 표시를 두고 누를 수 없게 한다.
  final bool busy;

  static const asset =
      'assets/signin-assets/Android/png@4x/light/android_light_rd_na@4x.png';

  static const label = '구글 계정으로 로그인';

  /// 흰 면의 테두리. 배포 이미지 동그라미 선과 같은 `#747775` 다.
  static const _stroke = Color(0xFF747775);

  /// 글자 색. 구글 밝은 버튼의 글자색이다(흰 면 대비 16.4:1).
  static const _text = Color(0xFF1F1F1F);

  /// 배포 이미지를 그리는 크기. @4x 160px 이라 40 이 제 크기다.
  static const _imageSize = 40.0;

  /// G 를 보여주는 칸. G 는 이미지 가운데 절반(20)을 차지하고, 동그라미 선은
  /// 가장자리에 있다. 가운데 24 만 보이면 G 가 온전히 들어가고 선은 보이지 않는다.
  static const _markSize = 24.0;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final text = busy ? '로그인하는 중이에요' : label;

    // 그림과 글자를 한 이름으로 읽는다. 누름과 초점은 아래 InkWell 이 이 항목에
    // 붙이고, 안쪽 글자는 따로 읽지 않게 막는다.
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: text,
      child: Opacity(
        // 기다리는 중은 누를 수 없지만 흐리게 하지 않는다. 비활성과 다르게 보인다.
        opacity: onPressed == null && !busy ? 0.4 : 1,
        child: Material(
          color: AppColors.background,
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.button)),
            side: BorderSide(color: _stroke),
          ),
          child: InkWell(
            onTap: enabled ? onPressed : null,
            child: ConstrainedBox(
              // 높이를 못 박지 않는다. 글자를 키워 한 줄이 높아지면 버튼도 늘어난다.
              constraints: const BoxConstraints(
                minWidth: double.infinity,
                minHeight: AppSizes.control,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: ExcludeSemantics(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox.square(
                        dimension: _markSize,
                        child: busy
                            ? const Padding(
                                padding: EdgeInsets.all(2),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const _GoogleMark(),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      // 좁은 화면에서 글자를 키우면 한 줄에 들어가지 않는다.
                      // `로그인` 이 `로` 와 `그인` 으로 갈라지지 않게 줄을 바꾸지
                      // 않고 줄인다. 아이콘이 있는 보조 버튼과 같다(`app/DESIGN.md`).
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            text,
                            style: AppTypography.button.copyWith(color: _text),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 배포 이미지의 가운데만 보여준다. 이미지는 제 크기로 그리고 잘라 보일 뿐
/// G 의 색과 모양은 그대로다.
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: OverflowBox(
        maxWidth: GoogleSignInButton._imageSize,
        maxHeight: GoogleSignInButton._imageSize,
        child: Image.asset(
          GoogleSignInButton.asset,
          width: GoogleSignInButton._imageSize,
          height: GoogleSignInButton._imageSize,
          fit: BoxFit.contain,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}
