import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../design/tokens.dart';

/// 사진에서 나온 카드(`evidenceSource: photo`)의 그 사진.
///
/// 카드는 근거 사진의 ID 만 준다(4-3 `evidence` 의 `photoId`). 지금 어르신의
/// 프로필 사진(2-3)에서 같은 ID 의 주소를 찾아 작게 보여준다. 2026-11-10 E2E 에서
/// `이 사진은 어디서 찍으셨어요?` 카드가 사진 없이 나와 보호자가 다섯 장 중
/// 어느 사진인지 알 수 없었다.
///
/// 사진을 찾지 못했거나(지운 사진, 목록을 읽지 못함) 주소가 만료돼 열지 못하면
/// 아무것도 그리지 않는다. 깨진 그림 표시(`ProfilePhotoImage` 와 다르다)도 빈
/// 자리도 두지 않는다. 열지 못하면 주소를 다시 읽게 알린다
/// ([CardPhotoUrlsNotifier.imageFailed]). 사진이 그려지기 전에는 자리를 차지하지
/// 않고, 그려지면 아래에 [gap] 만큼 띄운다. 높이는 [maxHeight] 를 넘지 않고
/// 사진의 가로세로 비율을 지킨다. 글자 크기와 상관없다.
///
/// 올린 원본(최대 20MiB)을 그대로 풀지 않고 [largestHeight] 높이로 줄여 푼다.
/// 카드 화면은 녹음 화면 아래에 열린 채 남아 그 그림을 면회 내내 들고 있다.
/// 카드 시트는 남는 높이에 따라 더 작게 그리지만 같은 크기로 풀어 카드 화면이
/// 이미 푼 그림을 그대로 쓴다. 서버 사진은 주소가 아니라 사진 ID 로 그림을
/// 기억해, 주소를 새로 받아도 이미 받은 사진을 다시 내려받지 않는다.
class CardSourcePhoto extends ConsumerWidget {
  const CardSourcePhoto({
    required this.card,
    this.maxHeight = largestHeight,
    this.gap = AppSpacing.md,
    this.alignment = AlignmentDirectional.centerStart,
    super.key,
  }) : assert(maxHeight <= largestHeight);

  final ConversationCard card;
  final double maxHeight;
  final double gap;
  final AlignmentGeometry alignment;

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
    final urls = ref.watch(cardPhotoUrlsProvider).value;
    final source = urls == null ? null : sourceOf(card, urls);
    if (source == null) return const SizedBox.shrink();

    Widget shown(BuildContext context, Widget child, int? frame, bool _) {
      if (frame == null) return const SizedBox.shrink();
      return Padding(
        padding: EdgeInsets.only(bottom: gap),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.image),
            child: child,
          ),
        ),
      );
    }

    final asset = source.url.startsWith(_assetScheme);
    Widget nothing(BuildContext _, Object error, StackTrace? stack) {
      // 그리는 중에는 주소를 바꾸지 않고 그린 뒤에 알린다.
      if (!asset) {
        Future.microtask(() {
          if (context.mounted) {
            ref.read(cardPhotoUrlsProvider.notifier).imageFailed(source.url);
          }
        });
      }
      return const SizedBox.shrink();
    }

    final ImageProvider provider = asset
        ? AssetImage(source.url.substring(_assetScheme.length))
        : _CardPhotoImage(photoId: source.photoId, url: source.url);
    final decodeHeight =
        (largestHeight * MediaQuery.devicePixelRatioOf(context)).round();

    return Align(
      alignment: alignment,
      child: Image(
        image: ResizeImage(provider, height: decodeHeight),
        fit: BoxFit.contain,
        semanticLabel: semanticLabel,
        frameBuilder: shown,
        errorBuilder: nothing,
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
