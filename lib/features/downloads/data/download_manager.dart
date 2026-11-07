import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/models/account.dart';
import '../../../core/network/network_client.dart';
import '../../../core/storage/settings_store.dart';
import '../../../core/storage/safe_file_publisher.dart';
import '../../library/data/xtream_api.dart';
import '../../library/domain/media_models.dart';
import '../domain/download_task.dart';
import 'download_http_client.dart';
import 'http_byte_range.dart';

class _IncompleteTransfer implements Exception {
  const _IncompleteTransfer();
}

class _PendingTransfer {
  const _PendingTransfer(this.id, this.url);
  final String id;
  // Retained in memory only. Xtream URLs can contain account credentials.
  final Uri url;
}

/// Performs bounded, sequential transfers with on-disk backpressure.
///
/// Downloads are written to temporary files and moved into place only when
/// complete. A failed or cancelled transfer never appears as a finished video.
class DownloadManager extends ChangeNotifier {
  DownloadManager(this._network, this._settings, {SafeFilePublisher? publisher})
    : _publisher = publisher ?? const SafeFilePublisher();

  static const maxHistoryItems = 300;
  static const maxQueuedItems = 100;

  final NetworkClient _network;
  final SettingsStore _settings;
  final SafeFilePublisher _publisher;
  final List<DownloadTask> _tasks = [];
  final List<_PendingTransfer> _queue = [];
  final Map<String, CancelToken> _tokens = {};
  final Map<String, Uri> _retrySources = {};
  final Set<String> _reservedDestinations = {};
  final Set<String> _claimingMediaKeys = {};
  final Set<String> _finalizing = {};
  final Set<String> _deletingFiles = {};
  final Set<String> _retryingIds = {};
  bool _running = false;
  bool _disposed = false;
  Future<void> _historyWrites = Future<void>.value();
  int _sequence = 0;
  String? _directory;
  String? _historyError;

  String? get directory => _directory;
  String? get historyError => _historyError;
  bool isFinalizing(String id) => _finalizing.contains(id);
  bool isTransferActive(String id) => _tokens.containsKey(id);
  List<DownloadTask> get tasks => List.unmodifiable(_tasks.reversed);

  /// Uses only an opaque saved-account ID and provider media IDs.
  /// Never put passwords, user names, stream URLs or tokens in this key.
  static String mediaKeyFor(String accountId, MediaEntry media) {
    return '${accountId.length}:$accountId:${media.kind.name}:'
        '${media.id.length}:${media.id}:'
        '${media.seasonNumber ?? ''}:${media.episodeNumber ?? ''}';
  }

  /// Returns the latest active or completed transfer for this media item.
  /// Failed and cancelled attempts do not prevent new downloads.
  DownloadTask? taskForMedia(String accountId, MediaEntry media) {
    final key = mediaKeyFor(accountId, media);
    for (final task in _tasks.reversed) {
      if (task.mediaKey == key &&
          (task.status == DownloadStatus.queued ||
              task.status == DownloadStatus.downloading ||
              task.status == DownloadStatus.completed ||
              _tokens.containsKey(task.id))) {
        return task;
      }
    }
    return null;
  }

  bool get canClearHistory => _tasks.any(
    (task) =>
        _isTerminal(task.status) &&
        !_deletingFiles.contains(task.id) &&
        !_tokens.containsKey(task.id),
  );

  static bool _isTerminal(DownloadStatus status) =>
      status == DownloadStatus.completed ||
      status == DownloadStatus.failed ||
      status == DownloadStatus.cancelled ||
      status == DownloadStatus.interrupted;

  int get activeCount => _tasks
      .where(
        (task) =>
            task.status == DownloadStatus.queued ||
            task.status == DownloadStatus.downloading,
      )
      .length;

