import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/l10n_ext.dart';

enum NoticeLevel { info, success, warning, error }

/// Shows a compact, semantic notification above modal routes.
///
/// ScaffoldMessenger belongs to the underlying Scaffold and can be obscured
/// by dialogs. The root Navigator overlay always presents above dialog routes.
class AppNotice {
  AppNotice._();

  static OverlayEntry? _active;
  static Timer? _dismissTimer;

  static void show(
    BuildContext context, {
    required NoticeLevel level,
    required String title,
    String? message,
    Duration duration = const Duration(seconds: 6),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    _dismiss();

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) {
        final theme = Theme.of(overlayContext);
        final scheme = theme.colorScheme;
        final dark = theme.brightness == Brightness.dark;
        final (accent, icon) = switch (level) {
          NoticeLevel.success => (
            dark ? const Color(0xFF63D8A2) : const Color(0xFF137B4D),
            Icons.check_circle_rounded,
          ),
          NoticeLevel.warning => (
            dark ? const Color(0xFFF4C56A) : const Color(0xFF99610C),
            Icons.warning_amber_rounded,
          ),
          NoticeLevel.error => (scheme.error, Icons.error_outline_rounded),
          NoticeLevel.info => (scheme.primary, Icons.info_outline_rounded),
        };
        final availableWidth = MediaQuery.sizeOf(overlayContext).width;
        return Positioned(
          top: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Material(
                elevation: 12,
                borderRadius: BorderRadius.circular(14),
                color: scheme.surfaceContainerHigh,
                child: Semantics(
                  liveRegion: true,
                  child: Container(
                    width: math.min(380.0, math.max(0.0, availableWidth - 32)),
                    decoration: BoxDecoration(
                      border: Border.all(color: accent.withValues(alpha: 0.55)),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, color: accent, size: 23),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (message != null && message.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  message,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                              if (actionLabel != null && onAction != null) ...[
                                const SizedBox(height: 7),
                                TextButton(
                                  onPressed: () {
                                    _dismiss();
                                    onAction();
                                  },
                                  child: Text(actionLabel),
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: overlayContext.l10n.dismissNotification,
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: _dismiss,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    _active = entry;
    overlay.insert(entry);
    _dismissTimer = Timer(duration, () {
      if (identical(_active, entry)) {
        _dismiss();
      }
    });
  }

  static void _dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _active?.remove();
    _active?.dispose();
    _active = null;
  }
}
