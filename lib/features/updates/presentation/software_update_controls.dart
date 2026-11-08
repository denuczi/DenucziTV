import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../shared/notifications/app_notice.dart';
import '../application/update_controller.dart';
import '../domain/stable_release.dart';
import 'update_dialog.dart';
import 'update_labels.dart';

class SoftwareUpdateControls extends StatefulWidget {
  const SoftwareUpdateControls({super.key});
  @override
  State<SoftwareUpdateControls> createState() => _SoftwareUpdateControlsState();
}

class _SoftwareUpdateControlsState extends State<SoftwareUpdateControls> {
  bool _running = false;

  Future<void> _check(UpdateController updates) async {
    if (_running || updates.checking || updates.dialogGuard.isBusy) return;
    updates.suppressStartupPrompt();
    setState(() => _running = true);
    try {
      final result = await updates.checkManually();
      if (!mounted) return;
      setState(() => _running = false);
      if (result.offersUpdate) {
        await showStableUpdateDialog(context, updates, result.release!);
      } else if (result.status != UpdateStatus.cancelled) {
        AppNotice.show(
          context,
          level: result.status == UpdateStatus.upToDate
              ? NoticeLevel.success
              : result.status == UpdateStatus.noStableRelease
              ? NoticeLevel.info
              : NoticeLevel.warning,
          title: context.l10n.softwareUpdates,
          message: updateStatusLabel(context, result.status),
        );
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final updates = context.watch<UpdateController?>();
    final l10n = context.l10n;
    final busy = _running || updates?.checking == true;
    final lastCheck = updates?.lastSuccessfulCheck?.toLocal();
    final material = MaterialLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Wrap(
        spacing: 14,
        runSpacing: 4,
        children: [
          Text(label, style: textTheme.bodyMedium),
          Text(value, style: textTheme.labelLarge),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row(
          l10n.updatesInstalledVersion,
          updates?.installedDisplay ?? l10n.updatesUnknownVersion,
        ),
        if (updates?.latestRelease case final release?)
          row(l10n.updatesLatestStable, release.version.canonical),
        if (lastCheck != null)
          row(
            l10n.updatesLastChecked,
            '${material.formatMediumDate(lastCheck)} ${material.formatTimeOfDay(TimeOfDay.fromDateTime(lastCheck))}',
          ),
        const SizedBox(height: 4),
        Semantics(
          liveRegion: true,
          child: Text(
            updates == null
                ? l10n.updatesMetadataError
                : updateStatusLabel(context, updates.status),
            key: const Key('softwareUpdateStatus'),
            style: textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (updates?.preferenceWarning == true) ...[
          const SizedBox(height: 8),
          Text(l10n.updatesPreferenceWarning, style: textTheme.bodySmall),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            key: const Key('checkForUpdates'),
            onPressed: updates == null || busy || updates.dialogGuard.isBusy
                ? null
                : () => _check(updates),
            icon: busy
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 19),
            label: Text(busy ? l10n.updatesChecking : l10n.updatesCheck),
          ),
        ),
      ],
    );
  }
}
