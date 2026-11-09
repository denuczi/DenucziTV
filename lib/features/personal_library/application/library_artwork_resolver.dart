import 'package:flutter/foundation.dart';

import '../../../core/models/account.dart';
import '../../library/data/xtream_api.dart';
import '../../library/domain/media_models.dart';
import '../domain/library_item.dart';

/// Resolves covers without persisting protected provider URLs. The bounded
/// session cache also shares one metadata request across episodes of a series.
class LibraryArtworkResolver {
  LibraryArtworkResolver(this._api);

  final XtreamApi _api;
  final _covers = <(LibraryKind, String), Future<String?>>{};
  String? _accountId;
  AccountCredentials? _credentials;
  int _generation = 0;
  static const _capacity = 128;

  void clear() {
    _generation++;
    _covers.clear();
    _accountId = null;
    _credentials = null;
  }

  Future<String?> resolve(
    LibraryItem item, {
    required String? accountId,
    required AccountCredentials? credentials,
    required Iterable<MediaEntry> catalog,
  }) {
    if (_accountId != accountId || !identical(_credentials, credentials)) {
      clear();
      _accountId = accountId;
      _credentials = credentials;
    }
    if (accountId != item.accountId || !item.available) {
      return SynchronousFuture(null);
    }
    final saved = _httpUrl(item.imageUrl);
    if (item.sourceScope.isEmpty && saved != null) {
      return SynchronousFuture(saved);
    }
    if (credentials == null ||
        credentials.linkExpired ||
        (credentials.protected &&
            credentials.accessGrant?.allowsNewSessions != true) ||
        credentials.sourceScope != item.sourceScope) {
      return SynchronousFuture(null);
    }
    final id = item.seriesId ?? item.mediaId;
    final key = (item.kind, id);
    final existing = _covers[key];
    if (existing != null) return existing;
    if (_covers.length >= _capacity) _covers.remove(_covers.keys.first);

    for (final media in catalog) {
      if (media.kind == item.kind &&
          media.id == id &&
          media.sourceScope == item.sourceScope) {
        final cover = _httpUrl(media.imageUrl);
        if (cover != null) {
          return _covers[key] = SynchronousFuture(cover);
        }
      }
    }
    final generation = _generation;
    late final Future<String?> request;
    request = _load(item.kind, id, credentials).then((cover) {
      if (generation != _generation ||
          credentials.linkExpired ||
          (credentials.protected &&
              credentials.accessGrant?.allowsNewSessions != true)) {
        return null;
      }
      // Failed requests may be retried when the row is rebuilt or revisited.
      if (cover == null && identical(_covers[key], request)) {
        _covers.remove(key);
      }
      return cover;
    });
    _covers[key] = request;
    return request;
  }

  Future<String?> _load(
    LibraryKind kind,
    String id,
    AccountCredentials credentials,
  ) async {
    try {
      final cover = switch (kind) {
        LibraryKind.movies => (await _api.movieDetails(
          credentials,
          id,
        )).imageUrl,
        LibraryKind.series => (await _api.seriesDetails(
          credentials,
          id,
        )).metadata.imageUrl,
        LibraryKind.live => null,
      };
      return _httpUrl(cover);
    } catch (_) {
      // Artwork failures must not hide library entries or expose provider URLs.
      return null;
    }
  }

  static String? _httpUrl(String? value) {
    final text = value?.trim();
    final uri = Uri.tryParse(text ?? '');
    return uri != null &&
            uri.hasAuthority &&
            uri.host.isNotEmpty &&
            (uri.scheme == 'http' || uri.scheme == 'https')
        ? text
        : null;
  }
}
