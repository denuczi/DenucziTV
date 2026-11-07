import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';

import '../../../core/errors/app_exception.dart';
import '../data/download_manager.dart';

/// Prompts once, in the current media context, before enqueuing a download.
/// Cancelling leaves the movie or episode dialog and its selection intact.
Future<bool> ensureDownloadFolder(
  BuildContext context,
  DownloadManager manager,
) async {
  if (manager.directory != null) {
    return true;
  }
  return await showDialog<bool>(
        context: context,
        builder: (_) => _DownloadFolderPrompt(manager: manager),
      ) ??
      false;
}

class _DownloadFolderPrompt extends StatefulWidget {
  const _DownloadFolderPrompt({required this.manager});

  final DownloadManager manager;

  @override
  State<_DownloadFolderPrompt> createState() => _DownloadFolderPromptState();
}

class _DownloadFolderPromptState extends State<_DownloadFolderPrompt> {
  bool _busy = false;
  String? _error;

  Future<void> _select() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final path = await getDirectoryPath(
        confirmButtonText: context.l10n.useThisFolder,
        canCreateDirectories: true,
      );
      if (path == null || !mounted) {
        return;
      }
      await widget.manager.setDirectory(path);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on AppException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = context.l10n.downloadFolderSaveFailed);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: const Icon(Icons.folder_open_outlined, size: 32),
      title: Text(context.l10n.chooseDownloadFolder),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.l10n.downloadFolderHelp),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: scheme.error)),
            ],
            if (_busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text(context.l10n.cancel),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _select,
          icon: const Icon(Icons.folder_open),
          label: Text(context.l10n.chooseFolder),
        ),
      ],
    );
  }
}
