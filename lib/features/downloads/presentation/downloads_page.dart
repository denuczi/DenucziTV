import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../l10n/app_error_localizations.dart';
import '../../../core/theme/app_theme.dart';

import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/platform/desktop_file_opener.dart';
import '../../../core/models/app_controller.dart';
import '../../../shared/notifications/app_notice.dart';
import '../data/download_manager.dart';
import '../data/download_storage_inspector.dart';
import '../domain/download_task.dart';
import 'download_storage_overview.dart';

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({
    super.key,
    this.fileOpener = const DesktopFileOpener(),
    this.storageInspector = const DownloadStorageInspector(),
  });

  final DesktopFileOpener fileOpener;
  final DownloadStorageInspector storageInspector;

  Future<void> _chooseDirectory(
    BuildContext context,
    DownloadManager manager,
  ) async {
    try {
      final directory = await getDirectoryPath(
        initialDirectory: manager.directory,
        confirmButtonText: context.l10n.useThisFolder,
      );
      if (directory == null) {
        return;
      }
      await manager.setDirectory(directory);
    } on AppException catch (error) {
      if (context.mounted) {
        _message(context, error.message);
      }
    } catch (_) {
      if (context.mounted) {
        _message(context, context.l10n.downloadFolderSelectFailed);
      }
    }
  }

  void _message(BuildContext context, String text) {
    AppNotice.show(
      context,
      level: NoticeLevel.error,
      title: context.l10n.couldNotUpdateDownloads,
      message: text,
    );
  }

  Future<void> _clearHistory(
    BuildContext context,
    DownloadManager manager,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        constraints: const BoxConstraints(maxWidth: 460),
        title: Text(context.l10n.clearDownloadHistoryQuestion),
        content: Text(context.l10n.downloadHistoryClearDetails),
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
    if (confirmed != true || !context.mounted) {
      return;
    }
    try {
      final count = await manager.clearHistory();
      if (context.mounted) {
        _historyNotice(
          context,
          manager,
          title: context.l10n.historyCleared,
          message: context.l10n.clearDownloadRecords(count),
        );
      }
    } on AppException catch (error) {
      if (context.mounted) {
        _message(context, error.message);
      }
    } catch (_) {
      if (context.mounted) {
        _message(context, context.l10n.downloadHistoryClearFailed);
      }
    }
  }

  void _historyNotice(
    BuildContext context,
    DownloadManager manager, {
    required String title,
    required String message,
  }) {
    final failure = manager.historyError;
    AppNotice.show(
      context,
      level: failure == null ? NoticeLevel.success : NoticeLevel.warning,
      title: failure == null ? title : context.l10n.historyNotSaved,
      message: failure ?? message,
    );
  }

  @override
  Widget build(BuildContext context) {
    final manager = context.read<AppController>().downloads;
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final tasks = manager.tasks;
        final scheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(28, 26, 28, 16),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 960),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.downloads,
                          style: textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          context.l10n.manageDownloads,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 24),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final location = Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.folder_outlined,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            context.l10n.downloadLocation,
                                            style: textTheme.titleMedium,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    SelectableText(
                                      manager.directory ??
                                          context.l10n.noFolderSelected,
                                      style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    OutlinedButton.icon(
                                      onPressed: () =>
                                          _chooseDirectory(context, manager),
                                      icon: const Icon(
                                        Icons.folder_open_outlined,
                                      ),
                                      label: Text(
                                        manager.directory == null
                                            ? context.l10n.chooseFolder
                                            : context.l10n.changeFolder,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      context.l10n.savedForFuture,
                                      style: textTheme.bodySmall?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                );
                                final overview = DownloadStorageOverview(
                                  manager: manager,
                                  inspector: storageInspector,
                                );
                                if (constraints.maxWidth < 700) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      location,
                                      const SizedBox(height: 18),
                                      overview,
                                    ],
                                  );
                                }
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(flex: 5, child: location),
                                    const SizedBox(width: 26),
                                    Expanded(flex: 4, child: overview),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                        if (manager.historyError != null) ...[
                          const SizedBox(height: 14),
                          Semantics(
                            liveRegion: true,
                            child: Card(
                              color: scheme.errorContainer,
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.warning_amber_rounded,
                                      color: scheme.onErrorContainer,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        manager.historyError!,
                                        style: TextStyle(
                                          color: scheme.onErrorContainer,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 26),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final heading = Text(
                              context.l10n.transferActivity,
                              style: textTheme.titleLarge,
                            );
                            final active = manager.activeCount > 0
                                ? Text(
                                    context.l10n.activeDownloads(
                                      manager.activeCount,
                                    ),
                                    style: TextStyle(color: scheme.primary),
                                  )
                                : null;
                            final clearButton = manager.canClearHistory
                                ? OutlinedButton.icon(
                                    onPressed: () =>
                                        _clearHistory(context, manager),
                                    icon: const Icon(
                                      Icons.history_toggle_off_outlined,
                                      size: 18,
                                    ),
                                    label: Text(context.l10n.clearHistory),
                                  )
                                : null;
                            if (constraints.maxWidth < 680) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  heading,
                                  if (active != null) ...[
                                    const SizedBox(height: 6),
                                    active,
                                  ],
                                  if (clearButton != null) ...[
                                    const SizedBox(height: 12),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: clearButton,
                                    ),
                                  ],
                                ],
                              );
                            }
                            return Row(
                              children: [
                                heading,
                                if (active != null) ...[
                                  const SizedBox(width: 12),
                                  active,
                                ],
                                const Spacer(),
                                ?clearButton,
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (tasks.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                sliver: SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 960),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 40,
                            horizontal: 20,
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.download_for_offline_outlined,
                                size: 42,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                context.l10n.downloadsEmptyHelp,
                                style: textTheme.titleMedium,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                context.l10n.mediaActionsDownloadsHelp,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 56),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 960),
                        child: _TransferTile(
                          task: tasks[index],
                          manager: manager,
                          fileOpener: fileOpener,
                        ),
                      ),
                    ),
                    childCount: tasks.length,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TransferTile extends StatelessWidget {
  const _TransferTile({
    required this.task,
    required this.manager,
    required this.fileOpener,
  });

  final DownloadTask task;
  final DownloadManager manager;
  final DesktopFileOpener fileOpener;

  Future<void> _openFile(BuildContext context) async {
    try {
      await fileOpener.play(task.destination);
    } on AppException catch (error) {
      if (context.mounted) {
        _error(context, error.message);
      }
    } catch (_) {
      if (context.mounted) {
        _error(context, context.l10n.systemPlayerOpenFailed);
      }
    }
  }

  Future<void> _openFolder(BuildContext context) async {
    try {
      await fileOpener.openContainingFolder(task.destination);
    } on AppException catch (error) {
      if (context.mounted) {
        _error(context, error.message);
      }
    } catch (_) {
      if (context.mounted) {
        _error(context, context.l10n.fileManagerOpenFailed);
      }
    }
  }

  Future<void> _removeHistory(BuildContext context) async {
    // The tile will be removed after the operation. Keep a stable context for
    // the overlay notification instead of using the unmounted list item.
    final noticeContext = Navigator.of(context, rootNavigator: true).context;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.removeHistoryQuestion),
        content: Text(context.l10n.downloadRemoveWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.removeEntry),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    try {
      await manager.removeFromHistory(task.id);
      if (noticeContext.mounted) {
        _historyNotice(
          noticeContext,
          title: noticeContext.l10n.historyEntryRemoved,
          message: noticeContext.l10n.completedFilesKept,
        );
      }
    } on AppException catch (error) {
      if (noticeContext.mounted) {
        _error(noticeContext, error.message);
      }
    } catch (_) {
      if (noticeContext.mounted) {
        _error(noticeContext, noticeContext.l10n.downloadHistoryUpdateFailed);
      }
    }
  }

  Future<void> _deleteFile(BuildContext context) async {
    final noticeContext = Navigator.of(context, rootNavigator: true).context;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.deleteDownloadedQuestion),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.downloadDeleteFullWarning),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 130),
              child: SingleChildScrollView(
                child: SelectableText(
                  task.destination,
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.keepFile),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.deleteFile),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    try {
      await manager.deleteDownloadedFile(task.id);
      if (noticeContext.mounted) {
        _historyNotice(
          noticeContext,
          title: noticeContext.l10n.fileDeleted,
          message: noticeContext.l10n.downloadAndHistoryRemoved,
        );
      }
    } on AppException catch (error) {
      if (noticeContext.mounted) {
        _error(noticeContext, error.message);
      }
    } catch (_) {
      if (noticeContext.mounted) {
        _error(noticeContext, noticeContext.l10n.downloadFileDeleteFailed);
      }
    }
  }

  void _historyNotice(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    final failure = manager.historyError;
    AppNotice.show(
      context,
      level: failure == null ? NoticeLevel.success : NoticeLevel.warning,
      title: failure == null ? title : context.l10n.historyNotSaved,
      message: failure ?? message,
    );
  }

  void _error(BuildContext context, String message) {
    AppNotice.show(
      context,
      level: NoticeLevel.error,
      title: context.l10n.downloadActionFailed,
      message: message,
    );
  }

  String _bytes(int value) {
    if (value < 1024) {
      return '$value B';
    }
    if (value < 1048576) {
      return '${(value / 1024).toStringAsFixed(1)} KB';
    }
    if (value < 1073741824) {
      return '${(value / 1048576).toStringAsFixed(1)} MB';
    }
    return '${(value / 1073741824).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final running = task.status == DownloadStatus.downloading;
    final queued = task.status == DownloadStatus.queued;
    final total = task.totalBytes;
    final progressText = total == null || total <= 0
        ? context.l10n.downloadedTotalUnknown(_bytes(task.bytesReceived))
        : context.l10n.downloadedRemaining(
            _bytes(task.bytesReceived),
            _bytes(total),
            _bytes(task.remainingBytes!),
          );
    final percent = task.percentComplete;
    final failed = task.status == DownloadStatus.failed;
    final completed = task.status == DownloadStatus.completed;
    final statusColor = switch (task.status) {
      DownloadStatus.completed =>
        theme.brightness == Brightness.dark
            ? const Color(0xFF63D8A2)
            : const Color(0xFF137B4D),
      DownloadStatus.failed => scheme.error,
      DownloadStatus.cancelled ||
      DownloadStatus.interrupted => scheme.onSurfaceVariant,
      _ => AppPalette.information(theme.brightness),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      completed
                          ? Icons.check_circle_outline_rounded
                          : failed
                          ? Icons.error_outline_rounded
                          : Icons.downloading_rounded,
                      color: statusColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          switch (task.status) {
                            DownloadStatus.queued =>
                              context.l10n.downloadStatusQueued,
                            DownloadStatus.downloading =>
                              context.l10n.downloadStatusDownloading,
                            DownloadStatus.completed =>
                              context.l10n.downloadStatusDownloaded,
                            DownloadStatus.failed =>
                              context.l10n.downloadStatusFailed,
                            DownloadStatus.cancelled =>
                              context.l10n.downloadStatusCancelled,
                            DownloadStatus.interrupted =>
                              context.l10n.downloadStatusInterrupted,
                          }.toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (running || queued)
                    IconButton(
                      tooltip: context.l10n.cancelDownload,
                      onPressed: manager.isFinalizing(task.id)
                          ? null
                          : () => manager.cancel(task.id),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  if ((failed || task.status == DownloadStatus.cancelled) &&
                      manager.canRetry(task.id))
                    TextButton.icon(
                      onPressed: () => manager.retry(task.id),
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(
                        task.bytesReceived > 0
                            ? context.l10n.resume
                            : context.l10n.retry,
                      ),
                    ),
                ],
              ),
              if (running || queued) ...[
                const SizedBox(height: 15),
                LinearProgressIndicator(
                  value: task.progress,
                  minHeight: 5,
                  color: statusColor,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (percent != null) ...[
                      Text(
                        '$percent%',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        progressText,
                        style: theme.textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              if (completed) ...[
                const SizedBox(height: 10),
                Text(
                  context.l10n.progressComplete,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (completed ||
                  (task.message != null && task.message!.isNotEmpty)) ...[
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final notice = Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.07),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.28),
                        ),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        task.message?.isNotEmpty == true
                            ? localizeAppError(context, task.message!)
                            : context.l10n.savedSuccessfully,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: failed ? scheme.error : scheme.onSurface,
                        ),
                      ),
                    );
                    if (!completed) {
                      return notice;
                    }
                    final play = OutlinedButton.icon(
                      key: Key('play-download-${task.id}'),
                      onPressed: () => _openFile(context),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: Text(context.l10n.playInSystemPlayer),
                    );
                    if (constraints.maxWidth < 580) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          notice,
                          const SizedBox(height: 10),
                          Align(alignment: Alignment.centerRight, child: play),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: notice),
                        const SizedBox(width: 12),
                        play,
                      ],
                    );
                  },
                ),
              ],
              if ((failed ||
                      task.status == DownloadStatus.cancelled ||
                      task.status == DownloadStatus.interrupted) &&
                  task.bytesReceived > 0) ...[
                const SizedBox(height: 7),
                Text(
                  context.l10n.partialPreserved(_bytes(task.bytesReceived)),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: 15,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Tooltip(
                      message: task.destination,
                      child: Text(
                        task.destination,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.copyFilePath,
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: task.destination),
                      );
                      if (context.mounted) {
                        AppNotice.show(
                          context,
                          level: NoticeLevel.success,
                          title: context.l10n.filePathCopied,
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final folderButton = OutlinedButton.icon(
                    key: Key('open-folder-${task.id}'),
                    onPressed: () => _openFolder(context),
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                    label: Text(context.l10n.openFolder),
                  );
                  final actions = Wrap(
                    key: Key('historyActions-${task.id}'),
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (!(running || queued)) ...[
                        TextButton.icon(
                          key: Key('remove-history-${task.id}'),
                          onPressed: manager.isTransferActive(task.id)
                              ? null
                              : () => _removeHistory(context),
                          icon: const Icon(Icons.history_rounded, size: 18),
                          label: Text(context.l10n.removeHistory),
                        ),
                        if (completed)
                          TextButton.icon(
                            key: Key('delete-file-${task.id}'),
                            style: TextButton.styleFrom(
                              foregroundColor: scheme.error,
                            ),
                            onPressed: () => _deleteFile(context),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                            ),
                            label: Text(context.l10n.deleteFile),
                          ),
                      ],
                    ],
                  );
                  if (constraints.maxWidth < 480) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: folderButton,
                        ),
                        if (!(running || queued)) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: actions,
                          ),
                        ],
                      ],
                    );
                  }
                  return Row(
                    children: [
                      folderButton,
                      const SizedBox(width: 10),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: actions,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
