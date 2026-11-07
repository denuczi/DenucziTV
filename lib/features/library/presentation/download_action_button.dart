import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';

import 'package:provider/provider.dart';

import '../../../core/models/app_controller.dart';
import '../../downloads/domain/download_task.dart';
import '../domain/media_models.dart';
import 'media_actions.dart';

/// Reflects the shared download queue rather than maintaining local progress.
/// A disposed details dialog does not affect an ongoing transfer.
class DownloadActionButton extends StatefulWidget {
  const DownloadActionButton({
    super.key,
    required this.media,
    this.compact = false,
    this.style,
  });

  final MediaEntry media;
  final bool compact;
  final ButtonStyle? style;

  @override
  State<DownloadActionButton> createState() => _DownloadActionButtonState();
}

class _DownloadActionButtonState extends State<DownloadActionButton> {
  bool _starting = false;

  Future<void> _start() async {
    if (_starting) {
      return;
    }
    setState(() => _starting = true);
    try {
      await performMediaAction(context, widget.media, MediaAction.download);
    } finally {
      if (mounted) {
        setState(() => _starting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    return ListenableBuilder(
      listenable: app.downloads,
      builder: (context, _) {
        final task = app.downloads.taskForMedia(
          app.activeAccount?.id ?? 'unscoped',
          widget.media,
        );
        final stopping =
            task?.status == DownloadStatus.cancelled &&
            task != null &&
            app.downloads.isTransferActive(task.id);
        final waiting =
            _starting || task?.status == DownloadStatus.queued || stopping;
        final downloading = task?.status == DownloadStatus.downloading;
        final completed = task?.status == DownloadStatus.completed;
        final locked = waiting || downloading || completed;
        final progress = downloading ? task?.progress : null;
        final icon = locked && !completed
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 2.4,
                  strokeCap: StrokeCap.round,
                  color: Theme.of(context).colorScheme.primary,
                ),
              )
            : Icon(
                completed
                    ? Icons.check_circle_outline_rounded
                    : Icons.download_outlined,
                size: 20,
              );
        final label = completed
            ? context.l10n.downloadStatusDownloaded
            : downloading
            ? context.l10n.downloadStatusDownloading
            : stopping
            ? context.l10n.downloadStatusStopping
            : waiting
            ? context.l10n.downloadStatusQueued
            : context.l10n.downloadVerb;
        return Semantics(
          label: completed
              ? context.l10n.downloadCompletedTitle(widget.media.title)
              : downloading
              ? context.l10n.downloadItemStatus(
                  context.l10n.downloadStatusDownloading,
                  widget.media.title,
                )
              : stopping
              ? context.l10n.downloadStoppingTitle(widget.media.title)
              : waiting
              ? context.l10n.downloadQueuedTitle(widget.media.title)
              : context.l10n.downloadTitle(widget.media.title),
          child: widget.compact
              ? Tooltip(
                  message: context.l10n.downloadItemStatus(
                    label,
                    widget.media.title,
                  ),
                  child: OutlinedButton(
                    key: Key(
                      'download-action-${widget.media.kind.name}-${widget.media.id}',
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(40, 40),
                      fixedSize: const Size(40, 40),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: locked ? null : _start,
                    child: icon,
                  ),
                )
              : OutlinedButton.icon(
                  key: Key(
                    'download-action-${widget.media.kind.name}-${widget.media.id}',
                  ),
                  style: widget.style,
                  onPressed: locked ? null : _start,
                  icon: icon,
                  label: Text(label),
                ),
        );
      },
    );
  }
}
