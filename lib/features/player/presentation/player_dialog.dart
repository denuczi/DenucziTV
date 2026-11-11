import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../../../core/models/account.dart';
import '../../../core/models/app_controller.dart';
import '../../../core/network/network_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../personal_library/application/personal_library_controller.dart';
import '../application/playback_retry_controller.dart';
import '../../personal_library/domain/playback_policy.dart';
import '../../library/data/xtream_api.dart';
import '../../library/domain/media_models.dart';
import 'responsive_player_frame.dart';
import 'playback_track_menu.dart';
import 'player_video_overlay.dart';

/// Plays a single channel/movie or a consecutive series episode queue.
/// MediaKit advances to the next queued item at the end of an episode.
class PlayerDialog extends StatefulWidget {
  const PlayerDialog({
    super.key,
    required this.media,
    this.episodeQueue = const [],
    this.initialIndex = 0,
    this.seriesTitle,
  });

  final MediaEntry media;
  final List<MediaEntry> episodeQueue;
  final int initialIndex;
  final String? seriesTitle;

  @override
  State<PlayerDialog> createState() => _PlayerDialogState();
}

class _PlayerDialogState extends State<PlayerDialog> {
  late final Player _player;
  late final AppController _app;
  bool _playbackFailed = false;
  late final VideoController _video;
  late final AccountCredentials? _credentials;
  late final XtreamApi _api;
  late final NetworkClient _network;
  StreamSubscription<String>? _errors;
  StreamSubscription<void>? _accessRevocations;
  bool _sessionRevoked = false;
  bool _sourceUnavailable = false;
  StreamSubscription<Playlist>? _playlistUpdates;
  StreamSubscription<bool>? _completionUpdates;
  StreamSubscription<Duration>? _positionUpdates;
  StreamSubscription<Duration>? _durationUpdates;
  StreamSubscription<bool>? _playingUpdates;
  StreamSubscription<bool>? _bufferingUpdates;
  PersonalLibraryController? _personalLibrary;
  String? _playbackAccountId;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _lastSavedPosition = Duration.zero;
  int? _pendingManualIndex;
  bool _opening = true;
  bool _openInProgress = false;
  bool _retryAfterOpen = false;
  bool _reloadingSource = false;
  bool _playbackHealthy = false;
  int? _retrySeconds;
  late final PlaybackRetryController _retryController;
  bool _nativeDisposed = false;
  bool _completed = false;
  String? _failure;
  final _videoStatus = ValueNotifier(const PlayerVideoStatus(opening: true));
  String _liveFormat = 'm3u8';
  late int _currentIndex;

  bool get _isSeriesQueue => widget.episodeQueue.isNotEmpty;
  List<MediaEntry> get _items =>
      _isSeriesQueue ? widget.episodeQueue : [widget.media];
  MediaEntry get _currentMedia =>
      _items[_currentIndex.clamp(0, _items.length - 1).toInt()];
  bool get _hasNext => _isSeriesQueue && _currentIndex < _items.length - 1;
  bool get _hasPrevious => _isSeriesQueue && _currentIndex > 0;

  // Fullscreen controls live on a separate route and do not rebuild when the
  // underlying dialog calls setState. Publish the same status to both views.
  void _updatePlayerState(VoidCallback update) {
    if (!mounted) return;
    setState(update);
    _videoStatus.value = PlayerVideoStatus(
      opening: _opening,
      retryCountdownSeconds: _retrySeconds,
      completed: _completed && _isSeriesQueue,
      failure: _failure,
      accessBlocked: _sessionRevoked || _sourceUnavailable,
      sourceUnavailable: _sourceUnavailable,
    );
  }

  Future<void> _closeVideo(
    VideoState video, {
    bool exploreCatalog = false,
  }) async {
    if (video.mounted && video.isFullscreen()) {
      await video.exitFullscreen();
    }
    if (!mounted) return;
    if (exploreCatalog) {
      _app.exploreUpdatedCatalog();
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      Navigator.of(context).pop();
    }
  }

  Widget _videoControls(VideoState video) => PlayerVideoOverlay(
    status: _videoStatus,
    controls: AdaptiveVideoControls(video),
    onRetry: () => _retryPlayback(manual: true),
    onClose: () => _closeVideo(video),
    onExploreCatalog: () => _closeVideo(video, exploreCatalog: true),
  );

