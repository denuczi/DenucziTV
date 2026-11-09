import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';

import 'package:provider/provider.dart';

import '../../../core/models/app_controller.dart';
import '../../library/domain/media_models.dart';
import '../domain/library_item.dart';

class FavoriteToggleButton extends StatefulWidget {
  const FavoriteToggleButton({super.key, required this.media});
  final MediaEntry media;

  @override
  State<FavoriteToggleButton> createState() => _FavoriteToggleButtonState();
}

class _FavoriteToggleButtonState extends State<FavoriteToggleButton> {
  bool _busy = false;

  Future<void> _toggle() async {
    final app = context.read<AppController>();
    if (widget.media.sourceScope.isNotEmpty && !app.canUseMedia(widget.media)) {
      return;
    }
    final library = app.personalLibrary;
    if (library == null || _busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await library.toggleFavorite(widget.media);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.favoriteUpdateFailed)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = context.read<AppController>().personalLibrary;
    if (library == null ||
        widget.media.kind == LibraryKind.live ||
        widget.media.seriesId != null) {
      return const SizedBox.shrink();
    }
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final saved = library.isFavorite(widget.media);
        return IconButton(
          key: const Key('favoriteToggle'),
          tooltip: saved
              ? context.l10n.removeFromFavorites
              : context.l10n.addToFavorites,
          onPressed: _busy ? null : _toggle,
          icon: Icon(
            saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: saved ? Theme.of(context).colorScheme.error : null,
          ),
        );
      },
    );
  }
}

class EpisodeWatchedButton extends StatefulWidget {
  const EpisodeWatchedButton({
    super.key,
    required this.episode,
    required this.seriesTitle,
  });
  final MediaEntry episode;
  final String seriesTitle;

  @override
  State<EpisodeWatchedButton> createState() => _EpisodeWatchedButtonState();
}

class _EpisodeWatchedButtonState extends State<EpisodeWatchedButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final library = context.read<AppController>().personalLibrary;
    final accountId = context.read<AppController>().activeAccount?.id;
    if (library == null || accountId == null) {
      return const SizedBox.shrink();
    }
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final watched = library.history.any(
          (entry) =>
              entry.kind == LibraryKind.series &&
              entry.mediaId == widget.episode.id &&
              entry.sourceScope == widget.episode.sourceScope &&
              entry.completed,
        );
        final dark = Theme.of(context).brightness == Brightness.dark;
        return IconButton(
          style: IconButton.styleFrom(
            fixedSize: const Size.square(40),
            minimumSize: const Size.square(40),
            maximumSize: const Size.square(40),
            visualDensity: VisualDensity.standard,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: EdgeInsets.zero,
            backgroundColor: watched
                ? (dark ? const Color(0xFF123D28) : const Color(0xFFD8F3DC))
                : null,
            foregroundColor: watched
                ? (dark ? const Color(0xFF8FE3AA) : const Color(0xFF176239))
                : null,
          ),
          tooltip: watched
              ? context.l10n.markEpisodeUnwatched
              : context.l10n.markEpisodeWatched,
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    await library.markWatched(
                      LibraryItem.fromMedia(
                        accountId: accountId,
                        media: widget.episode,
                        seriesTitle: widget.seriesTitle,
                      ),
                      !watched,
                    );
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(context.l10n.watchedStatusFailed),
                        ),
                      );
                    }
                  } finally {
                    if (mounted) {
                      setState(() => _busy = false);
                    }
                  }
                },
          icon: Icon(
            watched ? Icons.check_circle_rounded : Icons.check_circle_outline,
          ),
        );
      },
    );
  }
}
