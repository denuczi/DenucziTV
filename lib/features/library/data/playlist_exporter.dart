import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../../../core/models/account.dart';
import '../../../core/storage/safe_file_publisher.dart';
import '../domain/media_models.dart';
import 'xtream_api.dart';

/// Exports a playlist without truncating a previously saved M3U file.
///
/// A unique temporary file is created in the destination directory and
/// flushed before publication. The destination must not already exist.
class PlaylistExporter {
  PlaylistExporter(this._api, {SafeFilePublisher? publisher})
    : _publisher = publisher ?? const SafeFilePublisher();

  final XtreamApi _api;
  final SafeFilePublisher _publisher;

  Future<String?> export({
    required AccountCredentials credentials,
    required List<MediaEntry> entries,
    required List<MediaCategory> categories,
    required LibraryKind kind,
    void Function(int written, int total)? onProgress,
  }) async {
    if (credentials.protected) {
      throw const FormatException(
        'Protected accounts do not allow sharing links or playlists.',
      );
    }
    if (kind == LibraryKind.series) {
      throw const FormatException('Select Live TV or Movies to export M3U.');
    }
    const group = XTypeGroup(label: 'M3U playlists', extensions: ['m3u']);
    final destination = await getSaveLocation(
      suggestedName: kind == LibraryKind.live
          ? 'live_channels.m3u'
          : 'movies.m3u',
      acceptedTypeGroups: [group],
    );
    if (destination == null) {
      return null;
    }
    await exportToPath(
      destination: destination.path,
      credentials: credentials,
      entries: entries,
      categories: categories,
      kind: kind,
      onProgress: onProgress,
    );
    return destination.path;
  }

  /// Exposed separately from the native picker for deterministic file tests.
  Future<void> exportToPath({
    required String destination,
    required AccountCredentials credentials,
    required List<MediaEntry> entries,
    required List<MediaCategory> categories,
    required LibraryKind kind,
    void Function(int written, int total)? onProgress,
  }) async {
    if (credentials.protected) {
      throw const FormatException(
        'Protected accounts do not allow sharing links or playlists.',
      );
    }
    if (kind == LibraryKind.series) {
      throw const FormatException('Select Live TV or Movies to export M3U.');
    }
    final output = File(destination);
    if (await output.exists()) {
      throw const FileSystemException(
        'The selected file already exists. Choose a new filename.',
      );
    }
    final parent = output.parent;
    File? temporary;
    IOSink? writer;
    try {
      // A timestamp is not sufficient as a uniqueness guarantee; the OS must
      // reserve the path for us with exclusive creation.
      for (var attempt = 0; attempt < 20; attempt++) {
        final candidate = File(
          '${output.path}.${DateTime.now().microsecondsSinceEpoch}.$attempt.tmp',
        );
        try {
          temporary = await candidate.create(exclusive: true);
          break;
        } on PathExistsException {
          continue;
        }
      }
      if (temporary == null) {
        throw const FileSystemException(
          'Could not reserve a temporary playlist file',
        );
      }
      if (!await parent.exists()) {
        throw const FileSystemException(
          'Destination directory no longer exists',
        );
      }
      writer = temporary.openWrite();
      final categoriesById = {
        for (final category in categories) category.id: category.name,
      };
      writer.writeln('#EXTM3U');
      onProgress?.call(0, entries.length);
      for (final (index, entry) in entries.indexed) {
        final title = _sanitize(entry.title);
        final category = _sanitize(categoriesById[entry.categoryId] ?? 'Other');
        final image = _sanitize(entry.imageUrl ?? '');
        writer.writeln(
          '#EXTINF:-1 tvg-name="$title" tvg-logo="$image" group-title="$category",$title',
        );
        writer.writeln(_api.streamUrl(credentials, entry));
        if ((index + 1) % 250 == 0) {
          await writer.flush();
          onProgress?.call(index + 1, entries.length);
        }
      }
      await writer.flush();
      final completeWriter = writer;
      writer = null;
      await completeWriter.close();
      await _publisher.publish(temporary, destination);
      temporary = null;
      onProgress?.call(entries.length, entries.length);
    } finally {
      if (writer != null) {
        try {
          await writer.close();
        } on FileSystemException {
          // Preserve the original error while still releasing the sink.
        }
      }
      if (temporary != null) {
        try {
          if (await temporary.exists()) {
            await temporary.delete();
          }
        } on FileSystemException {
          // Do not mask the original export error.
        }
      }
    }
  }

  String _sanitize(String raw) =>
      raw.replaceAll(RegExp(r'[\r\n"]'), ' ').trim();
}
