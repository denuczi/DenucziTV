import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';

import '../data/download_manager.dart';
import '../data/download_storage_inspector.dart';
import '../domain/download_task.dart';

/// A bounded, on-demand disk inspection independent from transfer progress.
///
/// Rebuilds caused by a downloading task do not trigger disk scans. A new
/// inspection starts when terminal history changes or the user requests one.
class DownloadStorageOverview extends StatefulWidget {
  const DownloadStorageOverview({
    super.key,
    required this.manager,
    this.inspector = const DownloadStorageInspector(),
  });

  final DownloadManager manager;
  final DownloadStorageInspector inspector;

  @override
  State<DownloadStorageOverview> createState() =>
      _DownloadStorageOverviewState();
}

class _DownloadStorageOverviewState extends State<DownloadStorageOverview> {
  DownloadStorageSummary? _summary;
  String? _error;
  bool _loading = true;
  int _generation = 0;
  late String _signature;

  String _historySignature() {
    final buffer = StringBuffer();
    for (final task in widget.manager.tasks) {
      if (task.status == DownloadStatus.queued ||
          task.status == DownloadStatus.downloading) {
        continue;
      }
      buffer.write('${task.id.length}:${task.id}:${task.status.index}:');
      buffer.write('${task.destination.length}:${task.destination}:');
    }
    return buffer.toString();
  }

  @override
  void initState() {
    super.initState();
    _signature = _historySignature();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refresh();
      }
    });
  }

  @override
  void didUpdateWidget(covariant DownloadStorageOverview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextSignature = _historySignature();
    if (nextSignature != _signature || oldWidget.manager != widget.manager) {
      _signature = nextSignature;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _refresh();
        }
      });
    }
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await widget.inspector.inspect(widget.manager.tasks);
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _summary = summary;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _loading = false;
        _error = context.l10n.storageCalculationFailed;
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final summary = _summary;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.storage_outlined,
                  size: 19,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.l10n.trackedStorage,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  key: const Key('refreshTrackedStorage'),
                  tooltip: context.l10n.refreshStorage,
                  onPressed: _loading ? null : _refresh,
                  icon: const Icon(Icons.refresh_rounded, size: 19),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading && summary == null)
              const LinearProgressIndicator(minHeight: 3)
            else if (_error != null)
              Text(_error!, style: TextStyle(color: colors.error))
            else if (summary != null) ...[
              Text(
                _formatBytes(summary.totalBytes),
                key: const Key('trackedStorageTotal'),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${context.l10n.filesCompleted(summary.completedFiles)} · ${_formatBytes(summary.completedBytes)}',
                style: theme.textTheme.bodySmall,
              ),
              if (summary.partialFiles > 0)
                Text(
                  '${context.l10n.filesPartial(summary.partialFiles)} · ${_formatBytes(summary.partialBytes)}',
                  style: theme.textTheme.bodySmall,
                ),
              if (summary.unavailableFiles > 0)
                Text(
                  context.l10n.filesMissing(summary.unavailableFiles),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.error,
                  ),
                ),
            ],
            const SizedBox(height: 10),
            Text(
              context.l10n.trackedStorageHelp,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