  Future<void> initialize() async {
    try {
      _directory = await _settings.readDownloadDirectory();
    } catch (_) {
      _historyError = 'Download folder preference could not be restored.';
    }
    String? raw;
    try {
      raw = await _settings.readDownloadHistory();
    } catch (_) {
      _historyError = 'Download history could not be restored.';
    }
    _tasks.clear();
    if (raw != null) {
      try {
        final records = jsonDecode(raw);
        if (records is! List) {
          throw const FormatException('Invalid download history');
        }
        var skipped = 0;
        for (final record in records.take(maxHistoryItems)) {
          try {
            _tasks.add(
              DownloadTask.fromJson(Map<String, dynamic>.from(record as Map)),
            );
          } catch (_) {
            skipped++;
          }
        }
        if (skipped > 0) {
          _historyError =
              '$skipped invalid download history entries were skipped.';
        }
      } catch (_) {
        // Preserve playback when optional download history is corrupt.
        _historyError = 'Download history could not be read.';
      }
    }
    // The history can lag the actual .part length after a crash. Disk is the
    // authoritative source for retained bytes, not the last UI update.
    for (var index = 0; index < _tasks.length; index++) {
      final task = _tasks[index];
      if (task.status == DownloadStatus.completed) {
        continue;
      }
      final partial = File('${task.destination}.part');
      if (await FileSystemEntity.type(partial.path, followLinks: false) ==
          FileSystemEntityType.file) {
        try {
          final bytes = await partial.length();
          _tasks[index] = task.copyWith(
            bytesReceived: bytes,
            message: bytes > 0
                ? 'Partial file preserved. Open this title in the catalog to resume after restarting.'
                : task.message,
          );
        } on FileSystemException {
          // Leave the persisted status intact if the file cannot be inspected.
        }
      }
    }
    _emit();
  }

