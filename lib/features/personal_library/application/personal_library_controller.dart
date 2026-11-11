import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../library/domain/media_models.dart';
import '../data/library_repository.dart';
import 'library_artwork_cache.dart';
import '../domain/library_item.dart';

/// Account-scoped view model. Database operations are serialized so a late
/// playback event cannot overwrite a newer position on the same device.
class PersonalLibraryController extends ChangeNotifier {
  PersonalLibraryController(this._repository, {this.artworkCache});
  final LibraryRepository _repository;
  final LibraryArtworkCache? artworkCache;
  final _favoriteIndex = <(LibraryKind, String, String)>{};
  final _pendingFavorites = <(String, LibraryKind, String, String)>{};
  final _deletingAccounts = <String>{};
  final _clearingFavorites = <String>{};
  String? _accountId;
  String? _sourceScope = '';
  int _revision = 0;
  bool _closed = false;
  Future<void> _writes = Future<void>.value();
  List<LibraryItem> favorites = const [];
  List<LibraryItem> history = const [];
  String? error;

  String? get accountId => _accountId;

  Future<void> initialize() => _repository.initialize();

  Future<void> selectAccount(
    String? accountId, {
    String? sourceScope = '',
    bool protected = false,
  }) async {
    _accountId = accountId;
    _sourceScope = sourceScope;
    final revision = ++_revision;
    favorites = const [];
    _favoriteIndex.clear();
    history = const [];
    error = null;
    notifyListeners();
    if (accountId == null) {
      return;
    }
    await _loadFor(accountId, revision);
  }

  Future<void> _loadFor(String id, int revision) async {
    try {
      final savedFavorites = await _repository.favorites(
        id,
        includeUnavailable: true,
      );
      final savedHistory = await _repository.history(
        id,
        includeUnavailable: true,
      );
      if (!_closed && _revision == revision && _accountId == id) {
        LibraryItem scoped(LibraryItem item) => item.withAvailability(
          item.available && item.sourceScope == _sourceScope,
        );
        favorites = savedFavorites.map(scoped).toList(growable: false);
        _favoriteIndex
          ..clear()
          ..addAll(
            favorites.map(
              (item) => (item.kind, item.mediaId, item.sourceScope),
            ),
          );
        history = savedHistory.map(scoped).toList(growable: false);
        error = null;
        notifyListeners();
      }
    } catch (_) {
      if (!_closed && _revision == revision) {
        error = 'The personal library could not be loaded.';
        notifyListeners();
      }
    }
  }

  Future<void> refresh() async {
    final id = _accountId;
    if (id != null) {
      await _loadFor(id, _revision);
    }
  }

  bool isFavorite(MediaEntry media) =>
      _favoriteIndex.contains((media.kind, media.id, media.sourceScope));

  bool favoritePending(MediaEntry media) => _pendingFavorites.contains((
    _accountId ?? '',
    media.kind,
    media.id,
    media.sourceScope,
  ));

