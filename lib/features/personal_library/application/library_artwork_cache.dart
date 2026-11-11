import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/network/network_client.dart';
import '../../library/domain/media_models.dart';
import '../domain/library_item.dart';

/// Stores small artwork files without persisting provider URLs or credentials.
/// Files are scoped by account and source generation and expire after 72 hours.
/// This cache never determines whether protected content may be played.
class LibraryArtworkCache {
  LibraryArtworkCache(
    this._network, {
    Directory? directory,
    DateTime Function()? clock,
  }) : _rootOverride = directory,
       _clock = clock ?? DateTime.now;

  static const ttl = Duration(days: 3);
  static const maxImageBytes = 2 * 1024 * 1024;
  static const maxCacheBytes = 120 * 1024 * 1024;
  static const maxCacheFiles = 600;

  final NetworkClient _network;
  final Directory? _rootOverride;
  final DateTime Function() _clock;
  Future<Directory>? _rootFuture;
  final Map<String, Future<File?>> _pending = {};
  final Map<String, int> _accountEpoch = {};
  final Map<String, int> _itemEpoch = {};
  final Set<String> _deletedAccounts = {};
  final List<Completer<void>> _waiting = [];
  int _inFlight = 0;
  DateTime? _lastPruned;
  int _bytesSincePrune = 0;
  int _filesSincePrune = 0;

  // Dart's String.hashCode is not stable across application launches. FNV-1a
  // produces a deterministic opaque file name with no provider URL in it.
  static String _hash(String value) {
    var hash = 0x4bf29ce484222325;
    for (final byte in utf8.encode(value)) {
      hash = ((hash ^ byte) * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  String _accountKey(String accountId) => _hash(jsonEncode([accountId]));

  String _itemKey(LibraryItem item) => _hash(
    jsonEncode([
      item.accountId,
      item.sourceScope,
      item.kind.name,
      item.mediaId,
    ]),
  );

  Future<Directory> _root() => _rootFuture ??= () async {
    final root =
        _rootOverride ??
        Directory(
          '${(await getApplicationSupportDirectory()).path}'
          '${Platform.pathSeparator}denuczi_tv'
          '${Platform.pathSeparator}artwork_cache',
        );
    await root.create(recursive: true);
    return root;
  }();

  Future<File> _fileFor(LibraryItem item) async {
    final root = await _root();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}${_accountKey(item.accountId)}',
    );
    return File(
      '${directory.path}${Platform.pathSeparator}${_itemKey(item)}.img',
    );
  }

  Future<bool> _isFresh(File file) async {
    try {
      final stat = await file.stat();
      return stat.type == FileSystemEntityType.file &&
          stat.size > 0 &&
          stat.size <= maxImageBytes &&
          !_clock().difference(stat.modified).isNegative &&
          _clock().difference(stat.modified) < ttl;
    } on FileSystemException {
      return false;
    }
  }

  Future<File?> getOrLoad(
    LibraryItem item, {
    Future<String?> Function()? resolveUrl,
  }) async {
    if (_deletedAccounts.contains(item.accountId)) return null;
    try {
      final file = await _fileFor(item);
      if (await _isFresh(file)) return file;
      if (await file.exists()) await file.delete();
      if (resolveUrl == null) return null;
      final key = '${_accountKey(item.accountId)}/${_itemKey(item)}';
      final already = _pending[key];
      if (already != null) return await already;
      final epoch = _accountEpoch[item.accountId] ?? 0;
      final itemEpoch = _itemEpoch[key] ?? 0;
      final work = _load(item, file, resolveUrl, epoch, itemEpoch);
      _pending[key] = work;
      try {
        return await work;
      } finally {
        if (identical(_pending[key], work)) {
          // The completed future has already been awaited; remove only its
          // reference so later requests can start a new download.
          unawaited(_pending.remove(key));
        }
      }
    } catch (_) {
      // An image cache must never prevent the personal library from loading.
      return null;
    }
  }

  Future<void> warm(String accountId, MediaEntry media) async {
    final item = LibraryItem.fromMedia(accountId: accountId, media: media);
    if (media.imageUrl == null || _deletedAccounts.contains(accountId)) return;
    await getOrLoad(item, resolveUrl: () async => media.imageUrl);
  }

  Future<void> _acquire() async {
    if (_inFlight < 3) {
      _inFlight++;
      return;
    }
    final waiter = Completer<void>();
    _waiting.add(waiter);
    await waiter.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete();
    } else {
      _inFlight--;
    }
  }

