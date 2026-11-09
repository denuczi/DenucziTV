import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';

@immutable
class PlayerVideoStatus {
  const PlayerVideoStatus({
    this.opening = false,
    this.completed = false,
    this.failure,
    this.accessBlocked = false,
    this.sourceUnavailable = false,
  });

  final bool opening;
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
            if (value.accessBlocked)
              const ColoredBox(color: Colors.black)
            else
              controls!,
            if (value.opening)
              const IgnorePointer(
                child: Center(child: CircularProgressIndicator()),
              ),
            if (value.completed)
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
              SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Semantics(
                      liveRegion: true,
                      child: Material(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                value.failure!,
                                style: const TextStyle(color: Colors.white),
                              ),
                              if (value.accessBlocked)
                                TextButton(
                                  onPressed: onClose,
                                  child: Text(context.l10n.closePlayer),
                                ),
                              if (value.sourceUnavailable)
                                TextButton(
                                  onPressed: onExploreCatalog,
                                  child: Text(context.l10n.exploreCatalog),
                                ),
                              if (!value.accessBlocked)
                                TextButton.icon(
                                  onPressed: onRetry,
                                  icon: const Icon(Icons.refresh),
                                  label: Text(context.l10n.retry),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}
