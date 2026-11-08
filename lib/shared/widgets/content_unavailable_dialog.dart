import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/app_controller.dart';
import '../../l10n/l10n_ext.dart';

/// Replaces stale detail actions after a protected source switch or revocation.
class ContentUnavailableDialog extends StatelessWidget {
  const ContentUnavailableDialog({super.key});
  @override
  Widget build(BuildContext context) => AlertDialog(
    constraints: const BoxConstraints(maxWidth: 480),
    scrollable: true,
    title: Text(context.l10n.contentUnavailable),
    content: Text(context.l10n.updatedSourceExplanation),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.close),
      ),
      FilledButton(
        onPressed: () {
          context.read<AppController>().exploreUpdatedCatalog();
          Navigator.of(context).popUntil((route) => route.isFirst);
        },
        child: Text(context.l10n.exploreCatalog),
      ),
    ],
  );
}
