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
import '../../personal_library/domain/playback_policy.dart';
import '../../library/data/xtream_api.dart';
import '../../library/domain/media_models.dart';
import 'responsive_player_frame.dart';
import 'playback_track_menu.dart';

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
  late final VideoController _video;
  late final AccountCredentials? _credentials;
  late final XtreamApi _api;
  late final NetworkClient _network;
  StreamSubscription<String>? _errors;
  StreamSubscription<Playlist>? _playlistUpdates;
  StreamSubscription<bool>? _completionUpdates;
  StreamSubscription<Duration>? _positionUpdates;
  StreamSubscription<Duration>? _durationUpdates;
  StreamSubscription<bool>? _playingUpdates;
  PersonalLibraryController? _personalLibrary;
  String? _playbackAccountId;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _lastSavedPosition = Duration.zero;
  int? _pendingManualIndex;
  bool _opening = true;
  bool _completed = false;
  String? _failure;
  String _liveFormat = 'm3u8';
  late int _currentIndex;

  bool get _isSeriesQueue => widget.episodeQueue.isNotEmpty;
  List<MediaEntry> get _items =>
      _isSeriesQueue ? widget.episodeQueue : [widget.media];
  MediaEntry get _currentMedia =>
      _items[_currentIndex.clamp(0, _items.length - 1).toInt()];
  bool get _hasNext => _isSeriesQueue && _currentIndex < _items.length - 1;
  bool get _hasPrevious => _isSeriesQueue && _currentIndex > 0;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppController>();
    _credentials = app.credentials;
    _api = app.api;
    _network = app.network;
    _personalLibrary = app.personalLibrary;
    _playbackAccountId = app.activeAccount?.id;
    _currentIndex = _isSeriesQueue
        ? widget.initialIndex.clamp(0, widget.episodeQueue.length - 1).toInt()
        : 0;
    _player = Player();
    _video = VideoController(_player);
    _errors = _player.stream.error.listen((_) {
      if (mounted) {
        setState(() {
          _opening = false;
          _failure = context.l10n.mediaEnginePlaybackFailed;
        });
      }
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
      if (!playing && _position > Duration.zero) {
        _recordProgress(_currentMedia);
      }
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
      _position = Duration.zero;
      _duration = Duration.zero;
      _lastSavedPosition = Duration.zero;
      setState(() {
        _currentIndex = nextIndex;
        _failure = null;
        _completed = false;
      });
    });
    _completionUpdates = _player.stream.completed.listen((completed) {
      if (!mounted) {
        return;
      }
      if (completed && _currentMedia.kind != LibraryKind.live) {
        _recordProgress(_currentMedia, completed: true);
      }
      setState(() => _completed = completed && !_hasNext);
    });
    unawaited(_open());
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

  Future<void> _open() async {
    final credentials = _credentials;
    if (credentials == null) {
      if (mounted) {
        setState(() {
          _opening = false;
          _failure = 'No account is connected.';
        });
      }
      return;
    }
    setState(() {
      _opening = true;
      _completed = false;
      _failure = null;
    });
    try {
      final resumeAt = await _resumePosition();
      if (!mounted) {
        return;
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
      await _player.open(Playlist(items, index: _currentIndex));
      if (resumeAt != null && mounted) {
        try {
          await _player.seek(resumeAt);
        } catch (_) {
          if (mounted) {
            setState(() => _failure = context.l10n.resumeNotSupported);
          }
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _failure = context.l10n.mediaResourceOpenFailed);
      }
    } finally {
      if (mounted) {
        setState(() => _opening = false);
      }
    }
  }

  Future<void> _goTo(int index) async {
    if (index < 0 || index >= _items.length) {
      return;
    }
    _recordProgress(_currentMedia);
    _position = Duration.zero;
    _duration = Duration.zero;
    _lastSavedPosition = Duration.zero;
    _pendingManualIndex = index;
    setState(() {
      _currentIndex = index;
      _completed = false;
      _failure = null;
    });
    try {
      await _player.jump(index);
    } catch (_) {
      if (mounted) {
        setState(() => _failure = context.l10n.episodeSwitchFailed);
      }
    }
  }

  Future<void> _releasePlayer() async {
    try {
      await _errors?.cancel();
      await _playlistUpdates?.cancel();
      await _completionUpdates?.cancel();
      await _positionUpdates?.cancel();
      await _durationUpdates?.cancel();
      await _playingUpdates?.cancel();
    } finally {
      // A subscription cancellation failure must not leak native resources.
      try {
        await _player.dispose();
      } catch (_) {
        // The UI is already disposed. Do not emit a widget error or reveal a
        // provider URL from a native player exception.
      }
    }
  }

  @override
  void dispose() {
    _recordProgress(_currentMedia);
    unawaited(_releasePlayer().catchError((Object _) {}));
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
                onPressed: _hasPrevious ? () => _goTo(_currentIndex - 1) : null,
                icon: const Icon(
                  Icons.skip_previous_rounded,
                  color: Colors.white,
                ),
              ),
              IconButton(
                key: const Key('nextEpisode'),
                tooltip: context.l10n.nextEpisode,
                onPressed: _hasNext ? () => _goTo(_currentIndex + 1) : null,
                icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
              ),
            ],
            if (current.kind == LibraryKind.live)
              PopupMenuButton<String>(
                tooltip: context.l10n.liveStreamFormat,
                onSelected: (value) {
                  _liveFormat = value;
                  unawaited(_open());
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
            PlaybackTrackMenu(player: _player),
            IconButton(
              tooltip: context.l10n.closePlayer,
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: Colors.white),
            ),
          ],
        ),
      ),
      video: Stack(
        fit: StackFit.expand,
        children: [
          Video(controller: _video, fit: BoxFit.contain, fill: Colors.black),
          if (_opening)
            Center(
              child: CircularProgressIndicator(
                color: theme.colorScheme.primary,
              ),
            ),
          if (_completed && _isSeriesQueue)
            Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    context.l10n.endEpisodeList,
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          if (_failure != null)
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _failure!,
                      style: const TextStyle(color: Colors.white),
                    ),
                    TextButton.icon(
                      onPressed: _open,
                      icon: const Icon(Icons.refresh),
                      label: Text(context.l10n.retry),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
