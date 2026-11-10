import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../design/tokens.dart';
import '../auth/auth_providers.dart';

/// 사진에서 나온 카드(`evidenceSource: photo`)의 그 사진.
///
/// 카드는 근거 사진의 ID 만 준다(4-3 `evidence` 의 `photoId`). 지금 어르신의
/// 프로필 사진(2-3)에서 같은 ID 의 주소를 찾아 작게 보여준다. 2026-11-10 E2E 에서
/// `이 사진은 어디서 찍으셨어요?` 카드가 사진 없이 나와 보호자가 다섯 장 중
/// 어느 사진인지 알 수 없었다.
///
/// 사진을 누르면 같은 앱 안에서 크게 본다. 작은 화면은 [compact] 버튼으로 연다.
/// 목록을 읽는 중이거나 사진을 열지 못한 경우에도 상태와 다시 시도할 길을 남긴다.
///
/// 목록 사진은 [largestHeight]에 기기 배율을 곱한 높이로 줄여 푼다.
/// 확대 화면은 별도로 더 큰 크기를 사용하되 각 변을 3072px 이하로 제한한다.
/// 서버 사진은 사진 ID로 기억해 주소가 갱신되어도 이미 받은 그림을 재사용한다.
class CardSourcePhoto extends ConsumerWidget {
  const CardSourcePhoto({
    required this.card,
    this.maxHeight = largestHeight,
    this.gap = AppSpacing.md,
    this.alignment = AlignmentDirectional.centerStart,
    this.compact = false,
    this.viewerStatus,
    super.key,
  }) : assert(maxHeight <= largestHeight);

  final ConversationCard card;
  final double maxHeight;
  final double gap;
  final AlignmentGeometry alignment;
  final bool compact;

  /// 면회 화면이 전달하는 읽기 전용 녹음 상태. 카드 선택 화면에서는 비워 둔다.
  final Widget? viewerStatus;

  /// 사진을 그리는 가장 큰 높이. 이 높이에 맞춰 사진을 푼다.
  static const largestHeight = 120.0;

  static const _assetScheme = 'asset:';

  /// 화면 낭독기가 읽는 이름이다.
  static const semanticLabel = '이 카드의 사진';

  /// [card] 의 근거 사진 중 [urls] 에 주소가 있는 첫 사진. 사진 카드가 아니거나
  /// 찾지 못하면 `null` 이다.
  static ({String photoId, String url})? sourceOf(
    ConversationCard card,
    Map<String, String> urls,
  ) {
    if (card.evidenceSource != 'photo') return null;
    for (final evidence in card.evidence) {
      final photoId = evidence['photoId'];
      final url = urls[photoId];
      if (photoId is String && url != null) return (photoId: photoId, url: url);
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (card.evidenceSource != 'photo') return const SizedBox.shrink();
    void open() {
      final owner = ref.read(_photoOwnerProvider);
      Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) =>
              _PhotoViewer(card: card, owner: owner, status: viewerStatus),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: gap),
      child: Align(
        alignment: alignment,
        child: compact
            ? _PhotoButton(label: '사진 보기', onPressed: open)
            : _PhotoContent(card: card, maxHeight: maxHeight, onOpen: open),
      ),
    );
  }
}

typedef _PhotoOwner = (String?, String?);

final _photoOwnerProvider = Provider<_PhotoOwner>(
  (ref) => (
    ref.watch(sessionProvider.select((session) => session?.account.accountId)),
    ref.watch(careProfilesProvider.select((profiles) => profiles.selected?.id)),
  ),
);

class _PhotoButton extends StatelessWidget {
  const _PhotoButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: const Icon(Icons.photo_outlined),
    label: Text(label, textAlign: TextAlign.center),
    style: OutlinedButton.styleFrom(
      foregroundColor: HomeColors.accent,
      side: const BorderSide(color: HomeColors.outline),
      minimumSize: const Size(48, 48),
      textStyle: Theme.of(
        context,
      ).textTheme.labelLarge?.merge(AppTypography.button),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
  );
}

class _PhotoContent extends ConsumerStatefulWidget {
  const _PhotoContent({
    required this.card,
    required this.maxHeight,
    this.onOpen,
  });
  final ConversationCard card;
  final double maxHeight;
  final VoidCallback? onOpen;

  @override
  ConsumerState<_PhotoContent> createState() => _PhotoContentState();
}

class _PhotoContentState extends ConsumerState<_PhotoContent> {
  int _retry = 0;
  bool _reloading = false;

  Future<void> _reload() async {
    if (_reloading) return;
    setState(() {
      _retry++;
      _reloading = true;
    });
    try {
      ref.invalidate(cardPhotoUrlsProvider);
      await ref.read(cardPhotoUrlsProvider.future);
    } catch (_) {
      // 오류 원문과 임시 사진 주소는 표시하지 않는다. 아래 상태 안내로 전환한다.
    } finally {
      if (mounted) setState(() => _reloading = false);
    }
  }

