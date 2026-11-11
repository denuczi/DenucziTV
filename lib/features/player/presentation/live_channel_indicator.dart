import 'package:flutter/material.dart';

import '../../../core/network/network_client.dart';
import '../../../l10n/l10n_ext.dart';
import '../../library/domain/media_models.dart';
import '../../personal_library/domain/library_item.dart';

/// Short-lived, non-interactive information shown only after channel input
/// or a directional change. Not shown when playback first opens or retries.
@immutable
class LiveChannelNotice {
  const LiveChannelNotice.forDigits(this.number)
    : channel = null,
      message = null;

  const LiveChannelNotice.forChannel(this.channel)
    : number = null,
      message = null;

  const LiveChannelNotice.forMessage(this.message)
    : number = null,
      channel = null;

  final String? number;
  final MediaEntry? channel;
  final String? message;
}

class LiveChannelIndicator extends StatelessWidget {
  const LiveChannelIndicator({
    super.key,
    required this.notice,
    required this.network,
  });

  final LiveChannelNotice notice;
  final NetworkClient network;

  @override
  Widget build(BuildContext context) {
    final media = notice.channel;
    final number = media?.channelNumber;
    final image = media == null ? null : safeArtworkUrl(media.imageUrl);
    return Semantics(
      liveRegion: notice.number == null,
      label:
          notice.message ??
          (media == null
              ? notice.number
              : '${number == null ? '' : '${context.l10n.channelPosition(number)}. '}${media.title}'),
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xE9161920),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x33FFFFFF)),
            boxShadow: const [
              BoxShadow(color: Color(0x50000000), blurRadius: 14),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: media != null
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: image == null
                            ? const _LogoFallback()
                            : Image.network(
                                image,
                                key: ValueKey((media.sourceScope, media.id)),
                                headers: network.imageHeaders,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.low,
                                loadingBuilder: (context, child, progress) =>
                                    progress == null
                                    ? child
                                    : const _LogoFallback(),
                                errorBuilder: (context, error, trace) =>
                                    const _LogoFallback(),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (number != null)
                              Text(
                                context.l10n.channelPosition(number),
                                maxLines: 1,
                                style: const TextStyle(
                                  color: Color(0xFFD2D7E1),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            Text(
                              media.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : Text(
                    notice.number ?? notice.message ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: notice.number == null ? 14 : 28,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _LogoFallback extends StatelessWidget {
  const _LogoFallback();

  @override
  Widget build(BuildContext context) => const Center(
    child: Icon(Icons.live_tv_outlined, color: Colors.white70, size: 26),
  );
}
