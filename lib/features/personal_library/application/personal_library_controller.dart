import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../library/domain/media_models.dart';
import '../data/library_repository.dart';
import '../domain/library_item.dart';

/// Account-scoped view model. Database operations are serialized so a late
/// playback event cannot overwrite a newer position on the same device.
class PersonalLibraryController extends ChangeNotifier {
  PersonalLibraryController(this._repository);
  final LibraryRepository _repository;
  String? _accountId;
  int _revision = 0;
  bool _closed = false;
  Future<void> _writes = Future<void>.value();
  List<LibraryItem> favorites = const [];
  List<LibraryItem> history = const [];
  String? error;

  String? get accountId => _accountId;

  Future<void> initialize() => _repository.initialize();

  Future<void> selectAccount(String? accountId) async {
    _accountId = accountId;
    final revision = ++_revision;
    favorites = const [];
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
      final savedFavorites = await _repository.favorites(id);
      final savedHistory = await _repository.history(id);
      if (!_closed && _revision == revision && _accountId == id) {
        favorites = savedFavorites;
        history = savedHistory;
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

  bool isFavorite(MediaEntry media) => favorites.any(
    (item) => item.kind == media.kind && item.mediaId == media.id,
  );

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
    if (id == null) {
      return;
    }
    final enabled = !isFavorite(media);
    await _write(
      () => _repository.setFavorite(
        LibraryItem.fromMedia(accountId: id, media: media),
        enabled,
      ),
    );
    if (_accountId == id) {
      await refresh();
    }
  }

  Future<LibraryItem?> progressFor(String accountId, MediaEntry media) =>
      _repository.progress(accountId, media.kind, media.id);

  Future<void> saveProgress({
    required String accountId,
    required MediaEntry media,
    required Duration position,
    required Duration duration,
    String? seriesTitle,
    bool completed = false,
  }) async {
    if (media.kind == LibraryKind.live) {
      return;
    }
    await _write(
      () => _repository.saveProgress(
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
    if (_accountId == accountId) {
      await refresh();
    }
  }

  Future<void> markWatched(LibraryItem item, bool watched) async {
    await _write(() => _repository.markWatched(item, watched));
    if (_accountId == item.accountId) {
      await refresh();
    }
  }

  Future<void> removeHistory(LibraryItem item) async {
    await _write(() => _repository.removeHistory(item));
    if (_accountId == item.accountId) {
      await refresh();
    }
  }

  Future<void> removeFromContinue(LibraryItem item) async {
    await _write(() => _repository.hideFromContinue(item));
    if (_accountId == item.accountId) {
      await refresh();
    }
  }

  Future<void> deleteAccount(String accountId) async {
    await _write(() => _repository.deleteAccount(accountId));
    if (_accountId == accountId) {
      await refresh();
    }
  }

  Future<void> clearHistory() async {
    final id = _accountId;
    if (id == null) {
      return;
    }
    await _write(() => _repository.clearHistory(id));
    if (_accountId == id) {
      await refresh();
    }
  }

  /// Only run after a full, successful catalog response (never on network errors).
  Future<void> reconcileCatalog(
    String accountId,
    LibraryKind kind,
    Iterable<String> ids,
  ) async {
    await _write(() => _repository.reconcileAvailable(accountId, kind, ids));
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
