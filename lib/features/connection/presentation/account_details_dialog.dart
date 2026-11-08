import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/app_controller.dart';
import '../../../core/models/account.dart';
import '../../../core/models/protected_account.dart';
import '../../../l10n/l10n_ext.dart';
import 'protected_account_labels.dart';

/// Shows account metadata without ever exposing authentication secrets.
class AccountDetailsDialog extends StatelessWidget {
  const AccountDetailsDialog({super.key, this.account});
  final Account? account;

  String _date(DateTime value) {
    final local = value.toLocal();
    String pad(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${pad(local.month)}-${pad(local.day)} '
        '${pad(local.hour)}:${pad(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final account = this.account ?? app.activeAccount;
    final status = app.accountStatus;
    final scheme = Theme.of(context).colorScheme;
    if (account == null) {
      return const SizedBox.shrink();
    }
    if (account.isProtected) {
      final expiration = app.protectedExpirations[account.id];
      final updated = app.protectedLastUpdated[account.id];
      final checking =
          app.protectedSyncStates[account.id] == ProtectedSyncState.checking;
      return AlertDialog(
        constraints: const BoxConstraints(maxWidth: 480),
        scrollable: true,
        title: Text(context.l10n.protectedSingleLink),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                account.label,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Text(context.l10n.protectedLinkConfigured),
              _DetailRow(
                label: context.l10n.accountType,
                value: protectedSyncLabel(
                  context,
                  app.protectedSyncStates[account.id],
                ),
              ),
              _DetailRow(
                label: context.l10n.lastSynchronization,
                value: updated == null
                    ? context.l10n.unknownAccountDate
                    : _date(updated),
              ),
              _DetailRow(
                label: context.l10n.expires,
                value: expiration == null
                    ? context.l10n.protectedExpiryUnknown
                    : _date(expiration),
              ),
              if (app.expiredProtectedAccounts.contains(account.id))
                Text(context.l10n.protectedExpired),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.close),
          ),
          FilledButton(
            onPressed: checking
                ? null
                : () => app.refreshProtectedAccount(account),
            child: Text(context.l10n.updateCredentials),
          ),
        ],
      );
    }
    final provider = Uri.tryParse(account.serverUrl)?.host ?? account.serverUrl;
    final streamFormats = status?.allowedFormats ?? const <String>[];

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.verified_user_outlined),
          const SizedBox(width: 12),
          Expanded(child: Text(context.l10n.providerAccount)),
          IconButton(
            tooltip: context.l10n.close,
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                account.label,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 7),
              Text(
                status?.status?.toLowerCase() == 'active' ||
                        (status?.status == null && status?.authorized == true)
                    ? context.l10n.accountStatusActive
                    : (status?.status ?? context.l10n.accountStatusUnknown),
                style: TextStyle(
                  color: status?.authorized == true
                      ? scheme.primary
                      : scheme.error,
                ),
              ),
              const SizedBox(height: 20),
              _DetailRow(label: context.l10n.provider, value: provider),
              _DetailRow(label: context.l10n.username, value: account.username),
              _DetailRow(label: context.l10n.server, value: account.serverUrl),
              _DetailRow(
                label: context.l10n.created,
                value: status?.createdAt == null
                    ? context.l10n.unknownAccountDate
                    : _date(status!.createdAt!),
              ),
              _DetailRow(
                label: context.l10n.expires,
                value: status?.expiration == null
                    ? context.l10n.unknownAccountDate
                    : _date(status!.expiration!),
              ),
              _DetailRow(
                label: context.l10n.connections,
                value:
                    '${status?.activeConnections?.toString() ?? '—'} / '
                    '${status?.maxConnections?.toString() ?? '—'}',
              ),
              _DetailRow(
                label: context.l10n.accountType,
                value: switch (status?.isTrial) {
                  true => context.l10n.trialAccount,
                  false => context.l10n.standardAccount,
                  null => context.l10n.unknownAccountDate,
                },
              ),
              _DetailRow(
                label: context.l10n.serverTimezone,
                value:
                    status?.serverTimezone ?? context.l10n.unknownAccountDate,
              ),
              _DetailRow(
                label: context.l10n.streamFormats,
                value: streamFormats.isEmpty
                    ? context.l10n.unknownAccountDate
                    : streamFormats.join(', '),
              ),
              const SizedBox(height: 12),
              Text(
                context.l10n.localTimezoneDates,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.close),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 146,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
