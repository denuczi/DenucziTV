import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../shared/widgets/content_unavailable_dialog.dart';

import 'package:provider/provider.dart';

import '../../../core/models/app_controller.dart';
import '../../../shared/navigation/dialog_launch_guard.dart';
import '../domain/media_models.dart';
import 'media_artwork.dart';
import '../../player/presentation/player_dialog.dart';
import 'media_actions.dart';
import 'download_action_button.dart';
import 'season_selector.dart';
import '../../downloads/domain/download_task.dart';
import 'rating_badge.dart';
import '../../personal_library/presentation/library_controls.dart';

typedef EpisodePlaybackLauncher = Future<void> Function(
  BuildContext context,
  List<MediaEntry> queue,
  int selectedIndex,
);

class SeriesDialog extends StatefulWidget {
  const SeriesDialog({
    super.key,
    required this.series,
    this.detailsLoader,
    this.playbackLauncher,
  });

  final MediaEntry series;
  final Future<SeriesDetails> Function()? detailsLoader;
  final EpisodePlaybackLauncher? playbackLauncher;

  @override
  State<SeriesDialog> createState() => _SeriesDialogState();
}

class _SeriesDialogState extends State<SeriesDialog> {
  late final Future<SeriesDetails> _details;
  int? _selectedSeason;
  bool _downloadPending = false;
  final DialogLaunchGuard _episodeLaunchGuard = DialogLaunchGuard();