  Widget _notice(String message, {bool loading = false}) {
    // 카드 위에서는 확대 화면에서 상태와 재시도를 볼 수 있게 한다.
    if (widget.onOpen != null) {
      return _PhotoButton(label: message, onPressed: widget.onOpen!);
    }
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screen),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading) const CircularProgressIndicator(),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              style: AppTypography.body,
              textAlign: TextAlign.center,
            ),
            if (!loading) ...[
              const SizedBox(height: AppSpacing.md),
              _PhotoButton(label: '사진 다시 불러오기', onPressed: _reload),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final urls = ref.watch(cardPhotoUrlsProvider);
    if (_reloading ||
        (urls.isLoading && (!urls.hasValue || !urls.isRefreshing))) {
      return _notice('사진을 불러오고 있어요', loading: true);
    }
    final source = CardSourcePhoto.sourceOf(
      widget.card,
      urls.value ?? const {},
    );
    if (source == null) {
      return _notice(urls.hasError ? '사진을 불러오지 못했어요' : '이 카드의 사진을 찾을 수 없어요');
    }
    final asset = source.url.startsWith(CardSourcePhoto._assetScheme);
    final ImageProvider provider = asset
        ? AssetImage(source.url.substring(CardSourcePhoto._assetScheme.length))
        : _CardPhotoImage(photoId: source.photoId, url: source.url);
    final large = widget.onOpen == null;
    final decodeHeight =
        ((large ? widget.maxHeight * 2 : CardSourcePhoto.largestHeight) *
                MediaQuery.devicePixelRatioOf(context))
            .clamp(1, 3072)
            .round();
    return Image(
      key: ValueKey((source.photoId, source.url, _retry)),
      image: ResizeImage(
        provider,
        height: decodeHeight,
        width: large
            ? (MediaQuery.sizeOf(context).width *
                      2 *
                      MediaQuery.devicePixelRatioOf(context))
                  .clamp(1, 3072)
                  .round()
            : null,
        policy: ResizeImagePolicy.fit,
        allowUpscaling: false,
      ),
      fit: BoxFit.contain,
      semanticLabel: CardSourcePhoto.semanticLabel,
      frameBuilder: (context, child, frame, _) {
        if (frame == null) return _notice('사진을 불러오고 있어요', loading: true);
        if (large) {
          return InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: SizedBox.expand(child: child),
          );
        }
        return Semantics(
          button: true,
          label: '사진 크게 보기',
          child: Tooltip(
            message: '사진 크게 보기',
            child: InkWell(
              onTap: widget.onOpen,
              borderRadius: BorderRadius.circular(AppRadius.image),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: 48,
                  minWidth: 48,
                  maxHeight: widget.maxHeight,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.image),
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      child,
                      const ExcludeSemantics(
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: HomeColors.bubble),
                          child: Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.open_in_full,
                              color: HomeColors.accent,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stack) {
        if (!asset) {
          Future.microtask(() {
            if (mounted) {
              ref.read(cardPhotoUrlsProvider.notifier).imageFailed(source.url);
            }
          });
        }
        return _notice('사진을 열지 못했어요');
      },
    );
  }
}

class _PhotoViewer extends ConsumerWidget {
  const _PhotoViewer({required this.card, required this.owner, this.status});
  final ConversationCard card;
  final _PhotoOwner owner;
  final Widget? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sameOwner = ref.watch(_photoOwnerProvider) == owner;
    return Scaffold(
      backgroundColor: HomeColors.background,
      appBar: AppBar(
        backgroundColor: HomeColors.background,
        automaticallyImplyLeading: false,
        toolbarHeight: (MediaQuery.textScalerOf(context).scale(18) * 1.5 + 16)
            .clamp(56, double.infinity)
            .toDouble(),
        titleTextStyle: Theme.of(
          context,
        ).textTheme.bodyLarge?.merge(AppTypography.bodyStrong),
        title: const Text('사진 보기'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('닫기'),
          ),
        ],
      ),
      body: SafeArea(
        child: sameOwner
            ? LayoutBuilder(
                builder: (context, box) => Column(
                  children: [
                    if (status != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.screen,
                          vertical: AppSpacing.sm,
                        ),
                        child: status,
                      ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) =>
                            _PhotoContent(card: card, maxHeight: box.maxHeight),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.all(AppSpacing.sm),
                      child: Text(
                        '두 손가락으로 사진을 확대할 수 있어요',
                        style: AppTypography.caption,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    // 긴 질문은 이 영역만 스크롤해 사진과 닫기를 계속 볼 수 있게 한다.
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: box.maxHeight * 0.30,
                      ),
                      child: ColoredBox(
                        color: HomeColors.bubble,
                        child: SizedBox(
                          width: double.infinity,
                          child: SingleChildScrollView(
                            primary: false,
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.lg),
                              child: Text(
                                card.primaryQuestion,
                                style: AppTypography.bodyStrong,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : const Center(
                child: Text(
                  '계정이나 어르신이 바뀌어 사진을 닫아주세요.',
                  style: AppTypography.body,
                ),
              ),
      ),
    );
  }
}

/// 서버 사진 한 장. 그림은 주소가 아니라 사진 ID 로 기억한다.
///
/// 같은 사진의 주소는 다시 읽을 때마다 바뀐다(서명한 임시 주소). 주소로 기억하면
/// 주소를 새로 받을 때마다 원본을 다시 내려받고, 그동안 사진이 사라졌다
/// 나타난다. 열지 못한 그림은 [ResizeImage] 가 잊어서 새 주소로 다시 연다.
@immutable
class _CardPhotoImage extends ImageProvider<_CardPhotoKey> {
  const _CardPhotoImage({required this.photoId, required this.url});

  final String photoId;
  final String url;

  @override
  Future<_CardPhotoKey> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture((cardPhotoId: photoId));

  @override
  ImageStreamCompleter loadImage(
    _CardPhotoKey key,
    ImageDecoderCallback decode,
  ) {
    final network = NetworkImage(url);
    return network.loadImage(network, decode);
  }

  // 주소가 바뀌면 다른 provider 다. 열지 못한 그림을 새 주소로 다시 열게 한다.
  @override
  bool operator ==(Object other) =>
      other is _CardPhotoImage && other.photoId == photoId && other.url == url;

  @override
  int get hashCode => Object.hash(photoId, url);
}

typedef _CardPhotoKey = ({String cardPhotoId});