  Future<T> _write<T>(Future<T> Function() work) {
    final result = _writes.then((_) => work());
    _writes = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<void> toggleFavorite(MediaEntry media) async {
    final id = _accountId;
    if (id == null ||
        _deletingAccounts.contains(id) ||
        _clearingFavorites.contains(id) ||
        media.sourceScope != _sourceScope ||
        (media.kind == LibraryKind.series && media.seriesId != null)) {
      return;
    }
    final key = (id, media.kind, media.id, media.sourceScope);
    if (!_pendingFavorites.add(key)) return;
    final revision = _revision;
    notifyListeners();
    try {
      final enabled = !isFavorite(media);
      final item = LibraryItem.fromMedia(accountId: id, media: media);
      await _write(() async {
        if (_deletingAccounts.contains(id)) return;
        await _repository.setFavorite(item, enabled);
      });
      if (!_closed && _accountId == id && _revision == revision) {
        await refresh();
      }
      if (enabled) {
        // Warm only the saved item, not the entire provider catalog.
        unawaited(artworkCache?.warm(id, media) ?? Future<void>.value());
      } else {
        await _evictIfUnreferenced(item);
      }
    } finally {
      _pendingFavorites.remove(key);
      if (!_closed) notifyListeners();
    }
  }

  Future<void> _evictIfUnreferenced(LibraryItem item) async {
    if (artworkCache == null) return;
    // Query the repository after the write to avoid evicting an image still
    // referenced by the other personal-library collection.
    final favorites = await _repository.favorites(
      item.accountId,
      includeUnavailable: true,
    );
    final history = await _repository.history(
      item.accountId,
      includeUnavailable: true,
    );
    bool same(LibraryItem other) =>
        other.kind == item.kind &&
        other.mediaId == item.mediaId &&
        other.sourceScope == item.sourceScope;
    if (!favorites.any(same) && !history.any(same)) {
      await artworkCache!.removeItem(item);
    }
  }

  Future<void> removeFavorite(LibraryItem item) async {
    if (_deletingAccounts.contains(item.accountId) ||
        _clearingFavorites.contains(item.accountId)) {
      return;
    }
    await _write(() => _repository.setFavorite(item, false));
    if (_accountId == item.accountId) await refresh();
    await _evictIfUnreferenced(item);
  }

  Future<void> clearFavorites({String? expectedAccountId}) async {
    final id = _accountId;
    if (id == null ||
        (expectedAccountId != null && expectedAccountId != id) ||
        _deletingAccounts.contains(id) ||
        !_clearingFavorites.add(id)) {
      return;
    }
    notifyListeners();
    try {
      // Serialize against outstanding favorite writes and query the snapshot
      // inside the same queue; clear never affects other provider accounts.
      final removed = await _write(() async {
        final items = await _repository.favorites(id, includeUnavailable: true);
        await _repository.clearFavorites(id);
        return items;
      });
      if (_accountId == id) {
        await refresh();
      }
      if (artworkCache != null && removed.isNotEmpty) {
        final historyItems = await _repository.history(
          id,
          includeUnavailable: true,
        );
        final retained = {
          for (final item in historyItems)
            (item.kind, item.mediaId, item.sourceScope),
        };
        for (final item in removed) {
          if (!retained.contains((item.kind, item.mediaId, item.sourceScope))) {
            await artworkCache!.removeItem(item);
          }
        }
      }
    } finally {
      _clearingFavorites.remove(id);
      if (!_closed) notifyListeners();
    }
  }

  Future<LibraryItem?> progressFor(String accountId, MediaEntry media) =>
      _repository.progress(
        accountId,
        media.kind,
        media.id,
        sourceScope: media.sourceScope,
      );

  Future<void> saveProgress({
    required String accountId,
    required MediaEntry media,
    required Duration position,
    required Duration duration,
    String? seriesTitle,
    bool completed = false,
  }) async {
    if (media.kind == LibraryKind.live ||
        _deletingAccounts.contains(accountId)) {
      return;
    }
    await _write(
      () => _deletingAccounts.contains(accountId)
          ? Future<void>.value()
          : _repository.saveProgress(
              LibraryItem.fromMedia(
                accountId: accountId,
                media: media,
                seriesTitle: seriesTitle,
              ),
              positionMs: position.inMilliseconds,
              durationMs: duration.inMilliseconds,
              completed: completed,
            ),
    );
    if (media.imageUrl != null) {
      unawaited(artworkCache?.warm(accountId, media) ?? Future<void>.value());
    }
    if (_accountId == accountId) {
      await refresh();
    }
  }

  Future<void> markWatched(LibraryItem item, bool watched) async {
    if (_deletingAccounts.contains(item.accountId)) return;
    await _write(() => _repository.markWatched(item, watched));
    if (_accountId == item.accountId) {
      await refresh();
    }
  }

  Future<void> removeHistory(LibraryItem item) async {
    if (_deletingAccounts.contains(item.accountId)) return;
    await _write(() => _repository.removeHistory(item));
    if (_accountId == item.accountId) await refresh();
    await _evictIfUnreferenced(item);
  }

  Future<void> removeFromContinue(LibraryItem item) async {
    await _write(() => _repository.hideFromContinue(item));
    if (_accountId == item.accountId) {
      await refresh();
    }
  }

  Future<void> deleteAccount(String accountId) async {
    // Block late UI actions before the queued delete reaches SQLite.
    _deletingAccounts.add(accountId);
    await _write(() => _repository.deleteAccount(accountId));
    await artworkCache?.removeAccount(accountId);
    if (_accountId == accountId) await refresh();
  }

  Future<void> clearHistory() async {
    final id = _accountId;
    if (id == null || _deletingAccounts.contains(id)) return;
    final removed = await _repository.history(id, includeUnavailable: true);
    await _write(() => _repository.clearHistory(id));
    if (_accountId == id) await refresh();
    for (final item in removed) {
      await _evictIfUnreferenced(item);
    }
  }

  /// Only run after a full, successful catalog response (never on network errors).
  Future<void> reconcileCatalog(
    String accountId,
    LibraryKind kind,
    Iterable<String> ids, {
    String sourceScope = '',
  }) async {
    await _write(
      () => _repository.reconcileAvailable(
        accountId,
        kind,
        ids,
        sourceScope: sourceScope,
      ),
    );
    if (_accountId == accountId) {
      await refresh();
    }
  }

  /// A series is represented once by its most recently watched episode.
  List<LibraryItem> get continueWatching {
    final visible = <LibraryItem>[];
    final seriesSeen = <String>{};
    for (final item in history) {
      if (item.completed ||
          item.hiddenFromContinue ||
          !item.available ||
          item.positionMs <= 0) {
        continue;
      }
      final seriesId = item.seriesId;
      if (seriesId != null && !seriesSeen.add(seriesId)) {
        continue;
      }
      visible.add(item);
    }
    return visible;
  }

  Future<void> close() async {
    _closed = true;
    await _writes;
    await _repository.close();
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}
