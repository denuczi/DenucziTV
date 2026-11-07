import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';

import '../../../core/theme/app_theme.dart';

enum ExportPhase { selecting, writing, success, failure }

/// Non-blocking desktop status for native file export operations.
class ExportNotice extends StatelessWidget {
  const ExportNotice({
    super.key,
    required this.phase,
    required this.message,
    required this.onDismiss,
    this.progress,
  });

  final ExportPhase phase;
  final String message;
  final double? progress;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final success = phase == ExportPhase.success;
    final failure = phase == ExportPhase.failure;
    final color = success
        ? (Theme.of(context).brightness == Brightness.dark
              ? AppPalette.success
              : const Color(0xFF116840))
        : failure
        ? scheme.error
        : scheme.primary;
    final active =
        phase == ExportPhase.selecting || phase == ExportPhase.writing;

    return Semantics(
      liveRegion: true,
      child: Material(
        elevation: 10,
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 330,
          padding: const EdgeInsets.fromLTRB(15, 13, 8, 13),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: .55)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    success
                        ? Icons.check_circle_rounded
                        : failure
                        ? Icons.error_outline_rounded
                        : Icons.file_download_outlined,
                    color: color,
                    size: 24,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      success
                          ? context.l10n.playlistSaved
                          : failure
                          ? context.l10n.exportFailed
                          : context.l10n.exportingPlaylist,
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.dismissNotification,
                    onPressed: active ? null : onDismiss,
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(35, 2, 10, 0),
                child: Text(
                  message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              if (active) ...[
                const SizedBox(height: 13),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(4),
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