  Future<void> setDirectory(String selected) async {
    if (selected.trim().isEmpty) {
      throw const AppException('Choose a download directory.');
    }
    final folder = Directory(selected);
    if (!await folder.exists()) {
      throw const AppException('The selected directory does not exist.');
    }
    try {
      final probe = File(
        _join(
          folder.path,
          '.denuczitv_write_test_${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      await probe.create(exclusive: true);
      await probe.delete();
    } on FileSystemException {
      throw const AppException('The selected directory is not writable.');
    }
    await _settings.writeDownloadDirectory(folder.absolute.path);
    _directory = folder.absolute.path;
    _emit();
  }

  Future<int> enqueue({
    required AccountCredentials credentials,
    required XtreamApi api,
    required Iterable<MediaEntry> media,
    String? subfolder,
    String accountId = 'unscoped',
  }) async {
    final root = _directory;
    if (root == null) {
      throw const AppException(
        'Set a download folder on the Downloads page first.',
      );
    }
    final files = media.toList(growable: false);
    if (files.isEmpty) {
      throw const AppException('No downloadable episodes were provided.');
    }
    if (files.any((entry) => entry.kind == LibraryKind.live)) {
      throw const AppException(
        'Live TV recording is not available in this version.',
      );
    }
    // Claim each content key before the first await. This is an atomic section
    // on Dart's event loop and protects concurrent calls from different widgets.
    final claimed = <String>{};
    final unique = <MediaEntry>[];
    for (final entry in files) {
      final key = mediaKeyFor(accountId, entry);
      if (_claimingMediaKeys.contains(key) ||
          taskForMedia(accountId, entry) != null ||
          !claimed.add(key)) {
        continue;
      }
      unique.add(entry);
    }
    if (unique.isEmpty) {
      return 0;
    }
    if (unique.length + activeCount + _claimingMediaKeys.length >
        maxQueuedItems) {
      throw const AppException(
        'Too many pending downloads. Wait for the current queue to finish.',
      );
    }
    // Never evict an unfinished history entry with retained partial bytes.
    // Require the user to clear old entries rather than orphaning .part files.
    final evictable = _tasks
        .where((task) => task.status == DownloadStatus.completed)
        .length;
    final newRecords = unique
        .where(
          (entry) => !_tasks.any(
            (task) =>
                task.mediaKey == mediaKeyFor(accountId, entry) &&
                (task.status == DownloadStatus.failed ||
                    task.status == DownloadStatus.cancelled ||
                    task.status == DownloadStatus.interrupted),
          ),
        )
        .length;
    if (_tasks.length + newRecords - evictable > maxHistoryItems) {
      throw const AppException(
        'Download history is full. Clear old entries before adding more.',
      );
    }
    _claimingMediaKeys.addAll(claimed);
    try {
      return await _enqueueClaimed(
        root: root,
        credentials: credentials,
        api: api,
        files: unique,
        accountId: accountId,
        subfolder: subfolder,
      );
    } finally {
      _claimingMediaKeys.removeAll(claimed);
    }
  }

  Future<int> _enqueueClaimed({
    required String root,
    required AccountCredentials credentials,
    required XtreamApi api,
    required List<MediaEntry> files,
    required String accountId,
    String? subfolder,
  }) async {
    // Resolve all URLs before mutating queue state, so malformed provider
    // metadata never leaves a partially queued season.
    final sourceUrls = <Uri>[];
    const supportedVideoExtensions = {
      'mp4',
      'mkv',
      'ts',
      'avi',
      'mov',
      'webm',
      'm4v',
      'mpeg',
      'mpg',
      'flv',
    };
    for (final file in files) {
      final extension = file.playbackExtension().toLowerCase();
      if (extension == 'm3u8') {
        throw const AppException(
          'HLS downloads are not supported yet. A direct video stream is required.',
        );
      }
      if (!supportedVideoExtensions.contains(extension)) {
        throw const AppException(
          'The provider returned an unsupported video file extension.',
        );
      }
      sourceUrls.add(api.streamUrl(credentials, file));
    }
    final destinationFolder = subfolder == null
        ? root
        : _join(root, safeFileName(subfolder));
    try {
      await Directory(destinationFolder).create(recursive: true);
    } on FileSystemException {
      throw const AppException(
        'Unable to create the selected download directory.',
      );
    }
    // Reserve every destination before inserting tasks. A failed reservation
    // cannot leave a half-enqueued season with missing episodes.
    final staged = <({DownloadTask task, Uri source, bool reuse})>[];
    try {
      for (final (index, entry) in files.indexed) {
        // Reconnect an interrupted history entry when the user selects the
        // same media from the catalog after restarting the application.
        DownloadTask? reusable;
        final mediaKey = mediaKeyFor(accountId, entry);
        for (final old in _tasks.reversed) {
          if (!_deletingFiles.contains(old.id) &&
              old.mediaKey == mediaKey &&
              (old.status == DownloadStatus.failed ||
                  old.status == DownloadStatus.cancelled ||
                  old.status == DownloadStatus.interrupted) &&
              !await File(old.destination).exists() &&
              await FileSystemEntity.type(
                    '${old.destination}.part',
                    followLinks: false,
                  ) ==
                  FileSystemEntityType.file) {
            reusable = old;
            break;
          }
        }
        if (reusable != null) {
          final destination = _normalize(reusable.destination);
          if (!_reservedDestinations.add(destination)) {
            continue;
          }
          staged.add((
            task: reusable.copyWith(
              status: DownloadStatus.queued,
              bytesReceived: await File('${reusable.destination}.part')
                  .length(),
              message: 'Resuming saved partial transfer...',
            ),
            source: sourceUrls[index],
            reuse: true,
          ));
          continue;
        }
        final extension = entry.playbackExtension().toLowerCase();
        final title = safeFileName(entry.title);
        final episode = entry.episodeNumber == null
            ? ''
            : 'S${(entry.seasonNumber ?? 0).toString().padLeft(2, '0')}'
                  'E${entry.episodeNumber!.toString().padLeft(2, '0')} - ';
        final target = await _uniqueFileName(
          destinationFolder,
          '$episode$title',
          extension,
        );
        final id = '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
        staged.add((
          task: DownloadTask(
            id: id,
            title: entry.title,
            destination: target,
            status: DownloadStatus.queued,
            mediaKey: mediaKeyFor(accountId, entry),
          ),
          source: sourceUrls[index],
          reuse: false,
        ));
      }
    } catch (_) {
      for (final item in staged) {
        _reservedDestinations.remove(_normalize(item.task.destination));
      }
      rethrow;
    }
    for (final item in staged) {
      if (item.reuse) {
        final index = _tasks.indexWhere((task) => task.id == item.task.id);
        if (index < 0) {
          continue;
        }
        _tasks[index] = item.task;
      } else {
        _tasks.add(item.task);
      }
      _retrySources[item.task.id] = item.source;
      _queue.add(_PendingTransfer(item.task.id, item.source));
    }
    _pruneHistory();
    _emit();
    unawaited(_saveHistory());
    unawaited(_drain());
    return staged.length;
  }

  static String safeFileName(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F\x7F]'), ' ')
        .replaceAll(RegExp(r'[\u202A-\u202E\u2066-\u2069]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[. ]+|[. ]+$'), '')
        .trim();
    final truncated = String.fromCharCodes(cleaned.runes.take(100)).trimRight();
    final reserved = RegExp(
      r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$',
      caseSensitive: false,
    );
    return truncated.isEmpty || reserved.hasMatch(truncated)
        ? 'Untitled media'
        : truncated;
  }

  static String _join(String parent, String child) =>
      '$parent${Platform.pathSeparator}$child';

  String _normalize(String path) =>
      Platform.isWindows ? path.toLowerCase() : path;

  void _pruneHistory() {
    while (_tasks.length > maxHistoryItems) {
      // Retain records backed by partial video data until the user chooses to
      // remove them. Otherwise a trim could orphan gigabytes on disk.
      final index = _tasks.indexWhere(
        (task) =>
            !_tokens.containsKey(task.id) &&
            task.status == DownloadStatus.completed,
      );
      if (index < 0) {
        return;
      }
      final removed = _tasks.removeAt(index);
      _retrySources.remove(removed.id);
      _reservedDestinations.remove(_normalize(removed.destination));
    }
  }

  Future<String> _uniqueFileName(
    String folder,
    String base,
    String extension,
  ) async {
    for (var index = 0; index < 10000; index++) {
      final suffix = index == 0 ? '' : ' ($index)';
      final candidate = _join(folder, '$base$suffix.$extension');
      if (!await File(candidate).exists() &&
          !await File('$candidate.part').exists()) {
        // Include queued destinations, which do not yet exist on disk.
        final normalized = _normalize(candidate);
        if (_reservedDestinations.add(normalized)) {
          return candidate;
        }
      }
    }
    throw const AppException('Unable to choose a unique filename.');
  }

  void cancel(String id) {
    if (_finalizing.contains(id)) {
      return; // Publication is already committed to its final destination.
    }
    final matching = _tasks.where((task) => task.id == id);
    if (matching.isEmpty ||
        (matching.first.status != DownloadStatus.queued &&
            matching.first.status != DownloadStatus.downloading)) {
      return;
    }
    _queue.removeWhere((pending) => pending.id == id);
    _tokens[id]?.cancel('Cancelled by the user');
    _set(id, status: DownloadStatus.cancelled, message: 'Cancelled');
    unawaited(_saveHistory());
  }

  /// Removes a terminal record and its partial data, never a finished video.
  Future<void> removeFromHistory(String id) async {
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index == -1) {
      return;
    }
    if (!_isTerminal(_tasks[index].status) ||
        _deletingFiles.contains(id) ||
        _tokens.containsKey(id)) {
      throw const AppException(
        'Wait until the transfer has stopped before removing its history.',
      );
    }
    if (!_deletingFiles.add(id)) {
      throw const AppException('This entry is already being removed.');
    }
    _emit();
    try {
      final removed = _tasks[index];
      await _deletePartial(removed);
      _tasks.removeWhere((entry) => entry.id == id);
      _retrySources.remove(id);
      _reservedDestinations.remove(_normalize(removed.destination));
      _emit();
      await _saveHistory();
    } finally {
      _deletingFiles.remove(id);
      _emit();
    }
  }

