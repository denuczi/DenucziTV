import 'package:flutter/widgets.dart';

import '../../../core/models/protected_account.dart';
import '../../../l10n/l10n_ext.dart';

String protectedSyncLabel(BuildContext context, ProtectedSyncState? state) =>
    switch (state) {
      ProtectedSyncState.checking => context.l10n.protectedChecking,
      ProtectedSyncState.updated => context.l10n.protectedUpdated,
      ProtectedSyncState.failed => context.l10n.protectedFailed,
      ProtectedSyncState.expired => context.l10n.expired,
      _ => context.l10n.protectedPending,
    };
