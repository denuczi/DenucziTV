import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';
import '../domain/media_models.dart';

/// A truly centered title; right-aligned actions do not move the title.
/// Count is located below the title, never competing with the refresh button.
class CatalogHeader extends StatelessWidget {
  const CatalogHeader({
    super.key,
    required this.kind,
    required this.total,
    required this.visible,
    required this.loading,
    required this.onRefresh,
    required this.exportAvailable,
    required this.exporting,
    required this.onExport,
  });

  final LibraryKind kind;
  final int total;
  final int visible;
  final bool loading;
  final VoidCallback onRefresh;
  final bool exportAvailable;
  final bool exporting;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final title = switch (kind) {
      LibraryKind.live => l.liveTv,
      LibraryKind.movies => l.movies,
      LibraryKind.series => l.series,
    };
    final count = switch (kind) {
      LibraryKind.live => l.channelCount(total),
      LibraryKind.movies => l.movieCount(total),
      LibraryKind.series => l.seriesCount(total),
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 530;
        final actionSpace = exportAvailable ? (compact ? 110.0 : 190.0) : 60.0;
        // Hide metadata on narrow windows rather than overlapping actions.
        final showCount = constraints.maxWidth >= actionSpace * 2 + 170;
        return SizedBox(
          height: 60,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: actionSpace + 6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (showCount) ...[
                        const SizedBox(height: 2),
                        Text(
                          loading
                              ? l.loading
                              : visible == total
                              ? count
                              : l.filteredCount(visible.toString(), count),
                          key: const Key('catalogSpecificCount'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 12,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: l.reloadCatalog,
                      onPressed: loading ? null : onRefresh,
                      icon: const Icon(Icons.refresh, size: 20),
                    ),
                    if (exportAvailable)
                      compact
                          ? IconButton(
                              tooltip: l.exportM3u,
                              onPressed: loading || exporting ? null : onExport,
                              icon: const Icon(
                                Icons.file_download_outlined,
                                size: 20,
                              ),
                            )
                          : OutlinedButton.icon(
                              onPressed: loading || exporting ? null : onExport,
                              icon: const Icon(
                                Icons.file_download_outlined,
                                size: 17,
                              ),
                              label: Text(l.exportM3u),
                            ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