  @override
  void initState() {
    super.initState();
    final app = context.read<AppController>();
    _app = app;
    _app.addListener(_onAccountChanged);
    _credentials = app.credentials;
    _api = app.api;
    _network = app.network;
    _personalLibrary = app.personalLibrary;
    _playbackAccountId = app.activeAccount?.id;
    _currentIndex = _isSeriesQueue
        ? widget.initialIndex.clamp(0, widget.episodeQueue.length - 1).toInt()
        : 0;
    _retryController = PlaybackRetryController(
      onCountdownChanged: (seconds) {
        if (mounted) {
          _updatePlayerState(() => _retrySeconds = seconds);
        }
      },
      onRetry: _retryPlayback,
    );
    _player = Player();
    _video = VideoController(_player);
    _accessRevocations = _credentials?.accessGrant?.revocations.listen(
      (_) => _revokeSession(),
    );
    _errors = _player.stream.error.listen((message) {
      if (!mounted ||
          _nativeDisposed ||
          _reloadingSource ||
          _sessionRevoked ||
          _sourceUnavailable) {
        return;
      }
      _playbackFailed = true;
      if (_credentials?.protected == true) {
        if (RegExp(r'\b(?:401|403)\b').hasMatch(message) &&
            _playbackAccountId != null) {
          unawaited(
            app.recoverProtectedCredentials(_playbackAccountId!).catchError((
              Object _,
            ) {
              // A failed refresh must not crash the player event listener.
            }),
          );
        }
        if (_credentials!.linkExpired) {
          _revokeSession();
          return;
        }
        if (app.credentials?.sourceScope != _credentials.sourceScope) {
          _stopUnavailable();
          return;
        }
      }
      _showPlaybackFailure(context.l10n.mediaEnginePlaybackFailed);
    });
    _positionUpdates = _player.stream.position.listen((position) {
      _position = position;
      if (_currentMedia.kind != LibraryKind.live &&
          (_position - _lastSavedPosition).inMilliseconds.abs() >= 10000) {
        _lastSavedPosition = _position;
        _recordProgress(_currentMedia);
      }
    });
    _durationUpdates = _player.stream.duration.listen((duration) {
      _duration = duration;
    });
    _playingUpdates = _player.stream.playing.listen((playing) {
      if (playing) {
        _markPlaybackHealthy();
      } else {
        _playbackHealthy = false;
        _retryController.playbackInterrupted();
        if (_position > Duration.zero) {
          _recordProgress(_currentMedia);
        }
      }
    });
    _bufferingUpdates = _player.stream.buffering.listen((buffering) {
      if (!buffering) _markPlaybackHealthy();
    });
    _playlistUpdates = _player.stream.playlist.listen((playlist) {
      if (!mounted || playlist.medias.isEmpty) {
        return;
      }
      final nextIndex = playlist.index.clamp(0, _items.length - 1).toInt();
      if (_currentIndex == nextIndex) {
        return;
      }
      final previous = _currentMedia;
      final manual = _pendingManualIndex == nextIndex;
      _pendingManualIndex = null;
      // The media engine advances automatically when the preceding episode
      // ends. Manual skipping is not treated as completing an episode.
      _recordProgress(previous, completed: !manual);
      _retryController.reset();
      _retryAfterOpen = false;
      _playbackHealthy = false;
      _position = Duration.zero;
      _duration = Duration.zero;
      _lastSavedPosition = Duration.zero;
      _updatePlayerState(() {
        _currentIndex = nextIndex;
        _failure = null;
        _completed = false;
      });
    });
    _completionUpdates = _player.stream.completed.listen((completed) {
      if (!mounted) {
        return;
      }
      if (_sessionRevoked || _sourceUnavailable) return;
      if (completed && _currentMedia.kind != LibraryKind.live) {
        _recordProgress(_currentMedia, completed: true);
      }
      _updatePlayerState(() => _completed = completed && !_hasNext);
    });
    if (widget.media.sourceScope.isNotEmpty && !app.canUseMedia(widget.media)) {
      _stopUnavailable();
    } else {
      unawaited(_open());
    }
  }

  void _showPlaybackFailure(String message) {
    if (!mounted || _sessionRevoked || _sourceUnavailable) return;
    _playbackHealthy = false;
    _updatePlayerState(() {
      _opening = false;
      _failure = message;
    });
    _retryController.reportFailure();
  }

