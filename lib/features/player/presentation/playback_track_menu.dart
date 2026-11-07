import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';

import 'package:media_kit/media_kit.dart';

import '../../../shared/notifications/app_notice.dart';

/// A native-track selector. Available tracks come from the actual media stream,
/// not from guessed language or quality metadata in the Xtream catalog.
class PlaybackTrackMenu extends StatelessWidget {
  const PlaybackTrackMenu({super.key, required this.player});

  final Player player;

  static String trackLabel(String id, String? title, String? language) {
    final parts = <String>[
      if (language != null && language.trim().isNotEmpty) language.trim(),
      if (title != null && title.trim().isNotEmpty) title.trim(),
    ];
    return parts.isEmpty ? 'Track $id' : parts.join(' · ');
  }

  Future<void> _loadSubtitleFile(BuildContext context) async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          XTypeGroup(
            label: context.l10n.subtitles,
            extensions: ['srt', 'vtt', 'ass', 'ssa'],
          ),
        ],
      );
      if (file == null) {
        return;
      }
      await player.setSubtitleTrack(
        SubtitleTrack.uri(Uri.file(file.path).toString()),
      );
    } catch (_) {
      if (context.mounted) {
        AppNotice.show(
          context,
          level: NoticeLevel.error,
          title: context.l10n.subtitleUnavailable,
          message: context.l10n.subtitleFileFailed,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Tracks>(
      stream: player.stream.tracks,
      initialData: player.state.tracks,
      builder: (context, snapshot) {
        final tracks = snapshot.data ?? const Tracks();
        final audioTracks = tracks.audio
            .where((t) => t.id != 'auto' && t.id != 'no')
            .toList();
        final subtitleTracks = tracks.subtitle
            .where((t) => t.id != 'auto' && t.id != 'no')
            .toList();
        final videoTracks = tracks.video
            .where((t) => t.id != 'auto' && t.id != 'no')
            .toList();
        return PopupMenuButton<String>(
          tooltip: context.l10n.audioSubtitlesTracks,
          icon: const Icon(Icons.tune_rounded, color: Colors.white),
          onSelected: (choice) async {
            try {
              if (choice == 'subtitle-file') {
                await _loadSubtitleFile(context);
              } else if (choice == 'audio-auto') {
                await player.setAudioTrack(AudioTrack.auto());
              } else if (choice.startsWith('audio-')) {
                final trackId = choice.substring(6);
                final track = audioTracks
                    .where((item) => item.id == trackId)
                    .firstOrNull;
                if (track != null) {
                  await player.setAudioTrack(track);
                }
              } else if (choice == 'subtitle-off') {
                await player.setSubtitleTrack(SubtitleTrack.no());
              } else if (choice == 'subtitle-auto') {
                await player.setSubtitleTrack(SubtitleTrack.auto());
              } else if (choice.startsWith('subtitle-')) {
                final trackId = choice.substring(9);
                final track = subtitleTracks
                    .where((item) => item.id == trackId)
                    .firstOrNull;
                if (track != null) {
                  await player.setSubtitleTrack(track);
                }
              } else if (choice == 'video-auto') {
                await player.setVideoTrack(VideoTrack.auto());
              } else if (choice.startsWith('video-')) {
                final trackId = choice.substring(6);
                final track = videoTracks
                    .where((item) => item.id == trackId)
                    .firstOrNull;
                if (track != null) {
                  await player.setVideoTrack(track);
                }
              }
            } catch (_) {
              if (context.mounted) {
                AppNotice.show(
                  context,
                  level: NoticeLevel.error,
                  title: context.l10n.trackUnavailable,
                  message: context.l10n.trackSwitchFailed,
                );
              }
            }
          },
          itemBuilder: (_) => <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
              enabled: false,
              child: Text(
                context.l10n.audio,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            PopupMenuItem(
              value: 'audio-auto',
              child: Text(context.l10n.automaticAudio),
            ),
            for (final audio in audioTracks)
              PopupMenuItem(
                value: 'audio-${audio.id}',
                child: Text(trackLabel(audio.id, audio.title, audio.language)),
              ),
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              enabled: false,
              child: Text(
                context.l10n.subtitles,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            PopupMenuItem(value: 'subtitle-off', child: Text(context.l10n.off)),
            PopupMenuItem(
              value: 'subtitle-auto',
              child: Text(context.l10n.automaticSubtitles),
            ),
            for (final subtitle in subtitleTracks)
              PopupMenuItem(
                value: 'subtitle-${subtitle.id}',
                child: Text(
                  trackLabel(subtitle.id, subtitle.title, subtitle.language),
                ),
              ),
            PopupMenuItem(
              value: 'subtitle-file',
              child: Text(context.l10n.loadSubtitleFile),
            ),
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              enabled: false,
              child: Text(
                context.l10n.videoTracks,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            PopupMenuItem(
              value: 'video-auto',
              child: Text(context.l10n.automaticTrack),
            ),
            for (final video in videoTracks)
              PopupMenuItem(
                value: 'video-${video.id}',
                child: Text(trackLabel(video.id, video.title, video.language)),
              ),
          ],
        );
      },
    );
  }
}