  /// Clears finished/failed history but never deletes downloaded media.
  /// Transfers that are active or being deleted remain visible.
  Future<int> clearHistory() async {
    final removed = _tasks
        .where(
          (task) =>
              _isTerminal(task.status) &&
              !_deletingFiles.contains(task.id) &&
              !_tokens.containsKey(task.id),
        )
        .toList();
    if (removed.isEmpty) {
      return 0;
    }
    final ids = removed.map((task) => task.id).toSet();
    _deletingFiles.addAll(ids);
    var cleared = 0;
    try {
      for (final task in removed) {
        try {
          await _deletePartial(task);
        } on AppException {
          // Preserve this record so the user can retry the cleanup.
          continue;
        }
        _tasks.removeWhere((entry) => entry.id == task.id);
        _retrySources.remove(task.id);
        _reservedDestinations.remove(_normalize(task.destination));
        cleared++;
      }
      _emit();
      await _saveHistory();
      return cleared;
    } finally {
      _deletingFiles.removeAll(ids);
      _emit();
    }
  }

  /// Only history removal discards a failed transfer's .part file. Never
  /// follow symlinks and never delete an actual completed video here.
  Future<void> _deletePartial(DownloadTask task) async {
    final partial = File('${task.destination}.part');
    final type = await FileSystemEntity.type(partial.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return;
    }
    if (type != FileSystemEntityType.file) {
      throw const AppException(
        'The partial download path is not a regular file. History was preserved.',
      );
    }
    try {
      await partial.delete();
    } on FileSystemException {
      throw const AppException(
        'Unable to remove the partial download. Check folder permissions.',
      );
    }
  }

