import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';
import '../application/update_controller.dart';
import '../domain/stable_release.dart';

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

  Future<void> _open({required bool download}) async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _failed = false;
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
      // AlertDialog measures intrinsic sizes. Keep LayoutBuilder outside its
      // subtree and resolve responsive action widths before that measurement.
      // Reserve 40 px for dialog insets and 48 px for content/action padding.
      final contentWidth = math.min(
        472.0,
        math.max(0.0, constraints.maxWidth - 88),
      );
      return _buildDialog(context, contentWidth);
    },
  );

  Widget _buildDialog(BuildContext context, double contentWidth) {
    final buttonWidth = contentWidth < 420
        ? contentWidth
        : (contentWidth - 12) / 2;
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final release = widget.release;
    final compatible = release.assetFor(widget.updates.target) != null;
    return AlertDialog(
      key: const Key('stableUpdateDialog'),
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      constraints: BoxConstraints(
        maxWidth: 560,
        maxHeight: math.max(0, MediaQuery.sizeOf(context).height - 48),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          Icon(
            Icons.system_update_alt_rounded,
            color: colors.primary,
            size: 25,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(l10n.updatesTitle)),
          IconButton(
            tooltip: l10n.updatesPostponeClose,
            onPressed: _later,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: SizedBox(
        width: contentWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              compatible
                  ? l10n.updatesBody(release.version.canonical)
                  : l10n.updatesBodyWithoutPackage(release.version.canonical),
            ),
            const SizedBox(height: 20),
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
            const SizedBox(height: 18),
            Text(l10n.updatesNotes, style: theme.textTheme.titleSmall),
            const SizedBox(height: 7),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 140),
              child: SingleChildScrollView(
                child: Text(
                  release.notes.isEmpty ? l10n.updatesNoNotes : release.notes,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            if (_failed) ...[
              const SizedBox(height: 12),
              Text(
                l10n.updatesOpenFailed,
                key: const Key('updateLaunchError'),
                style: TextStyle(color: colors.error),
              ),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
      actions: [
        SizedBox(
          width: contentWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (compatible)
                TextButton(
                  onPressed: _opening ? null : () => _open(download: false),
                  child: Text(l10n.updatesViewNotes),
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
                              child: CircularProgressIndicator(strokeWidth: 2),
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
      ],
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
