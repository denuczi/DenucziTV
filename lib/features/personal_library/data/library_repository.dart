import '../../library/domain/media_models.dart';
import '../domain/library_item.dart';

/// A testable persistence boundary for favorites and playback activity.
abstract interface class LibraryRepository {
  Future<void> initialize();
  Future<bool> isFavorite(
    String accountId,
    LibraryKind kind,
    String mediaId, {
    String sourceScope = '',
  });
  Future<void> setFavorite(LibraryItem item, bool enabled);
  Future<List<LibraryItem>> favorites(
    String accountId, {
    bool includeUnavailable = false,
  });
  Future<LibraryItem?> progress(
    String accountId,
    LibraryKind kind,
    String mediaId, {
    String sourceScope = '',
  });
  Future<void> saveProgress(
    LibraryItem item, {
    required int positionMs,
    required int durationMs,
    required bool completed,
  });
  Future<void> markWatched(LibraryItem item, bool watched);
  Future<List<LibraryItem>> history(
    String accountId, {
    bool includeUnavailable = false,
  });
  Future<void> removeHistory(LibraryItem item);
  Future<void> hideFromContinue(LibraryItem item);
  Future<void> clearHistory(String accountId);
  Future<void> deleteAccount(String accountId);

  /// Call only after an entire provider catalog has loaded successfully.
  Future<void> reconcileAvailable(
    String accountId,
    LibraryKind kind,
    Iterable<String> ids, {
    String sourceScope = '',
  });
  Future<void> close();
}
