import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../core/errors/app_exception.dart';
import '../../../l10n/l10n_ext.dart';
import '../data/download_manager.dart';

/// Prompts before the first download without closing the media details dialog.
/// The native file chooser must start only after the Flutter prompt is gone.
Future<bool> ensureDownloadFolder(
  BuildContext context,
  DownloadManager manager, {
  Future<String?> Function(String confirmButtonText)? selectDirectory,
}) async {
  if (manager.directory != null) {
    return true;
  }

  String? errorMessage;
  while (manager.directory == null) {
    if (!context.mounted) {
      return false;
    }

    final route = DialogRoute<bool>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          icon: const Icon(Icons.folder_open_outlined, size: 32),
          title: Text(dialogContext.l10n.chooseDownloadFolder),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(dialogContext.l10n.downloadFolderHelp),
                if (errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(errorMessage, style: TextStyle(color: scheme.error)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(dialogContext.l10n.cancel),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.folder_open),
              label: Text(dialogContext.l10n.chooseFolder),
            ),
          ],
        );
      },
    );

    final shouldSelect = await Navigator.of(
      context,
      rootNavigator: true,
    ).push(route);
    // The route future resolves before its reverse animation finishes.
    // Wait until its modal barrier is removed before opening a native dialog.
    await route.completed;
    if (shouldSelect != true || !context.mounted) {
      return false;
    }

    try {
      final buttonText = context.l10n.useThisFolder;
      final path =
          await (selectDirectory?.call(buttonText) ??
              getDirectoryPath(
                confirmButtonText: buttonText,
                canCreateDirectories: true,
              ));
      if (path == null || !context.mounted) {
        return false;
      }
      await manager.setDirectory(path);
      return context.mounted;
    } on AppException catch (error) {
      errorMessage = error.message;
    } catch (_) {
      if (!context.mounted) {
        return false;
      }
      errorMessage = context.l10n.downloadFolderSelectFailed;
    }
  }

  return context.mounted && manager.directory != null;
}
