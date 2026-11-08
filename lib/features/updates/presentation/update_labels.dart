import 'package:flutter/widgets.dart';

import '../../../l10n/l10n_ext.dart';
import '../domain/stable_release.dart';

String updateStatusLabel(BuildContext context, UpdateStatus status) {
  final l10n = context.l10n;
  return switch (status) {
    UpdateStatus.idle => l10n.updatesIdle,
    UpdateStatus.checking => l10n.updatesChecking,
    UpdateStatus.updateAvailable => l10n.updatesAvailable,
    UpdateStatus.upToDate => l10n.updatesUpToDate,
    UpdateStatus.noStableRelease => l10n.updatesNoStable,
    UpdateStatus.packageUnavailable => l10n.updatesPackageUnavailable,
    UpdateStatus.offline => l10n.updatesOffline,
    UpdateStatus.timedOut => l10n.updatesTimeout,
    UpdateStatus.rateLimited => l10n.updatesRateLimited,
    UpdateStatus.serverError => l10n.updatesServerError,
    UpdateStatus.invalidResponse => l10n.updatesInvalidResponse,
    UpdateStatus.metadataUnavailable => l10n.updatesMetadataError,
    UpdateStatus.cancelled => l10n.updatesCancelled,
  };
}
