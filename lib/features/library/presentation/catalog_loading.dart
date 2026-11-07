import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';

/// A centered, accessible loading state for slow provider catalogs.
/// Avoids suggesting an empty library before the request has completed.
class CatalogLoading extends StatelessWidget {
  const CatalogLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Center(
      child: Semantics(
        liveRegion: true,
        label: context.l10n.loadingMediaLibrary,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 42,
                  height: 42,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  context.l10n.loadingLibrary,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.loadingMediaLibraryHelp,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