  void _markPlaybackHealthy() {
    if (!mounted ||
        _nativeDisposed ||
        _sessionRevoked ||
        _sourceUnavailable ||
        _reloadingSource ||
        !_player.state.playing ||
        _player.state.buffering ||
        _playbackHealthy) {
      return;
    }
    _playbackHealthy = true;
    _retryAfterOpen = false;
    _playbackFailed = false;
    _retryController.playbackRecovered();
    _updatePlayerState(() {
      _opening = false;
      _failure = null;
    });
  }

  void _retryPlayback({bool manual = false}) {
    if (!mounted ||
        _nativeDisposed ||
        _sessionRevoked ||
        _sourceUnavailable ||
        (!manual && _failure == null)) {
      return;
    }
    if (manual) _retryController.reset();
    // Close any old error UI immediately. Opening the same Player keeps its
    // fullscreen surface and track controls intact across a reconnect.
    _updatePlayerState(() {
      _opening = true;
      _failure = null;
      _completed = false;
    });
    unawaited(_open(retry: true));
  }

  void _onAccountChanged() {
    if (_credentials?.protected != true) return;
    if (_credentials!.linkExpired) {
      _revokeSession();
      return;
    }
    if (_playbackFailed &&
        _app.credentials?.sourceScope != _credentials.sourceScope) {
      _stopUnavailable();
    }
  }

  void _revokeSession() {
    if (_sessionRevoked) {
      unawaited(_stopNativeSession());
      return;
    }
    _sessionRevoked = true;
    _retryAfterOpen = false;
    _retryController.cancelPending();
    _recordProgress(_currentMedia);
    unawaited(_stopNativeSession());
    if (mounted) {
      _updatePlayerState(() {
        _opening = false;
        _failure = context.l10n.protectedExpired;
      });
    }
  }

  void _stopUnavailable() {
    if (_sourceUnavailable) return;
    _sourceUnavailable = true;
    _retryAfterOpen = false;
    _retryController.cancelPending();
    _recordProgress(_currentMedia);
    unawaited(_stopNativeSession());
    if (mounted) {
      _updatePlayerState(() {
        _opening = false;
        _failure = context.l10n.updatedSourceExplanation;
      });
    }
  }

  Future<void> _stopNativeSession() async {
    if (_nativeDisposed) return;
    try {
      await _player.stop();
    } catch (_) {
      // Revocation must fail closed even if the backend cannot unload normally.
      await _disposeNativePlayer();
    }
  }

  Future<void> _disposeNativePlayer() async {
    if (_nativeDisposed) return;
    _nativeDisposed = true;
    try {
      await _player.dispose();
    } catch (_) {
      // Native errors may contain provider URLs; never forward them.
    }
  }

  void _recordProgress(MediaEntry media, {bool completed = false}) {
    final library = _personalLibrary;
    final account = _playbackAccountId;
    if (library == null || account == null || media.kind == LibraryKind.live) {
      return;
    }
    if (!completed && _position <= Duration.zero) {
      return;
    }
    final duration = _duration;
    final finished =
        completed ||
        PlaybackPolicy.isComplete(
          positionMs: _position.inMilliseconds,
          durationMs: duration.inMilliseconds,
        );
    unawaited(
      library
          .saveProgress(
            accountId: account,
            media: media,
            seriesTitle: widget.seriesTitle,
            position: _position,
            duration: duration,
            completed: finished,
          )
          .catchError((Object _) {
            // Database errors are surfaced by the library, never by the native player.
          }),
    );
  }

