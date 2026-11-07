import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';

import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/models/app_controller.dart';
import '../../../shared/notifications/app_notice.dart';
import '../../downloads/presentation/download_folder_prompt.dart';
import '../../downloads/domain/download_task.dart';
import '../domain/media_models.dart';

enum MediaAction { copyLink, download }

/// Reuses the same actions from cards, detail dialogs and episode lists.
/// These controls are hidden until explicitly enabled in Settings.
class MediaActionMenu extends StatelessWidget {
  const MediaActionMenu({
    super.key,
    required this.media,
    this.onMenuOpened,
    this.onMenuClosed,
  });

  final MediaEntry media;
  final VoidCallback? onMenuOpened;
  final VoidCallback? onMenuClosed;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    return ListenableBuilder(
      listenable: app.downloads,
      builder: (context, _) {
        final task = app.downloads.taskForMedia(
          app.activeAccount?.id ?? 'unscoped',
          media,
        );
        final occupied = task != null;
        final statusLabel = switch (task?.status) {
          DownloadStatus.queued => context.l10n.downloadStatusQueued,
          DownloadStatus.downloading => context.l10n.downloadStatusDownloading,
          DownloadStatus.completed => context.l10n.downloadStatusDownloaded,
          _ => context.l10n.downloadVideo,
        };
        return PopupMenuButton<MediaAction>(
          tooltip: context.l10n.mediaActions,
          icon: occupied && task.status != DownloadStatus.completed
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    value: task.progress,
                    strokeWidth: 2.2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                )
              : Icon(
                  occupied
                      ? Icons.check_circle_outline_rounded
                      : Icons.more_horiz_rounded,
                ),
          onOpened: onMenuOpened,
          onCanceled: onMenuClosed,
          onSelected: (action) async {
            try {
              await performMediaAction(context, media, action);
            } finally {
              onMenuClosed?.call();
            }
          },
          itemBuilder: (_) => [
            if (app.showCopyLinkControls)
              PopupMenuItem(
                value: MediaAction.copyLink,
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.link),
                  title: Text(context.l10n.copyStreamUrl),
                ),
              ),
            if (app.showDownloadControls && media.kind != LibraryKind.live)
              PopupMenuItem(
                value: MediaAction.download,
                enabled: !occupied,
                child: ListTile(
                  dense: true,
                  leading: occupied && task.status != DownloadStatus.completed
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            value: task.progress,
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        )
                      : Icon(
                          occupied
                              ? Icons.check_circle_outline
                              : Icons.download_outlined,
                        ),
                  title: Text(statusLabel),
                ),
              ),
          ],
        );
      },
    );
  }
}

Future<void> performMediaAction(
  BuildContext context,
  MediaEntry media,
  MediaAction action,
) async {
  final app = context.read<AppController>();
  final credentials = app.credentials;
  final selectedAccountId = app.activeAccount?.id;
  final accountId = selectedAccountId ?? 'unscoped';
  if (credentials == null) {
    _notify(
      context,
      context.l10n.connectProviderFirst,
      level: NoticeLevel.warning,
    );
    return;
  }
  try {
    if (action == MediaAction.copyLink) {
      final url = app.api.streamUrl(credentials, media);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.l10n.copyCredentialUrlQuestion),
          content: Text(context.l10n.copyUrlSecurityDetails),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(context.l10n.copyLink),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) {
        return;
      }
      await Clipboard.setData(ClipboardData(text: url.toString()));
      if (context.mounted) {
        _notify(context, context.l10n.streamUrlCopiedWarning);
      }
    } else {
      if (!await ensureDownloadFolder(context, app.downloads) ||
          !context.mounted) {
        return;
      }
      if (app.activeAccount?.id != selectedAccountId) {
        throw AppException(context.l10n.accountChangedDownload);
      }
      final count = await app.downloads.enqueue(
        credentials: credentials,
        api: app.api,
        media: [media],
        accountId: accountId,
      );
      if (context.mounted) {
        _notify(
          context,
          count == 0
              ? context.l10n.alreadyQueuedOrDownloaded
              : context.l10n.downloadQueuedCount(count),
          level: NoticeLevel.info,
        );
      }
    }
  } on AppException catch (error) {
    if (context.mounted) {
      _notify(context, error.message, level: NoticeLevel.error);
    }
  } catch (_) {
    if (context.mounted) {
      _notify(
        context,
        context.l10n.mediaActionCompleteFailed,
        level: NoticeLevel.error,
      );
    }
  }
}

Future<void> downloadSeason(
  BuildContext context,
  String seriesTitle,
  int season,
  List<MediaEntry> episodes,
) async {
  final app = context.read<AppController>();
  final credentials = app.credentials;
  final selectedAccountId = app.activeAccount?.id;
  final accountId = selectedAccountId ?? 'unscoped';
  if (credentials == null) {
    return;
  }
  try {
    if (!await ensureDownloadFolder(context, app.downloads) ||
        !context.mounted) {
      return;
    }
    if (app.activeAccount?.id != selectedAccountId) {
      throw AppException(context.l10n.accountChangedSeason);
    }
    final count = await app.downloads.enqueue(
      credentials: credentials,
      api: app.api,
      media: episodes,
      accountId: accountId,
      subfolder: '$seriesTitle - Season ${season.toString().padLeft(2, '0')}',
    );
    if (context.mounted) {
      _notify(
        context,
        count == 0
            ? context.l10n.episodesAlreadyQueued
            : context.l10n.episodesQueuedCount(count),
        level: NoticeLevel.info,
      );
    }
  } on AppException catch (error) {
    if (context.mounted) {
      _notify(context, error.message, level: NoticeLevel.error);
    }
  } catch (_) {
    if (context.mounted) {
      _notify(
        context,
        context.l10n.seasonQueueFailed,
        level: NoticeLevel.error,
      );
    }
  }
}

void _notify(
  BuildContext context,
  String message, {
  NoticeLevel level = NoticeLevel.success,
}) {
  AppNotice.show(
    context,
    level: level,
    title: switch (level) {
      NoticeLevel.error => context.l10n.actionFailed,
      NoticeLevel.warning => context.l10n.actionRequired,
      NoticeLevel.info => context.l10n.downloadStarted,
      NoticeLevel.success => context.l10n.actionCompleted,
    },
    message: message,
  );
}
