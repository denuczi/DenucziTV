import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/app_controller.dart';
import '../../../shared/navigation/dialog_launch_guard.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/formatting/count_format.dart';
import '../../connection/presentation/connect_dialog.dart';
import '../../player/presentation/player_dialog.dart';
import '../data/playlist_exporter.dart';
import '../domain/media_models.dart';
import 'media_card.dart';
import 'catalog_loading.dart';
import 'category_filter_bar.dart';
import 'catalog_header.dart';
import '../../../l10n/app_error_localizations.dart';
import '../../../l10n/l10n_ext.dart';
import 'export_notice.dart';
import 'media_details_dialog.dart';
import 'series_dialog.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  static const int _pageSize = 200;
  int _visibleLimit = _pageSize;

  final DialogLaunchGuard _mediaDialogGuard = DialogLaunchGuard();
  final ScrollController _scroll = ScrollController();
  final TextEditingController _searchField = TextEditingController();
  Timer? _searchDebounce;
  bool _showReturnToTop = false;
  bool _exporting = false;
  ExportPhase? _exportPhase;
  String _exportMessage = '';
  double? _exportProgress;
  Timer? _notificationTimer;
  LibraryKind? _lastKind;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    final visible = _scroll.hasClients && _scroll.offset > 450;
    if (visible != _showReturnToTop && mounted) {
      setState(() => _showReturnToTop = visible);
    }
  }

  Future<void> _goToTop() async {
    if (!_scroll.hasClients) {
      return;
    }
    await _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _filter(String? categoryId, AppController app) {
    setState(() => _visibleLimit = _pageSize);
    app.filterCategory(categoryId);
    _goToTop();
  }

  void _search(String value, AppController app) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) {
        return;
      }
      setState(() => _visibleLimit = _pageSize);
      app.setSearch(value);
      _goToTop();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _notificationTimer?.cancel();
    _searchField.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _open(MediaEntry entry) async {
    await _mediaDialogGuard.run(() => _openMedia(entry));
  }

  Future<void> _openMedia(MediaEntry entry) async {
    final sourceAccountId = context.read<AppController>().activeAccount?.id;
    if (entry.kind == LibraryKind.series) {
      await showDialog<void>(
        context: context,
        builder: (_) => SeriesDialog(series: entry),
      );
      return;
    } else if (entry.kind == LibraryKind.movies) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => MediaDetailsDialog(entry: entry),
      );
      if (!mounted || confirmed != true) {
        return;
      }
    }
    if (context.read<AppController>().activeAccount?.id != sourceAccountId) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => PlayerDialog(media: entry),
    );
  }

  Future<void> _export(AppController app) async {
    final credentials = app.credentials;
    if (credentials == null || _exporting) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.exportPlaylist),
        content: Text(context.l10n.exportWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.export),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    _notificationTimer?.cancel();
    setState(() {
      _exporting = true;
      _exportPhase = ExportPhase.selecting;
      _exportMessage = context.l10n.exportChooseFile;
      _exportProgress = null;
    });
    try {
      final entries = app.visibleEntries;
      final path = await PlaylistExporter(app.api).export(
        credentials: credentials,
        entries: entries,
        categories: app.categories,
        kind: app.kind,
        onProgress: (written, total) {
          if (!mounted) {
            return;
          }
          setState(() {
            _exportPhase = ExportPhase.writing;
            _exportProgress = total == 0 ? 1 : written / total;
            _exportMessage = context.l10n.exportWritten(
              formatItemCount(written),
              formatItemCount(total),
            );
          });
        },
      );
      if (!mounted) {
        return;
      }
      if (path == null) {
        setState(() => _exportPhase = null);
      } else {
        setState(() {
          _exportPhase = ExportPhase.success;
          _exportProgress = 1;
          _exportMessage = context.l10n.exportFinished(
            formatItemCount(entries.length),
            path,
          );
        });
        _scheduleNotificationDismissal();
      }
    } on FileSystemException catch (failure) {
      if (mounted) {
        setState(() {
          _exportPhase = ExportPhase.failure;
          _exportMessage = failure.message.contains('already exists')
              ? context.l10n.exportExists
              : context.l10n.exportWriteFailed;
          _exportProgress = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _exportPhase = ExportPhase.failure;
          _exportMessage = context.l10n.exportSaveFailed;
          _exportProgress = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  void _scheduleNotificationDismissal() {
    _notificationTimer?.cancel();
    _notificationTimer = Timer(const Duration(seconds: 7), () {
      if (mounted) {
        setState(() => _exportPhase = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final theme = Theme.of(context);
    if (app.activeAccount == null && (app.restoringAccount || app.connecting)) {
      return const CatalogLoading();
    }
    if (app.activeAccount == null) {
      final hasSavedAccounts = app.savedAccounts.isNotEmpty;
      return EmptyState(
        icon: hasSavedAccounts
            ? Icons.account_circle_outlined
            : Icons.live_tv_outlined,
        title: hasSavedAccounts
            ? context.l10n.connectSavedAccount
            : context.l10n.yourMediaOnePlace,
        description: hasSavedAccounts
            ? (app.error == null
                  ? context.l10n.chooseProvider
                  : localizeAppError(context, app.error!))
            : context.l10n.connectProviderHelp,
        action: hasSavedAccounts
            ? (app.savedAccounts.length == 1
                  ? FilledButton.icon(
                      onPressed: () =>
                          app.connectSaved(app.savedAccounts.single),
                      icon: const Icon(Icons.refresh),
                      label: Text(context.l10n.reconnect),
                    )
                  : null)
            : FilledButton.icon(
                onPressed: () => _mediaDialogGuard.run(() async {
                  await showDialog<void>(
                    context: context,
                    builder: (_) => const ConnectDialog(),
                  );
                }),
                icon: const Icon(Icons.add),
                label: Text(context.l10n.addProvider),
              ),
      );
    }

    // Reset navigation between libraries without changing the loading state.
    if (_lastKind != app.kind) {
      _searchDebounce?.cancel();
      _lastKind = app.kind;
      _visibleLimit = _pageSize;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _searchField.clear();
        if (_scroll.hasClients) {
          _scroll.jumpTo(0);
        }
      });
    }

    final visible = app.visibleEntries;
    final displayedCount = visible.length < _visibleLimit
        ? visible.length
        : _visibleLimit;
    final colors = theme.colorScheme;
    return Stack(
      children: [
        ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: Scrollbar(
            controller: _scroll,
            thumbVisibility: true,
            thickness: 6,
            radius: const Radius.circular(8),
            interactive: true,
            child: CustomScrollView(
              controller: _scroll,
              primary: false,
              slivers: [
                SliverAppBar(
                  pinned: true,
                  floating: false,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  toolbarHeight: 60,
                  expandedHeight: app.loading || app.entries.isNotEmpty
                      ? 188
                      : 60,
                  backgroundColor: colors.surface,
                  surfaceTintColor: Colors.transparent,
                  automaticallyImplyLeading: false,
                  titleSpacing: 0,
                  title: CatalogHeader(
                    kind: app.kind,
                    total: app.entries.length,
                    visible: visible.length,
                    loading: app.loading,
                    onRefresh: app.refresh,
                    exportAvailable:
                        app.showExportM3u && app.kind != LibraryKind.series,
                    exporting: _exporting,
                    onExport: () => _export(app),
                  ),
                  flexibleSpace: LayoutBuilder(
                    builder: (context, constraints) {
                      // Keep the flexible content at a fixed height and clip it as
                      // the app bar collapses. Fading does not change layout size.
                      final visibility = ((constraints.maxHeight - 96) / 92)
                          .clamp(0.0, 1.0)
                          .toDouble();
                      return ClipRect(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                // A neutral tonal transition separates the
                                // catalog tools without turning the header red.
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    colors.surfaceContainerLow,
                                    colors.surface,
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              top: 75,
                              left: 26,
                              right: 26,
                              height: 92,
                              child: IgnorePointer(
                                ignoring: visibility < 0.85,
                                child: Opacity(
                                  opacity: visibility,
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 220),
                                    switchInCurve: Curves.easeOut,
                                    switchOutCurve: Curves.easeIn,
                                    child: app.loading || app.entries.isEmpty
                                        ? Column(
                                            key: const ValueKey(
                                              'catalogFiltersPending',
                                            ),
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Container(
                                                height: 42,
                                                decoration: BoxDecoration(
                                                  color: colors
                                                      .surfaceContainerHighest
                                                      .withValues(alpha: 0.65),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Align(
                                                alignment: Alignment.centerLeft,
                                                child: Container(
                                                  width: 175,
                                                  height: 28,
                                                  decoration: BoxDecoration(
                                                    color: colors
                                                        .surfaceContainerHighest
                                                        .withValues(
                                                          alpha: 0.45,
                                                        ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          14,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          )
                                        : Column(
                                            key: const ValueKey(
                                              'catalogFiltersReady',
                                            ),
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              SizedBox(
                                                height: 42,
                                                child: ValueListenableBuilder<TextEditingValue>(
                                                  valueListenable: _searchField,
                                                  builder: (context, value, _) => TextField(
                                                    key: const Key(
                                                      'catalogSearchField',
                                                    ),
                                                    controller: _searchField,
                                                    autofocus: false,
                                                    textAlignVertical:
                                                        TextAlignVertical
                                                            .center,
                                                    style: theme
                                                        .textTheme
                                                        .bodyMedium,
                                                    decoration: InputDecoration(
                                                      isDense: true,
                                                      suffixIconConstraints:
                                                          const BoxConstraints(
                                                            minWidth: 40,
                                                            minHeight: 40,
                                                          ),
                                                      hintText: switch (app
                                                          .kind) {
                                                        LibraryKind.live =>
                                                          context
                                                              .l10n
                                                              .searchLiveTv,
                                                        LibraryKind.movies =>
                                                          context
                                                              .l10n
                                                              .searchMovies,
                                                        LibraryKind.series =>
                                                          context
                                                              .l10n
                                                              .searchSeries,
                                                      },
                                                      suffixIcon:
                                                          value.text.isEmpty
                                                          ? null
                                                          : IconButton(
                                                              tooltip: context
                                                                  .l10n
                                                                  .clearCatalogSearch,
                                                              constraints:
                                                                  const BoxConstraints.tightFor(
                                                                    width: 40,
                                                                    height: 40,
                                                                  ),
                                                              padding:
                                                                  EdgeInsets
                                                                      .zero,
                                                              icon: const Icon(
                                                                Icons.close,
                                                                size: 18,
                                                              ),
                                                              onPressed: () {
                                                                _searchDebounce
                                                                    ?.cancel();
                                                                _searchField
                                                                    .clear();
                                                                app.setSearch(
                                                                  '',
                                                                );
                                                                _goToTop();
                                                              },
                                                            ),
                                                      border: OutlineInputBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              21,
                                                            ),
                                                        borderSide:
                                                            BorderSide.none,
                                                      ),
                                                      contentPadding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 14,
                                                            vertical: 8,
                                                          ),
                                                    ),
                                                    onChanged: (value) =>
                                                        _search(value, app),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              SizedBox(
                                                height: 44,
                                                child: CategoryFilterBar(
                                                  key: ValueKey(
                                                    'categoryBar-${app.kind.name}',
                                                  ),
                                                  categories: app.categories,
                                                  selectedId: app.categoryId,
                                                  onSelected: (id) =>
                                                      _filter(id, app),
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                if (app.error != null && visible.isNotEmpty)
                  SliverToBoxAdapter(
                    child: MaterialBanner(
                      content: Text(localizeAppError(context, app.error!)),
                      actions: [
                        TextButton(
                          onPressed: app.clearError,
                          child: Text(context.l10n.dismiss),
                        ),
                        TextButton(
                          onPressed: app.refresh,
                          child: Text(context.l10n.retry),
                        ),
                      ],
                    ),
                  ),
                if (app.loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: CatalogLoading(),
                  )
                else if (app.error != null && visible.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.wifi_off_outlined,
                      title: context.l10n.unableLoadCatalog,
                      description: localizeAppError(context, app.error!),
                      action: FilledButton.icon(
                        onPressed: app.refresh,
                        icon: const Icon(Icons.refresh),
                        label: Text(context.l10n.tryAgain),
                      ),
                    ),
                  )
                else if (visible.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: app.entries.isEmpty
                          ? Icons.video_library_outlined
                          : Icons.search_off_outlined,
                      title: app.entries.isEmpty
                          ? context.l10n.noTitlesAvailable
                          : context.l10n.noMatchingTitles,
                      description: app.entries.isEmpty
                          ? context.l10n.emptyCatalogHelp
                          : context.l10n.noMatchesHelp,
                      action: app.entries.isEmpty
                          ? OutlinedButton.icon(
                              onPressed: app.refresh,
                              icon: const Icon(Icons.refresh),
                              label: Text(context.l10n.reloadCatalog),
                            )
                          : null,
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(26, 14, 26, 32),
                    sliver: SliverGrid.builder(
                      itemCount: displayedCount,
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 205,
                            mainAxisSpacing: 20,
                            crossAxisSpacing: 15,
                            childAspectRatio: 0.64,
                          ),
                      itemBuilder: (context, index) => MediaCard(
                        entry: visible[index],
                        network: app.network,
                        onOpen: () => _open(visible[index]),
                        showActions:
                            app.kind != LibraryKind.series &&
                            (app.showCopyLinkControls ||
                                (app.showDownloadControls &&
                                    app.kind == LibraryKind.movies)),
                      ),
                    ),
                  ),
                if (!app.loading && visible.length > _pageSize)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(26, 6, 26, 32),
                      child: Column(
                        children: [
                          Text(
                            context.l10n.showingTitles(
                              displayedCount.toString(),
                              visible.length.toString(),
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          if (displayedCount < visible.length) ...[
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              key: const Key('loadMoreCatalog'),
                              onPressed: () =>
                                  setState(() => _visibleLimit += _pageSize),
                              icon: const Icon(Icons.expand_more_rounded),
                              label: Text(context.l10n.loadMoreTitles),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_exportPhase != null)
          Positioned(
            top: 72,
            left: 16,
            right: 16,
            child: Align(
              alignment: Alignment.topRight,
              child: ExportNotice(
                phase: _exportPhase!,
                progress: _exportProgress,
                message: _exportMessage,
                onDismiss: () {
                  _notificationTimer?.cancel();
                  setState(() => _exportPhase = null);
                },
              ),
            ),
          ),
        Positioned(
          right: 22,
          bottom: 20,
          child: IgnorePointer(
            ignoring: !_showReturnToTop,
            child: AnimatedOpacity(
              opacity: _showReturnToTop ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: FloatingActionButton.small(
                key: const Key('returnToTop'),
                tooltip: context.l10n.backToTop,
                onPressed: _goToTop,
                child: const Icon(Icons.keyboard_arrow_up_rounded),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