  Future<Duration?> _resumePosition() async {
    final library = _personalLibrary;
    final accountId = _playbackAccountId;
    if (library == null ||
        accountId == null ||
        _currentMedia.kind == LibraryKind.live) {
      return null;
    }
    try {
      final previous = await library.progressFor(accountId, _currentMedia);
      if (!mounted ||
          previous == null ||
          !PlaybackPolicy.canResume(
            positionMs: previous.positionMs,
            durationMs: previous.durationMs,
            completed: previous.completed,
          )) {
        return null;
      }
      final shouldResume = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.l10n.resumePlaybackQuestion),
          content: Text(
            context.l10n.resumeAt(
              _formatTime(Duration(milliseconds: previous.positionMs)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.l10n.startOver),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(context.l10n.resume),
            ),
          ],
        ),
      );
      if (!mounted) {
        return null;
      }
      if (shouldResume == false) {
        // Starting over must clear the prior completed/hidden state.
        return null;
      }
      return shouldResume == true
          ? Duration(milliseconds: previous.positionMs)
          : null;
    } catch (_) {
      return null;
    }
  }

  String _formatTime(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _open({bool retry = false}) async {
    if (!mounted || _nativeDisposed || _sessionRevoked || _sourceUnavailable) {
      return;
    }
    // A retry can arrive while the previous asynchronous open is still
    // completing. Queue at most one reload instead of racing two opens.
    if (_openInProgress) {
      if (retry) _retryAfterOpen = true;
      return;
    }
    _openInProgress = true;
    try {
      await _performOpen(retry: retry);
    } finally {
      _openInProgress = false;
      if (_retryAfterOpen &&
          mounted &&
          !_nativeDisposed &&
          !_sessionRevoked &&
          !_sourceUnavailable) {
        _retryAfterOpen = false;
        unawaited(_open(retry: true));
      }
    }
  }

  Future<void> _performOpen({required bool retry}) async {
    final initialCredentials = _credentials;
    // Protected credentials can be refreshed after a 401/403. Reuse only the
    // current credentials for the same protected account, never a new source.
    final credentials =
        initialCredentials?.protected == true &&
            _app.credentials?.sourceScope == initialCredentials?.sourceScope
        ? _app.credentials
        : initialCredentials;
    if (initialCredentials?.protected == true) {
      if (initialCredentials!.linkExpired ||
          (credentials?.linkExpired ?? false) ||
          _sessionRevoked) {
        _revokeSession();
        return;
      }
      if (_app.credentials?.sourceScope != initialCredentials.sourceScope) {
        _stopUnavailable();
        return;
      }
    }
    if (credentials == null) {
      if (mounted) {
        _updatePlayerState(() {
          _opening = false;
          _failure = context.l10n.mediaResourceOpenFailed;
        });
      }
      return;
    }
    _playbackHealthy = false;
    _retryController.playbackInterrupted();
    _updatePlayerState(() {
      _opening = true;
      _completed = false;
      _failure = null;
      _playbackFailed = false;
    });
    try {
      // Reopening a stream must not show the resume dialog again. For VOD,
      // retain the position from before the failed connection.
      final resumeAt = retry
          ? (_currentMedia.kind != LibraryKind.live &&
                    _position > Duration.zero &&
                    PlaybackPolicy.canResume(
                      positionMs: _position.inMilliseconds,
                      durationMs: _duration.inMilliseconds,
                      completed: false,
                    )
                ? _position
                : null)
          : await _resumePosition();
      if (!mounted || _nativeDisposed) return;
      if (credentials.protected &&
          _app.credentials?.sourceScope != credentials.sourceScope) {
        _stopUnavailable();
        return;
      }
      if (retry) {
        // A fresh open, rather than play(), is needed to request a new HLS
        // redirect/token when the provider's previous URL has expired.
        _reloadingSource = true;
        try {
          await _player.stop();
        } finally {
          _reloadingSource = false;
        }
        if (!mounted || _nativeDisposed) return;
      }
      final items = _items
          .map((entry) {
            final uri = _api.streamUrl(
              credentials,
              entry,
              liveFormat: _liveFormat,
            );
            return Media(uri.toString(), httpHeaders: _network.mediaHeaders);
          })
          .toList(growable: false);
      await _player.setPlaylistMode(PlaylistMode.none);
      if (!mounted || _nativeDisposed) return;
      if (credentials.linkExpired || _sessionRevoked) {
        _revokeSession();
        return;
      }
      if (credentials.protected &&
          _app.credentials?.sourceScope != credentials.sourceScope) {
        _stopUnavailable();
        return;
      }
      await _player.open(Playlist(items, index: _currentIndex));
      if (!mounted || _nativeDisposed) return;
      if (credentials.linkExpired || _sessionRevoked) {
        _revokeSession();
        return;
      }
      if (credentials.protected &&
          _app.credentials?.sourceScope != credentials.sourceScope) {
        _stopUnavailable();
        return;
      }
      if (resumeAt != null) {
        try {
          await _player.seek(resumeAt);
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              SnackBar(content: Text(context.l10n.resumeNotSupported)),
            );
          }
        }
      }
    } catch (_) {
      if (mounted) {
        if (credentials.linkExpired) {
          _revokeSession();
        } else {
          _playbackFailed = true;
          _showPlaybackFailure(context.l10n.mediaResourceOpenFailed);
          _onAccountChanged();
        }
      }
    } finally {
      if (mounted && !_nativeDisposed) {
        _updatePlayerState(() => _opening = false);
      }
    }
  }

  Future<void> _goTo(int index) async {
    if (_sessionRevoked ||
        _sourceUnavailable ||
        (_credentials?.linkExpired ?? false) ||
        index < 0 ||
        index >= _items.length) {
      return;
    }
    _retryController.reset();
    _retryAfterOpen = false;
    _playbackHealthy = false;
    _recordProgress(_currentMedia);
    _position = Duration.zero;
    _duration = Duration.zero;
    _lastSavedPosition = Duration.zero;
    _pendingManualIndex = index;
    _updatePlayerState(() {
      _currentIndex = index;
      _completed = false;
      _failure = null;
    });
    try {
      await _player.jump(index);
    } catch (_) {
      if (mounted) {
        _showPlaybackFailure(context.l10n.episodeSwitchFailed);
      }
    }
  }

  Future<void> _releasePlayer() async {
    try {
      await _accessRevocations?.cancel();
      await _errors?.cancel();
      await _playlistUpdates?.cancel();
      await _completionUpdates?.cancel();
      await _positionUpdates?.cancel();
      await _durationUpdates?.cancel();
      await _playingUpdates?.cancel();
      await _bufferingUpdates?.cancel();
    } finally {
      // A subscription cancellation failure must not leak native resources.
      try {
        await _disposeNativePlayer();
      } catch (_) {
        // The UI is already disposed. Do not emit a widget error or reveal a
        // provider URL from a native player exception.
      }
    }
  }

  @override
  void dispose() {
    _retryAfterOpen = false;
    _retryController.dispose();
    _app.removeListener(_onAccountChanged);
    _recordProgress(_currentMedia);
    unawaited(_releasePlayer().catchError((Object _) {}));
    _videoStatus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = _currentMedia;
    return ResponsivePlayerFrame(
      header: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 5, 0),
        child: Row(
          children: [
            Icon(
              Icons.play_circle_outline,
              color: theme.colorScheme.primary,
              size: 21,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    current.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  if (_isSeriesQueue)
                    Text(
                      'S${current.seasonNumber ?? '?'} E${current.episodeNumber ?? '?'} · ${_currentIndex + 1} of ${_items.length} · Auto-play on',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppPalette.muted,
                      ),
                    ),
                ],
              ),
            ),
            if (_isSeriesQueue) ...[
              IconButton(
                tooltip: context.l10n.previousEpisode,
                onPressed:
                    _hasPrevious && !_sessionRevoked && !_sourceUnavailable
                    ? () => _goTo(_currentIndex - 1)
                    : null,
                icon: const Icon(
                  Icons.skip_previous_rounded,
                  color: Colors.white,
                ),
              ),
              IconButton(
                key: const Key('nextEpisode'),
                tooltip: context.l10n.nextEpisode,
                onPressed: _hasNext && !_sessionRevoked && !_sourceUnavailable
                    ? () => _goTo(_currentIndex + 1)
                    : null,
                icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
              ),
            ],
            if (current.kind == LibraryKind.live &&
                !_sessionRevoked &&
                !_sourceUnavailable)
              PopupMenuButton<String>(
                tooltip: context.l10n.liveStreamFormat,
                onSelected: (value) {
                  if (_liveFormat == value) return;
                  _liveFormat = value;
                  _retryPlayback(manual: true);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'm3u8', child: Text('HLS (.m3u8)')),
                  PopupMenuItem(value: 'ts', child: Text('MPEG-TS (.ts)')),
                ],
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _liveFormat.toUpperCase(),
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            if (!_sessionRevoked && !_sourceUnavailable)
              PlaybackTrackMenu(player: _player),
            IconButton(
              tooltip: context.l10n.closePlayer,
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: Colors.white),
            ),
          ],
        ),
      ),
      video: Video(
        controller: _video,
        fit: BoxFit.contain,
        fill: Colors.black,
        controls: _videoControls,
      ),
    );
  }
}