  Future<void> _downloadSeason(int season, List<MediaEntry> episodes) async {
    if (_downloadPending) {
      return;
    }
    setState(() => _downloadPending = true);
    try {
      await downloadSeason(context, widget.series.title, season, episodes);
    } finally {
      if (mounted) {
        setState(() => _downloadPending = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    final override = widget.detailsLoader;
    if (override != null) {
      _details = override();
    } else {
      final app = context.read<AppController>();
      final credentials = app.credentials;
      _details = credentials == null
          ? Future.error(StateError('Account is not connected'))
          : app.api.seriesDetails(credentials, widget.series.id);
    }
  }

  Future<void> _play(SeriesDetails details, MediaEntry episode) async {
    await _episodeLaunchGuard.run(() => _playEpisode(details, episode));
  }

  Future<void> _playEpisode(SeriesDetails details, MediaEntry episode) async {
    if (widget.series.sourceScope.isNotEmpty &&
        !context.read<AppController>().canUseMedia(widget.series)) {
      return;
    }
    // Continue across season boundaries in chronological season/episode order.
    // This route remains mounted behind the player so the selected season and
    // scroll position survive when the playback window is closed.
    final queue = [
      for (final item in details.playbackQueue)
        item.withSeries(widget.series.id),
    ];
    final index = queue.indexWhere((item) => item.id == episode.id);
    if (index < 0) {
      return;
    }
    final launcher = widget.playbackLauncher;
    if (launcher != null) {
      await launcher(context, queue, index);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => PlayerDialog(
        media: episode,
        episodeQueue: queue,
        initialIndex: index,
        seriesTitle: widget.series.title,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    if (widget.series.sourceScope.isNotEmpty &&
        !app.canUseMedia(widget.series)) {
      return const ContentUnavailableDialog();
    }
    final viewport = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: math.min(780.0, math.max(0.0, viewport.width - 32.0)),
        height: math.min(680.0, math.max(0.0, viewport.height - 32.0)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 12, 8),
              child: Row(
                children: [
                  const Icon(Icons.tv_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.series.title,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  FavoriteToggleButton(media: widget.series),
                  IconButton(
                    tooltip: context.l10n.close,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<SeriesDetails>(
                future: _details,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(context.l10n.seriesDetailsFailed),
                    );
                  }
                  final details = snapshot.data!;
                  final seasons = details.episodesBySeason;
                  final numbers = seasons.keys.toList()..sort();
                  final season = numbers.contains(_selectedSeason)
                      ? _selectedSeason!
                      : (numbers.isEmpty ? null : numbers.first);
                  final episodes = season == null
                      ? <MediaEntry>[]
                      : seasons[season]!;
                  final metadata = details.metadata;
                  final network = context.read<AppController>().network;
                  return CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final summary = Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          if (metadata.genre != null)
                                            Chip(label: Text(metadata.genre!)),
                                          if (metadata.rating != null)
                                            RatingBadge(
                                              rating: metadata.rating!,
                                            ),
                                          if (metadata.releaseDate != null)
                                            Chip(
                                              label: Text(
                                                metadata.releaseDate!,
                                              ),
                                            ),
                                        ],
                                      ),
                                      if (metadata.plot != null ||
                                          widget.series.plot != null) ...[
                                        const SizedBox(height: 12),
                                        Text(
                                          metadata.plot ?? widget.series.plot!,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium,
                                        ),
                                      ],
                                      if (metadata.cast != null) ...[
                                        const SizedBox(height: 12),
                                        Text(
                                          context.l10n.cast(metadata.cast!),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ],
                                    ],
                                  );
                                  final artwork = MediaArtwork(
                                    imageUrl:
                                        metadata.imageUrl ??
                                        widget.series.imageUrl,
                                    network: network,
                                    width: 116,
                                    height: 166,
                                  );
                                  if (constraints.maxWidth < 430) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        artwork,
                                        const SizedBox(height: 12),
                                        summary,
                                      ],
                                    );
                                  }
                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      artwork,
                                      const SizedBox(width: 18),
                                      Expanded(child: summary),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 18),
                              Semantics(
                                label:
                                    '${context.l10n.seasonCount(details.seasonCount)}, ${context.l10n.episodesTotal(details.episodeCount)}',
                                child: Wrap(
                                  spacing: 10,
                                  runSpacing: 8,
                                  children: [
                                    Chip(
                                      avatar: const Icon(
                                        Icons.video_library_outlined,
                                        size: 17,
                                      ),
                                      label: Text(
                                        context.l10n.seasonCount(
                                          details.seasonCount,
                                        ),
                                      ),
                                    ),
                                    Chip(
                                      avatar: const Icon(
                                        Icons.playlist_play_rounded,
                                        size: 18,
                                      ),
                                      label: Text(
                                        context.l10n.episodesTotal(
                                          details.episodeCount,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          context.l10n.episodesHeading,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                        ),
                                        if (season != null)
                                          Text(
                                            context.l10n.episodesInSeason(
                                              details.episodeCountForSeason(
                                                season,
                                              ),
                                              season,
                                            ),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (season != null &&
                                      context
                                          .watch<AppController>()
                                          .showDownloadControls)
                                    ListenableBuilder(
                                      listenable: context
                                          .read<AppController>()
                                          .downloads,
                                      builder: (context, _) {
                                        final app = context
                                            .read<AppController>();
                                        final accountId =
                                            app.activeAccount?.id ?? 'unscoped';
                                        final tasks = [
                                          for (final episode in episodes)
                                            app.downloads.taskForMedia(
                                              accountId,
                                              episode,
                                            ),
                                        ];
                                        // An individual episode transfer must not be
                                        // represented as a season-wide download.
                                        final remaining = tasks
                                            .where(
                                              (task) =>
                                                  task == null ||
                                                  (task.status !=
                                                          DownloadStatus
                                                              .queued &&
                                                      task.status !=
                                                          DownloadStatus
                                                              .downloading &&
                                                      task.status !=
                                                          DownloadStatus
                                                              .completed),
                                            )
                                            .length;
                                        final complete =
                                            episodes.isNotEmpty &&
                                            tasks.every(
                                              (task) =>
                                                  task?.status ==
                                                  DownloadStatus.completed,
                                            );
                                        final allQueued =
                                            episodes.isNotEmpty &&
                                            remaining == 0 &&
                                            !complete;
                                        final locked =
                                            _downloadPending || remaining == 0;
                                        final label = complete
                                            ? context.l10n.seasonDownloaded
                                            : _downloadPending
                                            ? context.l10n.seasonQueueing
                                            : allQueued
                                            ? context.l10n.seasonAllQueued
                                            : remaining == episodes.length
                                            ? context.l10n.seasonDownload
                                            : context.l10n.seasonRemaining(
                                                remaining,
                                              );
                                        return TextButton.icon(
                                          key: const Key(
                                            'downloadSeasonAction',
                                          ),
                                          onPressed: locked
                                              ? null
                                              : () => _downloadSeason(
                                                  season,
                                                  episodes,
                                                ),
                                          icon: _downloadPending
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2.2,
                                                      ),
                                                )
                                              : Icon(
                                                  complete
                                                      ? Icons
                                                            .check_circle_outline
                                                      : allQueued
                                                      ? Icons.schedule_rounded
                                                      : Icons.download_outlined,
                                                ),
                                          label: Text(label),
                                        );
                                      },
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (season != null)
                                SizedBox(
                                  height: 44,
                                  child: SeasonSelector(
                                    seasons: numbers,
                                    selectedSeason: season,
                                    episodeCountForSeason:
                                        details.episodeCountForSeason,
                                    onSelected: (value) =>
                                        setState(() => _selectedSeason = value),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (episodes.isEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(context.l10n.noEpisodes),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
                          sliver: SliverList.builder(
                            itemCount: episodes.length,
                            itemBuilder: (context, index) {
                              final episode = episodes[index];
                              final scheme = Theme.of(context).colorScheme;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Material(
                                  color: scheme.surfaceContainer,
                                  clipBehavior: Clip.antiAlias,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                      color: scheme.outlineVariant,
                                    ),
                                  ),
                                  child: InkWell(
                                    key: Key('episode-$index'),
                                    mouseCursor: SystemMouseCursors.click,
                                    overlayColor: WidgetStatePropertyAll(
                                      scheme.primary.withValues(alpha: 0.09),
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () => _play(details, episode),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 14,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          SizedBox(
                                            width: 38,
                                            child: Text(
                                              '${episode.episodeNumber ?? index + 1}'
                                                  .padLeft(2, '0'),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                          ),
                                          MediaArtwork(
                                            key: Key('episodeArtwork-$index'),
                                            imageUrl:
                                                episode.imageUrl ??
                                                metadata.imageUrl ??
                                                widget.series.imageUrl,
                                            network: network,
                                            width: 104,
                                            height: 66,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  episode.title,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleSmall
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 15,
                                                      ),
                                                ),
                                                if (episode.plot != null &&
                                                    episode.plot!
                                                        .trim()
                                                        .isNotEmpty) ...[
                                                  const SizedBox(height: 5),
                                                  Text(
                                                    episode.plot!,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color: scheme
                                                              .onSurfaceVariant,
                                                          fontSize: 13,
                                                          height: 1.4,
                                                        ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            spacing: 12,
                                            children: [
                                              if (app.personalLibrary != null &&
                                                  app.activeAccount != null)
                                                SizedBox.square(
                                                  dimension: 40,
                                                  child: EpisodeWatchedButton(
                                                    episode: episode.withSeries(
                                                      widget.series.id,
                                                    ),
                                                    seriesTitle:
                                                        widget.series.title,
                                                  ),
                                                ),
                                              if (app.copyLinksAvailable)
                                                SizedBox.square(
                                                  dimension: 40,
                                                  child: MediaActionMenu(
                                                    media: episode,
                                                  ),
                                                ),
                                              if (app.showDownloadControls)
                                                SizedBox.square(
                                                  dimension: 40,
                                                  child: DownloadActionButton(
                                                    media: episode,
                                                    compact: true,
                                                  ),
                                                ),
                                              Tooltip(
                                                message:
                                                    context.l10n.playEpisode,
                                                child: const DecoratedBox(
                                                  decoration: BoxDecoration(
                                                    color: Colors.black,
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: SizedBox.square(
                                                    dimension: 40,
                                                    child: Icon(
                                                      Icons.play_arrow_rounded,
                                                      size: 24,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
