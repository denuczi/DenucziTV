import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';
import 'player_playback_failure_view.dart';

@immutable
class PlayerVideoStatus {
  const PlayerVideoStatus({
    this.opening = false,
    this.retryCountdownSeconds,
    this.completed = false,
    this.failure,
    this.accessBlocked = false,
    this.sourceUnavailable = false,
  });

  final bool opening;
  final int? retryCountdownSeconds;
  final bool completed;
  final String? failure;
  final bool accessBlocked;
  final bool sourceUnavailable;
}

/// Video controls are also mounted on media_kit's separate fullscreen route.
/// A shared listenable keeps status messages visible on either route.
class PlayerVideoOverlay extends StatelessWidget {
  const PlayerVideoOverlay({
    super.key,
    required this.status,
    required this.controls,
    required this.onRetry,
    required this.onClose,
    required this.onExploreCatalog,
  });

  final ValueListenable<PlayerVideoStatus> status;
  final Widget controls;
  final VoidCallback onRetry;
  final VoidCallback onClose;
  final VoidCallback onExploreCatalog;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<PlayerVideoStatus>(
        valueListenable: status,
        child: controls,
        builder: (context, value, controls) => Stack(
          fit: StackFit.expand,
          children: [
            // Hide native buffering controls beneath an error. Otherwise the
            // player can show a spinner and a failure message simultaneously.
            if (value.accessBlocked || value.failure != null)
              const ColoredBox(color: Colors.black)
            else
              controls!,
            if (value.opening && value.failure == null)
              const IgnorePointer(
                child: Center(child: CircularProgressIndicator()),
              ),
            if (value.completed && value.failure == null)
              IgnorePointer(
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        context.l10n.endEpisodeList,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            if (value.failure != null)
              PlayerPlaybackFailureView(
                failure: value.failure!,
                retryCountdownSeconds: value.retryCountdownSeconds,
                accessBlocked: value.accessBlocked,
                sourceUnavailable: value.sourceUnavailable,
                onRetry: onRetry,
                onClose: onClose,
                onExploreCatalog: onExploreCatalog,
              ),
          ],
        ),
      );
}