  Future<File?> _load(
    LibraryItem item,
    File destination,
    Future<String?> Function() resolveUrl,
    int epoch,
    int itemEpoch,
  ) async {
    await _acquire();
    File? temporary;
    try {
      if (await _isFresh(destination)) return destination;
      if (await destination.exists()) await destination.delete();
      final url = await resolveUrl();
      final uri = Uri.tryParse(url ?? '');
      if (uri == null ||
          !uri.hasAuthority ||
          uri.userInfo.isNotEmpty ||
          (uri.scheme != 'http' && uri.scheme != 'https')) {
        return null;
      }
      final response = await _network.dio.get<ResponseBody>(
        uri.toString(),
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: true,
          maxRedirects: 4,
          headers: _network.imageHeaders,
        ),
      );
      if (response.data == null) return null;
      if (response.statusCode != 200) {
        await response.data!.stream.listen((_) {}).cancel();
        return null;
      }
      final mime = response.headers
          .value(Headers.contentTypeHeader)
          ?.toLowerCase();
      final declaredSize =
          int.tryParse(
            response.headers.value(Headers.contentLengthHeader) ?? '',
          ) ??
          0;
      if ((mime != null &&
              !mime.startsWith('image/') &&
              !mime.startsWith('application/octet-stream')) ||
          declaredSize > maxImageBytes) {
        await response.data!.stream.listen((_) {}).cancel();
        return null;
      }
      await destination.parent.create(recursive: true);
      final partial = File('${destination.path}.part');
      temporary = partial;
      final sink = partial.openWrite();
      var size = 0;
      var valid = true;
      try {
        await for (final chunk in response.data!.stream) {
          size += chunk.length;
          if (size > maxImageBytes) {
            valid = false;
            break;
          }
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }
      final itemKey = '${_accountKey(item.accountId)}/${_itemKey(item)}';
      bool stillOwned() =>
          !_deletedAccounts.contains(item.accountId) &&
          (_accountEpoch[item.accountId] ?? 0) == epoch &&
          (_itemEpoch[itemKey] ?? 0) == itemEpoch;
      if (!valid || size == 0 || !stillOwned() || !await _isImage(partial)) {
        return null;
      }
      if (await destination.exists()) await destination.delete();
      await partial.rename(destination.path);
      temporary = null;
      if (!stillOwned()) {
        await destination.delete();
        return null;
      }
      await destination.setLastModified(_clock());
      unawaited(_pruneIfDue(size).catchError((Object _) {}));
      return destination;
    } catch (_) {
      return null;
    } finally {
      if (temporary != null) {
        try {
          if (await temporary.exists()) await temporary.delete();
        } catch (_) {}
      }
      _release();
    }
  }

  static Future<bool> _isImage(File file) async {
    final reader = await file.open();
    try {
      final prefix = await reader.read(12);
      if (prefix.length < 12) return false;

      // Image signatures contain arbitrary bytes (for example, PNG starts
      // with 0x89). Never decode them as UTF-8: invalid text sequences would
      // incorrectly reject otherwise valid cached artwork.
      final jpeg = prefix[0] == 0xff && prefix[1] == 0xd8 && prefix[2] == 0xff;
      final png =
          prefix[0] == 0x89 &&
          prefix[1] == 0x50 &&
          prefix[2] == 0x4e &&
          prefix[3] == 0x47 &&
          prefix[4] == 0x0d &&
          prefix[5] == 0x0a &&
          prefix[6] == 0x1a &&
          prefix[7] == 0x0a;
      final gif =
          prefix[0] == 0x47 &&
          prefix[1] == 0x49 &&
          prefix[2] == 0x46 &&
          prefix[3] == 0x38 &&
          (prefix[4] == 0x37 || prefix[4] == 0x39) &&
          prefix[5] == 0x61;
      final webp =
          prefix[0] == 0x52 &&
          prefix[1] == 0x49 &&
          prefix[2] == 0x46 &&
          prefix[3] == 0x46 &&
          prefix[8] == 0x57 &&
          prefix[9] == 0x45 &&
          prefix[10] == 0x42 &&
          prefix[11] == 0x50;
      return jpeg || png || gif || webp;
    } finally {
      await reader.close();
    }
  }

  /// Remove an image only when neither favorites nor history still owns it.
  Future<void> removeItem(LibraryItem item) async {
    final key = '${_accountKey(item.accountId)}/${_itemKey(item)}';
    _itemEpoch[key] = (_itemEpoch[key] ?? 0) + 1;
    try {
      final file = await _fileFor(item);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<void> removeAccount(String accountId) async {
    _deletedAccounts.add(accountId);
    _accountEpoch[accountId] = (_accountEpoch[accountId] ?? 0) + 1;
    _itemEpoch.removeWhere(
      (key, _) => key.startsWith('${_accountKey(accountId)}/'),
    );
    try {
      final root = await _root();
      final directory = Directory(
        '${root.path}${Platform.pathSeparator}${_accountKey(accountId)}',
      );
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (_) {}
  }

  Future<void> _pruneIfDue(int writtenBytes) async {
    _bytesSincePrune += writtenBytes;
    _filesSincePrune++;
    final now = _clock();
    if (_lastPruned != null &&
        now.difference(_lastPruned!) < const Duration(minutes: 10) &&
        _bytesSincePrune < 8 * 1024 * 1024 &&
        _filesSincePrune < 32) {
      return;
    }
    _lastPruned = now;
    _bytesSincePrune = 0;
    _filesSincePrune = 0;
    final root = await _root();
    final files = <File>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.endsWith('.img')) files.add(entity);
    }
    final fresh = <(File, FileStat)>[];
    for (final file in files) {
      try {
        final stat = await file.stat();
        if (now.difference(stat.modified) >= ttl || stat.size > maxImageBytes) {
          await file.delete();
        } else {
          fresh.add((file, stat));
        }
      } catch (_) {}
    }
    fresh.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    var total = fresh.fold<int>(0, (sum, file) => sum + file.$2.size);
    while (fresh.length > maxCacheFiles || total > maxCacheBytes) {
      final oldest = fresh.removeAt(0);
      total -= oldest.$2.size;
      try {
        await oldest.$1.delete();
      } catch (_) {}
    }
  }
}
