import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';

import '../../../core/network/network_client.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/media_models.dart';
import '../domain/rating_format.dart';
import 'media_actions.dart';
import 'live_channel_number_notch.dart';

/// Keyboard-accessible desktop poster tile with separate artwork and metadata.
/// The entire tile is clickable; the hover affordance never covers the title.
class MediaCard extends StatefulWidget {
  const MediaCard({
    super.key,
    required this.entry,
    required this.network,
    required this.onOpen,
    this.showActions = false,
  });

  final MediaEntry entry;
  final NetworkClient network;
  final VoidCallback onOpen;
  final bool showActions;

  @override
  State<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<MediaCard> {
  bool _hovered = false;
  bool _focused = false;
  bool _actionMenuOpen = false;

  void _setActionMenuOpen(bool value) {
    if (mounted && _actionMenuOpen != value) {
      setState(() => _actionMenuOpen = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final actionColor = AppPalette.mediaAction(scheme);
    final media = widget.entry;
    final compactRating = formatCompactRating(media.rating);
    final channelNumber =
        media.kind == LibraryKind.live && (media.channelNumber ?? 0) > 0
        ? media.channelNumber
        : null;
    final openLabel = context.l10n.openMedia(switch (media.kind) {
      LibraryKind.live => context.l10n.liveTv,
      LibraryKind.movies => context.l10n.movies,
      LibraryKind.series => context.l10n.series,
    }, media.title);
    final uri = Uri.tryParse(media.imageUrl ?? '');
    final hasImage =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    final emphasized = _hovered || _focused;

    return Semantics(
      button: true,
      label: channelNumber == null
          ? openLabel
          : '${context.l10n.channelPosition(channelNumber)}. $openLabel',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: emphasized
                ? scheme.surfaceContainerHigh
                : scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: emphasized ? actionColor : scheme.outlineVariant,
              width: emphasized ? 1.5 : 1.0,
            ),
            boxShadow: emphasized
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.28),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : const [],
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const Key('mediaCardAction'),
              mouseCursor: SystemMouseCursors.click,
              onTap: widget.onOpen,
              onFocusChange: (value) => setState(() => _focused = value),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (hasImage)
                          Image.network(
                            uri.toString(),
                            headers: widget.network.imageHeaders,
                            fit: BoxFit.cover,
                            cacheWidth: 420,
                            filterQuality: FilterQuality.low,
                            errorBuilder: (context, error, stackTrace) =>
                                _fallback(scheme),
                          )
                        else
                          _fallback(scheme),
                        if (emphasized)
                          ColoredBox(
                            color: Colors.black.withValues(alpha: 0.16),
                          ),
                        Positioned(
                          right: 10,
                          bottom: 10,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: emphasized
                                  ? actionColor
                                  : Colors.black.withValues(alpha: 0.72),
                              borderRadius: BorderRadius.circular(28),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                media.kind == LibraryKind.live
                                    ? Icons.play_arrow_rounded
                                    : Icons.arrow_outward_rounded,
                                color: Colors.white,
                                size: 19,
                              ),
                            ),
                          ),
                        ),
                        if (widget.showActions &&
                            (emphasized || _actionMenuOpen))
                          Positioned(
                            right: 6,
                            top: 6,
                            // Keep the popup button alive when the pointer
                            // leaves the card while an action is in progress.
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: scheme.surface.withValues(alpha: 0.96),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: MediaActionMenu(
                                media: media,
                                onMenuOpened: () => _setActionMenuOpen(true),
                                onMenuClosed: () => _setActionMenuOpen(false),
                              ),
                            ),
                          ),
                        if (media.kind == LibraryKind.live)
                          Positioned(
                            left: 10,
                            top: 10,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: AppPalette.brandRed,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                child: Text(
                                  context.l10n.live,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: .7,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      12,
                      11,
                      12,
                      channelNumber == null ? 12 : 5,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          media.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: scheme.onSurface,
                                height: 1.3,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        if (channelNumber == null) ...[
                          const SizedBox(height: 7),
                          Row(
                            children: [
                              if (compactRating != null) ...[
                                const Icon(
                                  Icons.star_rounded,
                                  size: 13,
                                  color: AppPalette.amber,
                                ),
                                const SizedBox(width: 4),
                              ],
                              Expanded(
                                child: Text(
                                  compactRating ?? media.kind.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                        fontSize: 12.5,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (channelNumber != null)
                    ExcludeSemantics(
                      child: LiveChannelNumberNotch(number: channelNumber),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fallback(ColorScheme scheme) => ColoredBox(
    color: scheme.surfaceContainerHighest,
    child: Center(
      child: Icon(
        switch (widget.entry.kind) {
          LibraryKind.live => Icons.live_tv_outlined,
          LibraryKind.movies => Icons.movie_outlined,
          LibraryKind.series => Icons.video_library_outlined,
        },
        size: 44,
        color: scheme.onSurfaceVariant,
      ),
    ),
  );
}
