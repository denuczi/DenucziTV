import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';

import 'package:provider/provider.dart';

import '../../../core/models/app_controller.dart';
import '../../../shared/navigation/dialog_launch_guard.dart';
import '../../library/domain/media_models.dart';
import '../../library/presentation/media_details_dialog.dart';
import '../../library/presentation/series_dialog.dart';
import '../../player/presentation/player_dialog.dart';
import '../application/personal_library_controller.dart';
import '../domain/library_item.dart';

enum _View { continueWatching, favorites, history }

/// Personal, local, account-scoped library. Pages only build visible rows.
class MyLibraryPage extends StatefulWidget {
  const MyLibraryPage({super.key});

  @override
  State<MyLibraryPage> createState() => _MyLibraryPageState();
}

class _MyLibraryPageState extends State<MyLibraryPage> {
  _View _view = _View.continueWatching;
  bool _busy = false;
  final DialogLaunchGuard _playbackGuard = DialogLaunchGuard();

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.libraryUpdateFailed)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _open(LibraryItem item) async {
    await _playbackGuard.run(() => _openItem(item));
  }

  Future<void> _openItem(LibraryItem item) async {
    final app = context.read<AppController>();
    final credentials = app.credentials;
    if (credentials == null || app.activeAccount?.id != item.accountId) {
      return;
    }
    try {
      if (item.isEpisode) {
        final seriesId = item.seriesId!;
        final details = await app.api.seriesDetails(credentials, seriesId);
        if (!mounted || app.activeAccount?.id != item.accountId) {
          return;
        }
        final queue = [
          for (final episode in details.playbackQueue)
            episode.withSeries(seriesId),
        ];
        final index = queue.indexWhere((episode) => episode.id == item.mediaId);
        if (index < 0) {
          _notify(context.l10n.episodeUnavailable);
          return;
        }
        await showDialog<void>(
          context: context,
          builder: (_) => PlayerDialog(
            media: queue[index],
            episodeQueue: queue,
            initialIndex: index,
            seriesTitle: item.seriesTitle,
          ),
        );
      } else if (item.kind == LibraryKind.series) {
        await showDialog<void>(
          context: context,
          builder: (_) => SeriesDialog(series: item.toMediaEntry()),
        );
      } else {
        final entry = item.toMediaEntry();
        final play = await showDialog<bool>(
          context: context,
          builder: (_) => MediaDetailsDialog(entry: entry),
        );
        if (play == true &&
            mounted &&
            app.activeAccount?.id == item.accountId) {
          await showDialog<void>(
            context: context,
            builder: (_) => PlayerDialog(media: entry),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        _notify(context.l10n.contentOpenFailed);
      }
    }
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmClear(PersonalLibraryController library) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.clearWatchHistoryQuestion),
        content: Text(context.l10n.clearWatchHistoryDetails),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.clearHistory),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _perform(library.clearHistory);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final library = app.personalLibrary;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    if (app.activeAccount == null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(context.l10n.connectToUseLibrary),
        ),
      );
    }
    if (library == null) {
      return Center(child: Text(context.l10n.libraryUnavailable));
    }
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final rows = switch (_view) {
          _View.continueWatching => library.continueWatching,
          _View.favorites => library.favorites,
          _View.history => library.history,
        };
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(26, 26, 26, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.myLibrary,
                        style: theme.textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        context.l10n.playbackAccountLibrary(
                          app.activeAccount!.label,
                        ),
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 20),
                      Center(
                        child: SizedBox(
                          width: 680,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: 680,
                              child: SegmentedButton<_View>(
                                key: const Key('personalLibraryTabs'),
                                showSelectedIcon: false,
                                segments: [
                                  ButtonSegment(
                                    value: _View.continueWatching,
                                    label: Text(context.l10n.continueWatching),
                                    icon: const Icon(Icons.play_circle_outline),
                                  ),
                                  ButtonSegment(
                                    value: _View.favorites,
                                    label: Text(context.l10n.favorites),
                                    icon: const Icon(Icons.favorite_outline),
                                  ),
                                  ButtonSegment(
                                    value: _View.history,
                                    label: Text(context.l10n.watchHistory),
                                    icon: const Icon(Icons.history),
                                  ),
                                ],
                                selected: {_view},
                                onSelectionChanged: (selection) =>
                                    setState(() => _view = selection.first),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_view == _View.history && rows.isNotEmpty)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _confirmClear(library),
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: Text(context.l10n.clearHistory),
                          ),
                        ),
                    ],
                  ),
                ),
                if (library.error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 26),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            library.error!,
                            style: TextStyle(color: colors.error),
                          ),
                        ),
                        TextButton(
                          onPressed: library.refresh,
                          child: Text(context.l10n.retry),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: rows.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  switch (_view) {
                                    _View.continueWatching =>
                                      Icons.play_circle_outline,
                                    _View.favorites => Icons.favorite_outline,
                                    _View.history => Icons.history,
                                  },
                                  size: 42,
                                  color: colors.onSurfaceVariant,
                                ),
                                const SizedBox(height: 12),
                                Text(switch (_view) {
                                  _View.continueWatching =>
                                    context.l10n.nothingToResume,
                                  _View.favorites => context.l10n.noFavorites,
                                  _View.history =>
                                    context.l10n.emptyViewingHistory,
                                }, style: theme.textTheme.titleMedium),
                                const SizedBox(height: 6),
                                Text(
                                  context.l10n.libraryEmptyHelp,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(26, 4, 26, 40),
                          itemCount: rows.length,
                          itemBuilder: (context, index) {
                            final item = rows[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _LibraryRow(
                                item: item,
                                view: _view,
                                busy: _busy,
                                onPlay: () => _open(item),
                                onDelete: () => _perform(
                                  () => _view == _View.favorites
                                      ? library.toggleFavorite(
                                          item.toMediaEntry(),
                                        )
                                      : library.removeHistory(item),
                                ),
                                onHide: () => _perform(
                                  () => library.removeFromContinue(item),
                                ),
                                onWatched: () => _perform(
                                  () => library.markWatched(
                                    item,
                                    !item.completed,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LibraryRow extends StatelessWidget {
  const _LibraryRow({
    required this.item,
    required this.view,
    required this.busy,
    required this.onPlay,
    required this.onDelete,
    required this.onHide,
    required this.onWatched,
  });
  final LibraryItem item;
  final _View view;
  final bool busy;
  final VoidCallback onPlay;
  final VoidCallback onDelete;
  final VoidCallback onHide;
  final VoidCallback onWatched;

  String _durationLabel(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    }
    return '${duration.inMinutes}m';
  }

  String _watchedDate(int milliseconds) {
    final date = DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
    String pad(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${pad(date.month)}-${pad(date.day)} '
        '${pad(date.hour)}:${pad(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final label = item.isEpisode
        ? '${item.seriesTitle ?? context.l10n.series} · S${item.season ?? '?'} E${item.episode ?? '?'}'
        : item.title;
    final statusText = item.completed
        ? context.l10n.watched
        : item.positionMs > 0 && item.durationMs > 0
        ? context.l10n.watchRemaining(
            _durationLabel(item.positionMs),
            _durationLabel(
              (item.durationMs - item.positionMs)
                  .clamp(0, item.durationMs)
                  .toInt(),
            ),
          )
        : item.positionMs > 0
        ? context.l10n.inProgress
        : context.l10n.saved;
    final artwork = SizedBox(
      width: 64,
      height: 82,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ColoredBox(
          color: colors.surfaceContainerHighest,
          child: item.imageUrl == null
              ? Icon(
                  item.kind == LibraryKind.movies
                      ? Icons.movie_outlined
                      : Icons.tv_outlined,
                  color: colors.onSurfaceVariant,
                )
              : Image.network(
                  item.imageUrl!,
                  fit: BoxFit.cover,
                  headers: context.read<AppController>().network.imageHeaders,
                  cacheWidth: 160,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.movie_outlined,
                    color: colors.onSurfaceVariant,
                  ),
                ),
        ),
      ),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        Text(
          statusText,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
        ),
        if (view == _View.history && item.updatedAtMs > 0) ...[
          const SizedBox(height: 3),
          Text(
            context.l10n.lastWatchedAt(_watchedDate(item.updatedAtMs)),
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11),
          ),
        ],
        if (item.progress != null && !item.completed) ...[
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: item.progress,
            minHeight: 4,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ],
    );
    final actions = <Widget>[
      IconButton.filledTonal(
        tooltip: context.l10n.openOrResume,
        onPressed: onPlay,
        icon: const Icon(Icons.play_arrow_rounded),
      ),
      if (view == _View.history)
        IconButton(
          tooltip: item.completed
              ? context.l10n.markAsUnwatched
              : context.l10n.markAsWatched,
          onPressed: busy ? null : onWatched,
          icon: Icon(
            item.completed ? Icons.check_circle : Icons.check_circle_outline,
          ),
        ),
      if (view == _View.continueWatching)
        IconButton(
          tooltip: context.l10n.removeContinueWatching,
          onPressed: busy ? null : onHide,
          icon: const Icon(Icons.close),
        ),
      if (view != _View.continueWatching)
        IconButton(
          tooltip: view == _View.favorites
              ? context.l10n.removeFavorite
              : context.l10n.removeHistoryEntry,
          onPressed: busy ? null : onDelete,
          icon: const Icon(Icons.delete_outline),
        ),
    ];
    return Material(
      color: colors.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 480;
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    artwork,
                    const SizedBox(width: 14),
                    Expanded(child: details),
                    if (!narrow) ...[const SizedBox(width: 12), ...actions],
                  ],
                ),
                if (narrow) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(spacing: 4, children: actions),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
