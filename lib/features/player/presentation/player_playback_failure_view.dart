import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';

/// Centered playback feedback shared by windowed and fullscreen video.
/// Keeps long provider messages scrollable without making the actions span
/// the entire player width. Retry scheduling belongs to the player, not here.
class PlayerPlaybackFailureView extends StatelessWidget {
  const PlayerPlaybackFailureView({
    super.key,
    required this.failure,
    required this.retryCountdownSeconds,
    required this.accessBlocked,
    required this.sourceUnavailable,
    required this.onRetry,
    required this.onClose,
    required this.onExploreCatalog,
  });

  final String failure;
  final int? retryCountdownSeconds;
  final bool accessBlocked;
  final bool sourceUnavailable;
  final VoidCallback onRetry;
  final VoidCallback onClose;
  final VoidCallback onExploreCatalog;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxHeight < 340 || constraints.maxWidth < 460;
          final verticalPadding = compact ? 12.0 : 24.0;

          // A minimum viewport height centers short messages; scrolling keeps
          // large text settings and small desktop windows usable.
          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: 20,
              vertical: verticalPadding,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: math.max(
                  0.0,
                  constraints.maxHeight - verticalPadding * 2,
                ),
              ),
              child: Center(
                child: ConstrainedBox(
                  key: const Key('playerFailureContent'),
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.play_disabled_rounded,
                        size: compact ? 32 : 40,
                        color: const Color(0xFFDADADD),
                      ),
                      SizedBox(height: compact ? 8 : 16),
                      Text(
                        l10n.playerPlaybackUnavailableTitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: compact ? 20 : 24,
                          height: 1.18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        failure,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: Color(0xFFB5B5BC),
                        ),
                      ),
                      if (retryCountdownSeconds != null && !accessBlocked) ...[
                        const SizedBox(height: 14),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.autorenew_rounded,
                              size: 16,
                              color: Color(0xFFE0E0E3),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              l10n.playerRetryingIn(retryCountdownSeconds!),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFFE0E0E3),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 22),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          if (!accessBlocked)
                            FilledButton.icon(
                              onPressed: onRetry,
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF111114),
                                minimumSize: const Size(146, 46),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              icon: const Icon(Icons.refresh_rounded, size: 19),
                              label: Text(l10n.retry),
                            ),
                          if (sourceUnavailable)
                            FilledButton(
                              onPressed: onExploreCatalog,
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF111114),
                                minimumSize: const Size(146, 46),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: Text(l10n.exploreCatalog),
                            ),
                          OutlinedButton(
                            onPressed: onClose,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              minimumSize: const Size(146, 46),
                              side: const BorderSide(color: Color(0xFF515158)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(l10n.closePlayer),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
