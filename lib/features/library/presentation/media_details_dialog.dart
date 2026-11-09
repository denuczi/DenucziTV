import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../shared/widgets/content_unavailable_dialog.dart';

import 'package:provider/provider.dart';

import '../../../core/models/app_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/media_models.dart';
import 'media_artwork.dart';
import 'media_actions.dart';
import 'download_action_button.dart';
import 'rating_badge.dart';
import '../../personal_library/presentation/library_controls.dart';

/// Presents provider-supplied movie metadata before starting playback.
class MediaDetailsDialog extends StatefulWidget {
  const MediaDetailsDialog({
    super.key,
    required this.entry,
    this.detailsLoader,
  });

  final MediaEntry entry;

  /// Allows tests to supply a delayed, successful, or failed metadata request.
  final Future<MediaDetails> Function()? detailsLoader;

  @override
  State<MediaDetailsDialog> createState() => _MediaDetailsDialogState();
}

class _MediaDetailsDialogState extends State<MediaDetailsDialog> {
  late Future<MediaDetails> _details;
  Future<MediaDetails> _loadDetails() {
    final loader = widget.detailsLoader;
    if (loader != null) {
      return loader();
    }
    final app = context.read<AppController>();
    if (widget.entry.sourceScope.isNotEmpty && !app.canUseMedia(widget.entry)) {
      return Future.error(StateError('Content unavailable'));
    }
    final credentials = app.credentials;
    return credentials == null
        ? Future.error(StateError('Account is not connected.'))
        : app.api.movieDetails(credentials, widget.entry.id);
  }

  Future<MediaDetails> _requestDetails() {
    // A synchronous provider exception can complete this future with an error
    // before FutureBuilder subscribes during the next frame. Mark it as
    // observed immediately; FutureBuilder still receives the error and shows
    // the retry UI when it subscribes.
    final request = Future<MediaDetails>.sync(_loadDetails);
    request.ignore();
    return request;
  }

  void _retryDetails() {
    // Keep setState synchronous. The request is observed before the next frame.
    final request = _requestDetails();
    setState(() {
      _details = request;
    });
  }

  @override
  void initState() {
    super.initState();
    _details = _requestDetails();
  }

  static const ButtonStyle _actionButtonStyle = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(150, 44)),
    padding: WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    ),
    alignment: Alignment.center,
  );

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    if (widget.entry.sourceScope.isNotEmpty && !app.canUseMedia(widget.entry)) {
      return const ContentUnavailableDialog();
    }
    final scheme = Theme.of(context).colorScheme;
    final width = (MediaQuery.sizeOf(context).width - 32)
        .clamp(0.0, 720.0)
        .toDouble();
    final maxHeight = (MediaQuery.sizeOf(context).height - 48)
        .clamp(0.0, 680.0)
        .toDouble();
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: width,
        height: maxHeight,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 12, 10),
              child: Row(
                children: [
                  const Icon(Icons.local_movies_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.l10n.movieDetails,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  FavoriteToggleButton(media: widget.entry),
                  IconButton(
                    tooltip: context.l10n.close,
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<MediaDetails>(
                future: _details,
                builder: (context, snapshot) {
                  final details = snapshot.data;
                  final loading =
                      snapshot.connectionState != ConnectionState.done;
                  final providerSynopsis = details?.plot?.trim();
                  final catalogSynopsis = widget.entry.plot?.trim();
                  final synopsis =
                      providerSynopsis != null && providerSynopsis.isNotEmpty
                      ? providerSynopsis
                      : catalogSynopsis;
                  final app = context.read<AppController>();
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final overview = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.entry.title,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium,
                              ),
                              const SizedBox(height: 12),
                              if (loading) const LinearProgressIndicator(),
                              if (!loading && snapshot.hasError)
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 8,
                                  children: [
                                    Text(
                                      context.l10n.movieDetailsFailed,
                                      style: TextStyle(color: scheme.error),
                                    ),
                                    TextButton.icon(
                                      onPressed: _retryDetails,
                                      icon: const Icon(Icons.refresh, size: 18),
                                      label: Text(context.l10n.retry),
                                    ),
                                  ],
                                ),
                              if (!loading && !snapshot.hasError)
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 7,
                                  children: [
                                    if (details?.releaseDate != null)
                                      Chip(label: Text(details!.releaseDate!)),
                                    if (details?.duration != null)
                                      Chip(label: Text(details!.duration!)),
                                    if ((details?.rating ??
                                            widget.entry.rating) !=
                                        null)
                                      RatingBadge(
                                        rating:
                                            (details?.rating ??
                                            widget.entry.rating)!,
                                      ),
                                    if (details?.genre != null)
                                      Chip(label: Text(details!.genre!)),
                                  ],
                                ),
                              const SizedBox(height: 18),
                              if (synopsis != null && synopsis.isNotEmpty)
                                Text(
                                  synopsis,
                                  style: Theme.of(context).textTheme.bodyLarge,
                                )
                              else if (loading)
                                Semantics(
                                  label: context.l10n.movieSynopsisLoading,
                                  child: Text(
                                    context.l10n.loadingSynopsis,
                                    style: Theme.of(context).textTheme.bodyLarge
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                  ),
                                )
                              else if (snapshot.hasError)
                                Text(
                                  context.l10n.movieSynopsisFailed,
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                )
                              else
                                Text(
                                  context.l10n.noSynopsis,
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                            ],
                          );
                          final artwork = MediaArtwork(
                            imageUrl:
                                details?.imageUrl ?? widget.entry.imageUrl,
                            network: app.network,
                          );
                          if (constraints.maxWidth < 500) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                artwork,
                                const SizedBox(height: 18),
                                overview,
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              artwork,
                              const SizedBox(width: 24),
                              Expanded(child: overview),
                            ],
                          );
                        },
                      ),
                      if (details != null) ...[
                        const SizedBox(height: 24),
                        if (details.director != null)
                          _MetadataRow('Director', details.director!),
                        if (details.cast != null)
                          _MetadataRow('Cast', details.cast!),
                        if (details.country != null)
                          _MetadataRow('Country', details.country!),
                      ],
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    if (context.watch<AppController>().copyLinksAvailable)
                      OutlinedButton.icon(
                        style: _actionButtonStyle,
                        onPressed: () => performMediaAction(
                          context,
                          widget.entry,
                          MediaAction.copyLink,
                        ),
                        icon: const Icon(Icons.link),
                        label: Text(context.l10n.copyUrl),
                      ),
                    if (context.watch<AppController>().showDownloadControls)
                      DownloadActionButton(
                        media: widget.entry,
                        style: _actionButtonStyle,
                      ),
                    FilledButton.icon(
                      style: _actionButtonStyle.merge(
                        FilledButton.styleFrom(
                          backgroundColor: AppPalette.mediaAction(scheme),
                          foregroundColor: Colors.white,
                        ),
                      ),
                      onPressed: () => Navigator.pop(context, true),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(context.l10n.playMovie),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(value),
        ],
      ),
    );
  }
}
