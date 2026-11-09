import 'dart:async';

import 'package:denuczi_tv/core/models/account.dart';
import 'package:denuczi_tv/core/models/protected_access_grant.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/features/library/data/xtream_api.dart';
import 'package:denuczi_tv/features/library/domain/media_models.dart';
import 'package:denuczi_tv/features/personal_library/application/library_artwork_resolver.dart';
import 'package:denuczi_tv/features/personal_library/domain/library_item.dart';
import 'package:flutter_test/flutter_test.dart';

class _CoverApi extends XtreamApi {
  _CoverApi(super.network);
  int movieRequests = 0;
  int seriesRequests = 0;
  Completer<MediaDetails>? pending;
  bool fail = false;

  @override
  Future<MediaDetails> movieDetails(
    AccountCredentials credentials,
    String id,
  ) async {
    movieRequests++;
    if (fail) throw StateError('Provider unavailable');
    if (pending != null) return pending!.future;
    return const MediaDetails(imageUrl: 'https://images.example/movie.jpg');
  }

  @override
  Future<SeriesDetails> seriesDetails(
    AccountCredentials credentials,
    String id,
  ) async {
    seriesRequests++;
    return SeriesDetails.fromJson({
      'episodes': <String, Object?>{},
      'info': {'cover': 'https://images.example/series.jpg'},
    });
  }
}

void main() {
  late _CoverApi api;
  late LibraryArtworkResolver resolver;
  late AccountCredentials credentials;
  const movie = LibraryItem(
    accountId: 'account',
    mediaId: 'movie',
    kind: LibraryKind.movies,
    title: 'Movie',
    sourceScope: 'generation-1',
  );

  setUp(() {
    final network = NetworkClient();
    addTearDown(network.dispose);
    api = _CoverApi(network);
    resolver = LibraryArtworkResolver(api);
    final grant = ProtectedAccessGrant(accountId: 'account');
    addTearDown(grant.dispose);
    credentials = AccountCredentials(
      serverUrl: 'https://provider.example',
      username: 'viewer',
      password: 'synthetic',
      label: 'Test',
      protected: true,
      sourceScope: 'generation-1',
      accessGrant: grant,
    );
  });

  Future<String?> resolve(
    LibraryItem item, {
    List<MediaEntry> catalog = const [],
  }) => resolver.resolve(
    item,
    accountId: 'account',
    credentials: credentials,
    catalog: catalog,
  );

  test(
    'protected covers come from current metadata without changing stored items',
    () async {
      expect(await resolve(movie), 'https://images.example/movie.jpg');
      expect(await resolve(movie), 'https://images.example/movie.jpg');
      expect(api.movieRequests, 1);
      expect(movie.imageUrl, isNull);
      expect(
        LibraryItem.fromMedia(
          accountId: 'account',
          media: const MediaEntry(
            id: 'movie',
            title: 'Movie',
            kind: LibraryKind.movies,
            sourceScope: 'generation-1',
            imageUrl: 'https://images.example/movie.jpg',
          ),
        ).imageUrl,
        isNull,
      );
    },
  );

  test('current catalog avoids metadata requests and ignores reused IDs from older sources', () async {
    expect(
      await resolve(
        movie,
        catalog: const [
          MediaEntry(
            id: 'movie',
            title: 'Old',
            kind: LibraryKind.movies,
            sourceScope: 'generation-0',
            imageUrl: 'https://images.example/old.jpg',
          ),
          MediaEntry(
            id: 'movie',
            title: 'Movie',
            kind: LibraryKind.movies,
            sourceScope: 'generation-1',
            imageUrl: 'https://images.example/current.jpg',
          ),
        ],
      ),
      'https://images.example/current.jpg',
    );
    expect(api.movieRequests, 0);
  });

  test('episodes share their series cover and one metadata request', () async {
    for (final id in ['episode-1', 'episode-2']) {
      expect(
        await resolve(
          LibraryItem(
            accountId: 'account',
            mediaId: id,
            kind: LibraryKind.series,
            title: id,
            sourceScope: 'generation-1',
            seriesId: 'series',
          ),
        ),
        'https://images.example/series.jpg',
      );
    }
    expect(api.seriesRequests, 1);
  });

  test(
    'unavailable entries and revoked grants never request artwork',
    () async {
      expect(await resolve(movie.withAvailability(false)), isNull);
      credentials.accessGrant!.revoke();
      expect(await resolve(movie), isNull);
      expect(api.movieRequests, 0);
    },
  );

  test('a late response from a previous session is discarded', () async {
    api.pending = Completer<MediaDetails>();
    final old = resolve(movie);
    resolver.clear();
    api.pending!.complete(
      const MediaDetails(imageUrl: 'https://images.example/old.jpg'),
    );
    expect(await old, isNull);
  });

  test('temporary metadata failures can be retried', () async {
    api.fail = true;
    expect(await resolve(movie), isNull);
    api.fail = false;
    expect(await resolve(movie), 'https://images.example/movie.jpg');
    expect(api.movieRequests, 2);
  });

  test(
    'saved manual artwork remains available without a live connection',
    () async {
      expect(
        await resolver.resolve(
          const LibraryItem(
            accountId: 'account',
            mediaId: 'manual',
            kind: LibraryKind.movies,
            title: 'Manual',
            imageUrl: 'https://images.example/saved.jpg',
          ),
          accountId: 'account',
          credentials: null,
          catalog: const [],
        ),
        'https://images.example/saved.jpg',
      );
    },
  );
}
