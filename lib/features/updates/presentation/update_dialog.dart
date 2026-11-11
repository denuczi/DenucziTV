import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';
import '../application/update_controller.dart';
import '../domain/stable_release.dart';
import 'release_notes_markdown.dart';

enum UpdateDialogAction { downloaded, later }

Future<void> showStableUpdateDialog(
  BuildContext context,
  UpdateController updates,
  StableRelease release,
) => updates.dialogGuard.run(() async {
  if (!context.mounted || updates.isDisposed) return;
  final action = await showDialog<UpdateDialogAction>(
    context: context,
    builder: (_) => StableUpdateDialog(updates: updates, release: release),
  );
  // Includes barrier dismissal, Escape, and the close button. Persistence never
  // delays closing the modal, and no download is started by postponement.
  if (action != UpdateDialogAction.downloaded) {
    updates.cancelDownload();
    unawaited(updates.postpone(release));
  }
});

class StableUpdateDialog extends StatefulWidget {
  const StableUpdateDialog({
    super.key,
    required this.updates,
    required this.release,
  });
  final UpdateController updates;
  final StableRelease release;

  @override
  State<StableUpdateDialog> createState() => _StableUpdateDialogState();
}

class _StableUpdateDialogState extends State<StableUpdateDialog> {
  bool _opening = false;
  bool _failed = false;
  bool _externalLinkFailed = false;
  bool _openingLink = false;
  final ScrollController _notesScroll = ScrollController();

  @override
  void dispose() {
    _notesScroll.dispose();
    super.dispose();
  }

  Future<bool> _openReleaseLink(Uri uri) async {
    if (_openingLink || !mounted) {
      return false;
    }
    _openingLink = true;
    try {
      return await widget.updates.openReleaseNotesLink(uri);
    } catch (_) {
      return false;
    } finally {
      _openingLink = false;
    }
  }

  void _linkFailed() {
    if (mounted) {
      setState(() => _externalLinkFailed = true);
    }
  }

  Future<void> _open({required bool download}) async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _failed = false;
      _externalLinkFailed = false;
    });
    final opened = download
        ? await widget.updates.download(widget.release)
        : await widget.updates.openNotes(widget.release);
    if (!mounted) return;
    setState(() {
      _opening = false;
      _failed = !opened;
    });
    if (opened && download) {
      Navigator.pop(context, UpdateDialogAction.downloaded);
    }
  }

  void _later() => Navigator.pop(context, UpdateDialogAction.later);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final dialogWidth = math.min(
        600.0,
        math.max(0.0, constraints.maxWidth - 40),
      );
      final contentWidth = math.max(0.0, dialogWidth - 48);
      final height = math.max(0.0, constraints.maxHeight - 48);
      return _buildDialog(context, dialogWidth, contentWidth, height);
    },
  );

  Widget _buildDialog(
    BuildContext context,
    double dialogWidth,
    double contentWidth,
    double maxHeight,
  ) {
    final buttonWidth = contentWidth < 420
        ? contentWidth
        : (contentWidth - 12) / 2;
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final release = widget.release;
    final compatible = release.assetFor(widget.updates.target) != null;

    return Dialog(
      key: const Key('stableUpdateDialog'),
      backgroundColor: colors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SizedBox(
        width: dialogWidth,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.system_update_alt_rounded,
                      color: colors.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l10n.updatesTitle,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.updatesPostponeClose,
                      onPressed: _later,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Only the content scrolls. The title and actions always remain
                // available, even for long notes or a small desktop window.
                Flexible(
                  child: Scrollbar(
                    controller: _notesScroll,
                    child: SingleChildScrollView(
                      key: const Key('releaseNotesScroll'),
                      controller: _notesScroll,
                      padding: const EdgeInsets.only(right: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            compatible
                                ? l10n.updatesBody(release.version.canonical)
                                : l10n.updatesBodyWithoutPackage(
                                    release.version.canonical,
                                  ),
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 18),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: colors.outlineVariant),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                children: [
                                  _VersionRow(
                                    l10n.updatesInstalledVersion,
                                    widget.updates.installedDisplay ??
                                        l10n.updatesUnknownVersion,
                                  ),
                                  const SizedBox(height: 10),
                                  _VersionRow(
                                    l10n.updatesAvailableVersion,
                                    release.version.canonical,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            l10n.updatesNotes,
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 10),
                          if (release.notes.isEmpty)
                            Text(
                              l10n.updatesNoNotes,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            )
                          else
                            ReleaseNotesMarkdown(
                              notes: release.notes,
                              openLink: _openReleaseLink,
                              onLinkFailure: _linkFailed,
                            ),
                          if (release.notesTruncated) ...[
                            const SizedBox(height: 12),
                            Text(
                              l10n.updatesNotesTruncated,
                              key: const Key('releaseNotesTruncated'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (_failed || _externalLinkFailed) ...[
                  const SizedBox(height: 8),
                  Text(
                    _externalLinkFailed
                        ? l10n.updatesLinkOpenFailed
                        : l10n.updatesOpenFailed,
                    key: const Key('updateLaunchError'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.error,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Divider(height: 1, color: colors.outlineVariant),
                const SizedBox(height: 12),
                if (compatible)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _opening ? null : () => _open(download: false),
                      child: Text(l10n.updatesViewNotes),
                    ),
                  ),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: buttonWidth,
                      height: 46,
                      child: OutlinedButton(
                        key: const Key('postponeUpdate'),
                        onPressed: _later,
                        child: Text(l10n.updatesMaybeLater),
                      ),
                    ),
                    SizedBox(
                      width: buttonWidth,
                      height: 46,
                      child: FilledButton.icon(
                        key: Key(
                          compatible ? 'downloadUpdate' : 'viewUpdateNotes',
                        ),
                        onPressed: _opening
                            ? null
                            : () => _open(download: compatible),
                        icon: _opening
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                compatible
                                    ? Icons.download_rounded
                                    : Icons.open_in_new_rounded,
                                size: 19,
                              ),
                        label: Text(
                          compatible
                              ? l10n.updatesDownload
                              : l10n.updatesViewNotes,
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
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Text(label, style: Theme.of(context).textTheme.bodySmall),
      ),
      const SizedBox(width: 14),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ),
    ],
  );
}
