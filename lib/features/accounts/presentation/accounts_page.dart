import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/account.dart';
import '../../../core/models/app_controller.dart';
import '../../../l10n/app_error_localizations.dart';
import '../../../l10n/l10n_ext.dart';
import '../../../shared/navigation/dialog_launch_guard.dart';
import '../../connection/presentation/account_details_dialog.dart';
import '../../connection/presentation/connect_dialog.dart';

/// Saved provider profiles and cached, non-sensitive subscription metadata.
class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key});

  static String date(DateTime value) {
    final local = value.toLocal();
    String pad(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${pad(local.month)}-${pad(local.day)} '
        '${pad(local.hour)}:${pad(local.minute)}';
  }

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  final DialogLaunchGuard _dialogGuard = DialogLaunchGuard();

  Future<void> _openDialog(WidgetBuilder builder) => _dialogGuard.run(() async {
    if (!mounted) {
      return;
    }
    await showDialog<void>(context: context, builder: builder);
  });

  Future<void> _remove(Account account, AppController app) => _dialogGuard.run(
    () async {
      if (!mounted) {
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(dialogContext.l10n.removeSavedAccountQuestion),
          content: Text(dialogContext.l10n.removeAccountWarning(account.label)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(dialogContext.l10n.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(dialogContext.l10n.removeAccount),
            ),
          ],
        ),
      );
      if (confirmed == true && mounted) {
        await app.removeSaved(account);
      }
    },
  );

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 30, 32, 56),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.accounts,
                          style: theme.textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          context.l10n.accountSubtitle,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _openDialog((_) => const ConnectDialog()),
                    icon: const Icon(Icons.add),
                    label: Text(context.l10n.addAccount),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              if (app.error != null)
                Card(
                  child: ListTile(
                    title: Text(localizeAppError(context, app.error!)),
                    trailing: IconButton(
                      onPressed: app.clearError,
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
              if (app.savedAccounts.isEmpty)
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(context.l10n.accountsEmpty),
                  ),
                ),
              for (final account in app.savedAccounts)
                _AccountTile(
                  account: account,
                  status: app.accountStatuses[account.id],
                  isActive: app.activeAccount?.id == account.id,
                  isBusy: app.connecting,
                  onConnect: () => app.connectSaved(account),
                  onRemove: () => _remove(account, app),
                  onDetails: () =>
                      _openDialog((_) => const AccountDetailsDialog()),
                  onDisconnect: () async {
                    await app.disconnect();
                  },
                ),
              const SizedBox(height: 16),
              Text(
                context.l10n.savedAccountsMayBeOutdated,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.account,
    required this.status,
    required this.isActive,
    required this.isBusy,
    required this.onConnect,
    required this.onRemove,
    required this.onDetails,
    required this.onDisconnect,
  });

  final Account account;
  final AccountStatus? status;
  final bool isActive;
  final bool isBusy;
  final VoidCallback onConnect;
  final VoidCallback onRemove;
  final VoidCallback onDetails;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final provider = Uri.tryParse(account.serverUrl)?.host ?? account.serverUrl;
    final expired = status?.expiration?.isBefore(DateTime.now()) ?? false;
    final expiryLabel = expired ? context.l10n.expired : context.l10n.expires;
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: scheme.primaryContainer,
                    child: Icon(
                      Icons.dns_outlined,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.label,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          provider,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (isActive)
                    Chip(
                      label: Text(context.l10n.connected),
                      avatar: const Icon(
                        Icons.circle,
                        size: 10,
                        color: Color(0xFF329D70),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 22,
                runSpacing: 14,
                children: [
                  _Fact(context.l10n.username, account.username),
                  _Fact(
                    context.l10n.created,
                    status?.createdAt == null
                        ? context.l10n.unknownAccountDate
                        : AccountsPage.date(status!.createdAt!),
                  ),
                  _Fact(
                    expiryLabel,
                    status?.expiration == null
                        ? context.l10n.unknownAccountDate
                        : AccountsPage.date(status!.expiration!),
                  ),
                  _Fact(
                    context.l10n.connections,
                    '${status?.activeConnections?.toString() ?? '—'} / ${status?.maxConnections?.toString() ?? '—'}',
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (isActive) ...[
                      OutlinedButton.icon(
                        onPressed: onDetails,
                        icon: const Icon(Icons.info_outline),
                        label: Text(context.l10n.moreDetails),
                      ),
                      OutlinedButton(
                        onPressed: isBusy ? null : onDisconnect,
                        child: Text(context.l10n.disconnect),
                      ),
                    ] else
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF6ED8A4)
                              : const Color(0xFF176D48),
                          foregroundColor:
                              Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF10261B)
                              : Colors.white,
                        ),
                        onPressed: isBusy ? null : onConnect,
                        icon: const Icon(Icons.link_rounded),
                        label: Text(context.l10n.connect),
                      ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.error,
                      ),
                      onPressed: isBusy ? null : onRemove,
                      icon: const Icon(Icons.delete_outline),
                      label: Text(context.l10n.removeSavedAccount),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
      ],
    ),
  );
}