  /// Deletes exactly the completed file chosen by the user, then its record.
  /// A symlink or directory is never followed or deleted via this operation.
  Future<void> deleteDownloadedFile(String id) async {
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index == -1 || _tasks[index].status != DownloadStatus.completed) {
      throw const AppException('Only completed downloads can be deleted.');
    }
    if (!_deletingFiles.add(id)) {
      throw const AppException('This file is already being removed.');
    }
    _emit();
    try {
      final destination = _tasks[index].destination;
      final type = await FileSystemEntity.type(destination, followLinks: false);
      if (type != FileSystemEntityType.file) {
        throw const AppException(
          'The download file is missing or has been replaced. Remove its history entry instead.',
        );
      }
      try {
        await File(destination).delete();
      } on FileSystemException {
        throw const AppException(
          'Could not delete the file. Verify permissions and close applications using it.',
        );
      }
      final currentIndex = _tasks.indexWhere((task) => task.id == id);
      if (currentIndex != -1) {
        _tasks.removeAt(currentIndex);
      }
      _retrySources.remove(id);
      _reservedDestinations.remove(_normalize(destination));
      _emit();
      await _saveHistory();
    } finally {
      _deletingFiles.remove(id);
      _emit();
    }
  }

  Future<void> retry(String id) async {
    if (!_retryingIds.add(id)) {
      return;
    }
    try {
      final index = _tasks.indexWhere((task) => task.id == id);
      final source = _retrySources[id];
      if (index < 0 ||
          source == null ||
          _disposed ||
          _tokens.containsKey(id) ||
          _deletingFiles.contains(id)) {
        return;
      }
      final original = _tasks[index];
      if (original.status != DownloadStatus.failed &&
          original.status != DownloadStatus.cancelled &&
          original.status != DownloadStatus.interrupted) {
        return;
      }
      final originalFile = File(original.destination);
      if (await originalFile.exists()) {
        // A different application may have taken the destination. Preserve
        // the .part file and require the user to resolve the collision.
        _set(
          id,
          status: DownloadStatus.failed,
          message: 'The destination now exists. The partial file was kept.',
        );
        return;
      }
      final normalized = _normalize(original.destination);
      if (!_reservedDestinations.add(normalized)) {
        return;
      }
      final partial = File('${original.destination}.part');
      final type = await FileSystemEntity.type(
        partial.path,
        followLinks: false,
      );
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.file) {
        _reservedDestinations.remove(normalized);
        _set(
          id,
          status: DownloadStatus.failed,
          message: 'Unsafe partial download path. No file was modified.',
        );
        return;
      }
      final bytes = type == FileSystemEntityType.file
          ? await partial.length()
          : 0;
      if (_disposed ||
          _tokens.containsKey(id) ||
          _tasks[index].status != original.status) {
        _reservedDestinations.remove(normalized);
        return;
      }
      _tasks[index] = original.copyWith(
        status: DownloadStatus.queued,
        bytesReceived: bytes,
        totalBytes: bytes == 0 ? null : original.totalBytes,
        etag: bytes == 0 ? null : original.etag,
        lastModified: bytes == 0 ? null : original.lastModified,
        message: bytes > 0 ? 'Resuming saved download...' : null,
      );
      _queue.add(_PendingTransfer(id, source));
      _emit();
      unawaited(_saveHistory());
      unawaited(_drain());
    } on FileSystemException {
      _set(
        id,
        status: DownloadStatus.failed,
        message: 'Could not read the saved partial file. Check permissions.',
      );
    } finally {
      _retryingIds.remove(id);
    }
  }

  bool canRetry(String id) =>
      _retrySources.containsKey(id) && !_tokens.containsKey(id);

  Future<void> _drain() async {
    if (_running || _disposed) {
      return;
    }
    _running = true;
    try {
      while (_queue.isNotEmpty && !_disposed) {
        final next = _queue.removeAt(0);
        final task = _tasks.firstWhere((entry) => entry.id == next.id);
        if (task.status != DownloadStatus.queued) {
          continue;
        }
        try {
          await _transfer(next);
        } catch (_) {
          // A single unexpected transfer failure must not stall the queue.
          _set(
            next.id,
            status: DownloadStatus.failed,
            message: 'An unexpected file transfer error occurred.',
          );
        } finally {
          _tokens.remove(next.id);
          _emit();
          await _saveHistory();
        }
      }
    } finally {
      _running = false;
    }
  }

  /// Download a direct media file while retaining successfully written bytes
  /// across network errors, user cancellation and automatic retry attempts.
  Future<void> _transfer(_PendingTransfer pending) async {
    final id = pending.id;
    final initialTask = _tasks.firstWhere((entry) => entry.id == id);
    final target = initialTask.destination;
    final partial = File('$target.part');
    final token = CancelToken();
    _tokens[id] = token;
    Object? lastError;
    _set(id, status: DownloadStatus.downloading, message: null);

    for (var attempt = 0; attempt < 3 && !token.isCancelled; attempt++) {
      RandomAccessFile? output;
      try {
        if (attempt > 0) {
          _set(id, message: 'Reconnecting to resume saved bytes...');
          await Future<void>.delayed(Duration(seconds: attempt * 2));
        }
        if (token.isCancelled) {
          break;
        }
        if (await File(target).exists()) {
          throw const AppException('The destination file already exists.');
        }
        final type = await FileSystemEntity.type(
          partial.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.notFound) {
          await partial.create(exclusive: true);
        } else if (type != FileSystemEntityType.file) {
          throw const AppException(
            'The partial download path is not a regular file.',
          );
        }
        final offset = await partial.length();
        final saved = _tasks.firstWhere((task) => task.id == id);
        if (saved.totalBytes != null && offset > saved.totalBytes!) {
          throw const AppException(
            'The saved partial exceeds the expected media size.',
          );
        }
        final bool allowDowngrade;
        try {
          allowDowngrade = await _settings.readAllowInsecureDownloadRedirects();
        } catch (_) {
          throw const AppException(
            'Unable to read the download redirect setting.',
          );
        }
        final client = DownloadHttpClient(_network);
        final validator = saved.etag != null && !saved.etag!.startsWith('W/')
            ? saved.etag
            : saved.lastModified;
        if (offset > 0 && validator == null) {
          await _verifyPrefix(
            client,
            pending.url,
            partial,
            offset,
            token,
            allowDowngrade,
            saved.totalBytes,
          );
        }
        final response = await client.open(
          pending.url,
          cancelToken: token,
          allowHttpsToHttpRedirect: allowDowngrade,
          startByte: offset,
          ifRange: offset > 0 ? validator : null,
        );
        final body = response.data;
        if (body == null) {
          throw const AppException('The provider returned an empty response.');
        }
        if (offset > 0 && response.statusCode == 200) {
          await body.stream.listen(null).cancel();
          throw const AppException(
            'The provider cannot safely resume this download. '
            'The previously downloaded bytes were kept.',
          );
        }
        final HttpByteRange? byteRange;
        if (offset > 0) {
          if (response.statusCode != 206) {
            throw const AppException('The provider did not support resuming.');
          }
          byteRange = HttpByteRange.parse(
            response.headers.value('content-range'),
            requestedStart: offset,
          );
          if (saved.totalBytes != null && saved.totalBytes != byteRange.total) {
            throw const AppException(
              'The media size changed since the download started. Partial data was kept.',
            );
          }
          final returnedTag = response.headers.value('etag');
          if (saved.etag != null &&
              returnedTag != null &&
              saved.etag != returnedTag) {
            throw const AppException(
              'The remote media changed. Partial data was kept.',
            );
          }
        } else {
          if (response.statusCode != 200) {
            throw const AppException(
              'Unexpected partial response from the provider.',
            );
          }
          byteRange = null;
        }
        final mime =
            response.headers.value(Headers.contentTypeHeader)?.toLowerCase() ??
            '';
        if (mime.contains('mpegurl') ||
            mime.contains('text/html') ||
            mime.contains('application/json')) {
          throw const AppException(
            'The provider returned a playlist or an error page.',
          );
        }
        final chunkLength = int.tryParse(
          response.headers.value(Headers.contentLengthHeader) ?? '',
        );
        if (chunkLength != null && chunkLength < 0) {
          throw const AppException('The server reported an invalid file size.');
        }
        if (byteRange != null &&
            chunkLength != null &&
            chunkLength != byteRange.length) {
          throw const AppException(
            'The server returned an inconsistent byte range.',
          );
        }
        final total = byteRange?.total ?? chunkLength;
        final tag = response.headers.value('etag');
        final modified = response.headers.value('last-modified');
        _set(
          id,
          bytes: offset,
          total: total,
          etag: tag ?? saved.etag,
          lastModified: modified ?? saved.lastModified,
        );
        unawaited(_saveHistory());
        output = await partial.open(
          mode: offset == 0 ? FileMode.writeOnly : FileMode.append,
        );
        var received = offset;
        var chunkReceived = 0;
        var lastUpdate = DateTime.now().subtract(const Duration(seconds: 1));
        var lastPersist = DateTime.now();
        final sniffBuffer = <int>[];
        await for (final bytes in body.stream) {
          if (token.isCancelled) {
            throw const AppException(
              'Download cancelled. Partial data was kept.',
            );
          }
          if (offset == 0 && sniffBuffer.length < 256) {
            sniffBuffer.addAll(bytes.take(256 - sniffBuffer.length));
            final sample = utf8
                .decode(sniffBuffer, allowMalformed: true)
                .trimLeft()
                .toLowerCase();
            if (sample.startsWith('#extm3u') ||
                sample.startsWith('<!doctype') ||
                sample.startsWith('<html') ||
                sample.startsWith('{"')) {
              throw const AppException(
                'The provider did not return a direct video file.',
              );
            }
          }
          if (total != null && received + bytes.length > total) {
            throw const AppException(
              'The server sent more bytes than the declared media size.',
            );
          }
          await output.writeFrom(bytes);
          received += bytes.length;
          chunkReceived += bytes.length;
          final now = DateTime.now();
          if (now.difference(lastUpdate).inMilliseconds >= 200) {
            _set(id, bytes: received, total: total);
            lastUpdate = now;
          }
          if (now.difference(lastPersist).inSeconds >= 3) {
            unawaited(_saveHistory());
            lastPersist = now;
          }
        }
        await output.flush();
        await output.close();
        output = null;
        _set(id, bytes: received, total: total);
        if (received == 0 ||
            (chunkLength != null && chunkReceived != chunkLength) ||
            (byteRange != null && chunkReceived != byteRange.length) ||
            (total != null && received != total)) {
          throw const _IncompleteTransfer();
        }
        if (token.isCancelled) {
          throw const AppException(
            'Download cancelled. Partial data was kept.',
          );
        }
        _finalizing.add(id);
        _set(id, message: 'Finalizing download...');
        try {
          await _publisher.publish(partial, target);
        } on PathExistsException {
          throw const AppException(
            'Another application created the destination.',
          );
        } finally {
          _finalizing.remove(id);
        }
        _set(
          id,
          status: DownloadStatus.completed,
          bytes: received,
          total: total ?? received,
          message: 'Saved successfully',
        );
        _tokens.remove(id);
        _retrySources.remove(id);
        return;
      } on DioException catch (error) {
        lastError = error;
        if (CancelToken.isCancel(error) || !_retryable(error)) {
          break;
        }
      } on _IncompleteTransfer {
        lastError = const AppException('The server ended the transfer early.');
      } on SocketException {
        lastError = const AppException(
          'The network connection was interrupted.',
        );
      } on HttpException {
        lastError = const AppException(
          'The server interrupted the connection.',
        );
      } on TimeoutException {
        lastError = const AppException('The download timed out.');
      } on FileSystemException {
        lastError = const AppException(
          'Cannot access the partial file. Check disk space and folder permissions.',
        );
        break;
      } on AppException catch (error) {
        lastError = error;
        break;
      } catch (_) {
        lastError = const AppException('The download failed unexpectedly.');
        break;
      } finally {
        if (output != null) {
          try {
            await output.close();
          } on FileSystemException {
            /* Preserve the original error. */
          }
        }
        // Do not delete .part here. It belongs to this history record until
        // final publication succeeds or the user removes the record.
        try {
          if (await FileSystemEntity.type(partial.path, followLinks: false) ==
              FileSystemEntityType.file) {
            _set(id, bytes: await partial.length());
          }
        } on FileSystemException {
          // The task remains failed; do not mask the transfer error.
        }
      }
    }
    if (token.isCancelled) {
      _set(
        id,
        status: DownloadStatus.cancelled,
        message: 'Cancelled. The downloaded portion has been kept.',
      );
    } else {
      _set(
        id,
        status: DownloadStatus.failed,
        message: _friendlyError(lastError),
      );
    }
    _tokens.remove(id);
  }

  /// Compare bounded sections of the remote file with saved bytes when the
  /// provider supplies neither a strong ETag nor a Last-Modified validator.
  /// This prevents common accidental corruption; it is not a full checksum.
  Future<void> _verifyPrefix(
    DownloadHttpClient client,
    Uri uri,
    File partial,
    int offset,
    CancelToken token,
    bool allowDowngrade,
    int? totalBytes,
  ) async {
    final prefix = offset < 65536 ? offset : 65536;
    await _verifySavedRange(
      client,
      uri,
      partial,
      0,
      prefix,
      token,
      allowDowngrade,
      totalBytes,
    );
    if (offset > prefix) {
      final suffix = offset - prefix;
      await _verifySavedRange(
        client,
        uri,
        partial,
        suffix,
        prefix,
        token,
        allowDowngrade,
        totalBytes,
      );
    }
  }

  /// Never request more than 64 KiB for an integrity probe.
  Future<void> _verifySavedRange(
    DownloadHttpClient client,
    Uri uri,
    File partial,
    int start,
    int count,
    CancelToken token,
    bool allowDowngrade,
    int? totalBytes,
  ) async {
    final response = await client.open(
      uri,
      cancelToken: token,
      allowHttpsToHttpRedirect: allowDowngrade,
      startByte: start,
      endByte: start + count - 1,
    );
    final body = response.data;
    if (response.statusCode != 206 || body == null) {
      if (body != null) {
        await body.stream.listen(null).cancel();
      }
      throw const AppException(
        'This server does not support safe download resumption. Partial data was kept.',
      );
    }
    final range = HttpByteRange.parse(
      response.headers.value('content-range'),
      requestedStart: start,
    );
    if (range.length != count ||
        (totalBytes != null && totalBytes != range.total)) {
      throw const AppException(
        'The remote media does not match the saved partial.',
      );
    }
    final local = await partial
        .openRead(start, start + count)
        .expand((bytes) => bytes)
        .toList();
    var cursor = 0;
    await for (final chunk in body.stream) {
      for (final value in chunk) {
        if (cursor >= local.length || value != local[cursor]) {
          throw const AppException(
            'The remote media changed. Partial data was kept.',
          );
        }
        cursor++;
      }
    }
    if (cursor != count) {
      throw const _IncompleteTransfer();
    }
  }

  bool _retryable(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError ||
        (error.type == DioExceptionType.unknown &&
            (error.error is SocketException || error.error is HttpException))) {
      return true;
    }
    final status = error.response?.statusCode;
    return status == 408 || status == 429 || (status != null && status >= 500);
  }

  String _friendlyError(Object? error) {
    if (error is AppException) {
      return error.message;
    }
    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      return switch (statusCode) {
        401 || 403 =>
          'The provider refused access. Verify the account and subscription.',
        404 => 'The media file is no longer available.',
        416 => 'The provider rejected the requested byte range.',
        _ => 'Network error. Check the connection and try again.',
      };
    }
    return 'The download could not be completed.';
  }

  static const Object _keep = Object();

  void _set(
    String id, {
    DownloadStatus? status,
    int? bytes,
    Object? total = _keep,
    Object? message = _keep,
    Object? etag = _keep,
    Object? lastModified = _keep,
  }) {
    final index = _tasks.indexWhere((entry) => entry.id == id);
    if (index < 0) {
      return;
    }
    final old = _tasks[index];
    // A cancelled operation cannot become completed when its network request
    // races the cancellation notification.
    if (old.status == DownloadStatus.cancelled &&
        status != null &&
        status != DownloadStatus.queued) {
      return;
    }
    _tasks[index] = old.copyWith(
      status: status,
      bytesReceived: bytes,
      totalBytes: identical(total, _keep) ? old.totalBytes : total,
      message: identical(message, _keep) ? old.message : message,
      etag: identical(etag, _keep) ? old.etag : etag,
      lastModified: identical(lastModified, _keep)
          ? old.lastModified
          : lastModified,
    );
    if (status == DownloadStatus.completed ||
        status == DownloadStatus.failed ||
        status == DownloadStatus.cancelled) {
      _reservedDestinations.remove(_normalize(old.destination));
    }
    _emit();
  }

  Future<void> _saveHistory() {
    // Serialize writes so late completion of an older snapshot cannot replace
    // the latest status. URLs and passwords are excluded by DownloadTask.toJson.
    final values = _tasks.reversed
        .take(maxHistoryItems)
        .toList()
        .reversed
        .toList();
    final snapshot = jsonEncode(values.map((value) => value.toJson()).toList());
    _historyWrites = _historyWrites.then((_) async {
      try {
        await _settings.writeDownloadHistory(snapshot);
        if (_historyError != null) {
          _historyError = null;
          _emit();
        }
      } catch (_) {
        _historyError = 'Download history could not be saved. Completed files are unaffected.';
        _emit();
      }
    });
    return _historyWrites;
  }

  void _emit() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _queue.clear();
    _retrySources.clear();
    _reservedDestinations.clear();
    _claimingMediaKeys.clear();
    _finalizing.clear();
    _deletingFiles.clear();
    _retryingIds.clear();
    for (final token in _tokens.values) {
      token.cancel('Application is closing');
    }
    super.dispose();
  }
}
