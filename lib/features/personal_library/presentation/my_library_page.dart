import 'dart:io';

import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';

import 'package:provider/provider.dart';

import '../../../core/models/app_controller.dart';
import '../../../shared/navigation/dialog_launch_guard.dart';
import '../../library/domain/media_models.dart';
import '../../library/presentation/media_details_dialog.dart';
import '../../library/presentation/media_artwork.dart';
import '../../library/presentation/series_dialog.dart';
import '../../player/presentation/player_dialog.dart';
import '../../connection/presentation/connect_dialog.dart';
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
  LibraryKind _favoriteKind = LibraryKind.live;
  bool _busy = false;
  final TextEditingController _favoritesSearch = TextEditingController();
  String _favoriteQuery = '';
  final DialogLaunchGuard _playbackGuard = DialogLaunchGuard();

  @override
  void dispose() {
    _favoritesSearch.dispose();
    super.dispose();
  }

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
    if (!item.available || !app.canUseMedia(item.toMediaEntry())) {
      _notify(context.l10n.contentUnavailable);
      return;
    }
    final credentials = app.credentials;
    if (credentials == null ||
        app.activeAccount?.id != item.accountId ||
        !app.canUseMedia(item.toMediaEntry())) {
      return;
    }
    try {
      if (item.isEpisode) {
        final seriesId = item.seriesId!;
        final details = await app.api.seriesDetails(credentials, seriesId);
        if (!mounted ||
            app.activeAccount?.id != item.accountId ||
            !app.canUseMedia(item.toMediaEntry())) {
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
      } else if (item.kind == LibraryKind.live) {
        await showDialog<void>(
          context: context,
          builder: (_) => PlayerDialog(media: item.toMediaEntry()),
        );
      } else {
        final entry = item.toMediaEntry();
        final play = await showDialog<bool>(
          context: context,
          builder: (_) => MediaDetailsDialog(entry: entry),
        );
        if (play == true &&
            mounted &&
            app.activeAccount?.id == item.accountId &&
            app.canUseMedia(item.toMediaEntry())) {
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

  Future<void> _confirmClearFavorites(
    PersonalLibraryController library,
    String accountName,
  ) async {
    if (library.favorites.isEmpty) {
      return;
    }
    // A confirmation opened for one account cannot delete another account's
    // favorites if the user navigates or switches providers in the meantime.
    final accountId = library.accountId;
    if (accountId == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.clearAllFavoritesQuestion,
                  style: Theme.of(dialogContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  context.l10n.clearAllFavoritesDetails(accountName),
                  style: Theme.of(dialogContext).textTheme.bodyMedium,
                ),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: Text(context.l10n.cancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: Text(context.l10n.clearAllFavorites),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (confirmed == true && mounted && library.accountId == accountId) {
      await _perform(() async {
        await library.clearFavorites(expectedAccountId: accountId);
        if (!mounted) {
          return;
        }
        _favoritesSearch.clear();
        setState(() => _favoriteQuery = '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final library = app.personalLibrary;
    final libraryAccount = app.activeAccount ?? app.offlineLibraryAccount;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    if (libraryAccount == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bookmarks_outlined, size: 44),
              const SizedBox(height: 14),
              Text(
                context.l10n.connectToUseLibrary,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.add_rounded),
                label: Text(context.l10n.connectProvider),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const ConnectDialog(),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (library == null) {
      return Center(child: Text(context.l10n.libraryUnavailable));
    }
    // Never show favorites from a previous account under the newly selected
    // provider while an asynchronous account switch is in progress.
    if (library.accountId != null && library.accountId != libraryAccount.id) {
      return Center(child: Text(context.l10n.loadingLibrary));
    }
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final query = _favoriteQuery;
        final rows = switch (_view) {
          _View.continueWatching => library.continueWatching,
          _View.favorites =>
            library.favorites
                .where(
                  (item) =>
                      item.kind == _favoriteKind &&
                      (query.isEmpty ||
                          item.title.toLowerCase().contains(query)),
                )
                .toList(growable: false),
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
                          libraryAccount.label,
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
                      if (_view == _View.favorites) ...[
                        const SizedBox(height: 16),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final compact = constraints.maxWidth < 860;
                            final searchField = TextField(
                              key: const Key('favoriteSearchField'),
                              controller: _favoritesSearch,
                              onChanged: (value) => setState(
                                () =>
                                    _favoriteQuery = value.trim().toLowerCase(),
                              ),
                              textInputAction: TextInputAction.search,
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: context.l10n.searchFavorites,
                                prefixIcon: const Icon(Icons.search, size: 18),
                                suffixIcon: _favoritesSearch.text.isEmpty
                                    ? null
                                    : IconButton(
                                        key: const Key('clearFavoriteSearch'),
                                        tooltip:
                                            context.l10n.clearFavoritesSearch,
                                        onPressed: () {
                                          _favoritesSearch.clear();
                                          setState(() => _favoriteQuery = '');
                                        },
                                        icon: const Icon(Icons.close, size: 16),
                                      ),
                                filled: true,
                                fillColor: colors.surfaceContainerLowest,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                            );
                            final clearAction = library.favorites.isEmpty
                                ? const SizedBox.shrink()
                                : IconButton(
                                    key: const Key('clearAllFavoritesAction'),
                                    tooltip: context.l10n.clearAllFavorites,
                                    onPressed: _busy
                                        ? null
                                        : () => _confirmClearFavorites(
                                            library,
                                            libraryAccount.label,
                                          ),
                                    icon: const Icon(
                                      Icons.delete_sweep_outlined,
                                    ),
                                  );
                            final chips = Wrap(
                              key: const Key('favoriteKindFilters'),
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final kind in LibraryKind.values)
                                  ChoiceChip(
                                    key: Key('favoriteKind_${kind.name}'),
                                    showCheckmark: false,
                                    selected: _favoriteKind == kind,
                                    avatar: Icon(switch (kind) {
                                      LibraryKind.live =>
                                        Icons.live_tv_outlined,
                                      LibraryKind.movies =>
                                        Icons.movie_outlined,
                                      LibraryKind.series => Icons.tv_outlined,
                                    }, size: 17),
                                    label: Text(switch (kind) {
                                      LibraryKind.live => context.l10n.liveTv,
                                      LibraryKind.movies => context.l10n.movies,
                                      LibraryKind.series => context.l10n.series,
                                    }),
                                    onSelected: (_) =>
                                        setState(() => _favoriteKind = kind),
                                  ),
                              ],
                            );
                            final trailingActions = Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(width: 260, child: searchField),
                                if (library.favorites.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  clearAction,
                                ],
                              ],
                            );
                            if (compact) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  chips,
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(child: searchField),
                                      if (library.favorites.isNotEmpty) ...[
                                        const SizedBox(width: 6),
                                        clearAction,
                                      ],
                                    ],
                                  ),
                                ],
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(child: chips),
                                const SizedBox(width: 16),
                                trailingActions,
                              ],
                            );
                          },
                        ),
                      ],
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
                                  _View.favorites =>
                                    _favoriteQuery.isNotEmpty
                                        ? context.l10n.noFavoriteMatches
                                        : context.l10n.noFavorites,
                                  _View.history =>
                                    context.l10n.emptyViewingHistory,
                                }, style: theme.textTheme.titleMedium),
                                const SizedBox(height: 6),
                                Text(
                                  _view == _View.favorites &&
                                          _favoriteQuery.isNotEmpty
                                      ? context.l10n.noMatchesHelp
                                      : context.l10n.libraryEmptyHelp,
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
                                key: ValueKey((
                                  item.accountId,
                                  item.sourceScope,
                                  item.kind,
                                  item.mediaId,
                                  item.isEpisode,
                                )),
                                item: item,
                                view: _view,
                                busy: _busy,
                                onPlay: () => _open(item),
                                onDelete: () => _perform(
                                  () => _view == _View.favorites
                                      ? library.removeFavorite(item)
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
    super.key,
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
    final statusText = !item.available
        ? context.l10n.contentUnavailable
        : item.completed
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
    final app = context.watch<AppController>();
    final artwork = _CachedLibraryArtwork(item: item, app: app);
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
    final canOpen =
        !busy && item.available && app.canUseMedia(item.toMediaEntry());
    final actions = <Widget>[
      IconButton.filledTonal(
        tooltip: context.l10n.openOrResume,
        onPressed: canOpen ? onPlay : null,
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
                    Expanded(
                      child: InkWell(
                        key:
                            item.kind == LibraryKind.live &&
                                view == _View.favorites
                            ? Key('favoriteLiveOpen_${item.mediaId}')
                            : null,
                        borderRadius: BorderRadius.circular(9),
                        // Only channel favorites gain a direct artwork/title
                        // play target. Playback buttons retain their actions.
                        onTap:
                            item.kind == LibraryKind.live &&
                                view == _View.favorites &&
                                canOpen
                            ? onPlay
                            : null,
                        child: Row(
                          children: [
                            artwork,
                            const SizedBox(width: 14),
                            Expanded(child: details),
                          ],
                        ),
                      ),
                    ),
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

/// Preserves the image request when a parent controller notifies listeners.
/// Disk files are readable before a provider catalog has been fetched.
class _CachedLibraryArtwork extends StatefulWidget {
  const _CachedLibraryArtwork({required this.item, required this.app});

  final LibraryItem item;
  final AppController app;

  @override
  State<_CachedLibraryArtwork> createState() => _CachedLibraryArtworkState();
}

class _CachedLibraryArtworkState extends State<_CachedLibraryArtwork> {
  late Future<({File? file, String? url})> _cover;
  Object? _credentialsSnapshot;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant _CachedLibraryArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.accountId != widget.item.accountId ||
        oldWidget.item.sourceScope != widget.item.sourceScope ||
        oldWidget.item.mediaId != widget.item.mediaId ||
        oldWidget.item.kind != widget.item.kind ||
        !identical(_credentialsSnapshot, widget.app.credentials)) {
      _reload();
    }
  }

  void _reload() {
    final app = widget.app;
    final item = widget.item;
    _credentialsSnapshot = app.credentials;
    final cache = app.personalLibrary?.artworkCache;
    _cover = cache == null
        ? app.resolveLibraryArtwork(item).then((url) => (file: null, url: url))
        : cache
              .getOrLoad(
                item,
                resolveUrl: () => app.resolveLibraryArtwork(item),
              )
              .then(
                (file) =>
                    (file: file, url: file == null ? item.imageUrl : null),
              );
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<({File? file, String? url})>(
        future: _cover,
        builder: (context, snapshot) => MediaArtwork(
          width: 64,
          height: 82,
          cachedFile: snapshot.data?.file,
          imageUrl: snapshot.data?.url,
          network: widget.app.network,
        ),
      );
}
