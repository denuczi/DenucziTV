import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/features/library/domain/media_models.dart';
import 'package:denuczi_tv/features/personal_library/application/personal_library_controller.dart';
import 'package:denuczi_tv/features/personal_library/data/sqlite_library_repository.dart';
import 'package:denuczi_tv/features/personal_library/domain/library_item.dart';

void main() {
  late Directory temp;
  late SqliteLibraryRepository repository;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('denuczitv-library-');
    repository = SqliteLibraryRepository(
      databasePath: '${temp.path}/library.sqlite',
    );
    await repository.initialize();
  });

  tearDown(() async {
    await repository.close();
    await temp.delete(recursive: true);
  });

  const movie = MediaEntry(
    id: 'movie-7',
    title: 'Movie',
    kind: LibraryKind.movies,
  );
  const series = MediaEntry(
    id: 'series-2',
    title: 'Series',
    kind: LibraryKind.series,
  );
  final episode = MediaEntry(
    id: 'episode-9',
    title: 'Episode',
    kind: LibraryKind.series,
    seasonNumber: 1,
    episodeNumber: 2,
    seriesId: series.id,
  );

  test('favorites are scoped by account and do not duplicate', () async {
    final one = LibraryItem.fromMedia(accountId: 'account-a', media: movie);
    await repository.setFavorite(one, true);
    await repository.setFavorite(one, true);
    expect((await repository.favorites('account-a')).length, 1);
    expect(await repository.favorites('account-b'), isEmpty);
    expect(
      await repository.isFavorite('account-a', LibraryKind.movies, movie.id),
      isTrue,
    );
    await repository.setFavorite(one, false);
    expect(await repository.favorites('account-a'), isEmpty);
  });

  test(
    'progress and watched flags survive closing and reopening SQLite',
    () async {
      final item = LibraryItem.fromMedia(
        accountId: 'account-a',
        media: episode,
        seriesTitle: series.title,
      );
      await repository.saveProgress(
        item,
        positionMs: 42000,
        durationMs: 120000,
        completed: false,
      );
      await repository.close();
      repository = SqliteLibraryRepository(
        databasePath: '${temp.path}/library.sqlite',
      );
      await repository.initialize();
      final saved = await repository.progress(
        'account-a',
        LibraryKind.series,
        episode.id,
      );
      expect(saved?.positionMs, 42000);
      expect(saved?.seriesId, series.id);
      expect(saved?.completed, isFalse);
      await repository.markWatched(item, true);
      expect(
        (await repository.progress(
          'account-a',
          LibraryKind.series,
          episode.id,
        ))?.completed,
        isTrue,
      );
      await repository.markWatched(item, false);
      expect(
        (await repository.progress(
          'account-a',
          LibraryKind.series,
          episode.id,
        ))?.completed,
        isFalse,
      );
    },
  );

  test('watch history can be cleared without removing favorites', () async {
    final item = LibraryItem.fromMedia(accountId: 'a', media: movie);
    await repository.setFavorite(item, true);
    await repository.saveProgress(
      item,
      positionMs: 70000,
      durationMs: 100000,
      completed: false,
    );
    await repository.clearHistory('a');
    expect(await repository.history('a'), isEmpty);
    expect((await repository.favorites('a')).length, 1);
  });

  test(
    'availability reconciliation only hides confirmed missing items',
    () async {
      final item = LibraryItem.fromMedia(accountId: 'a', media: movie);
      await repository.setFavorite(item, true);
      await repository.saveProgress(
        item,
        positionMs: 35000,
        durationMs: 100000,
        completed: false,
      );
      await repository.reconcileAvailable('a', LibraryKind.movies, ['other']);
      expect(await repository.history('a'), isEmpty);
      expect(await repository.favorites('a'), isEmpty);
      await repository.reconcileAvailable('a', LibraryKind.movies, ['movie-7']);
      expect((await repository.history('a')).length, 1);
      expect((await repository.favorites('a')).length, 1);
    },
  );

  test('controller aggregates episode activity into one series card', () async {
    final controller = PersonalLibraryController(repository);
    await controller.selectAccount('a');
    await controller.saveProgress(
      accountId: 'a',
      media: episode,
      seriesTitle: series.title,
      position: const Duration(seconds: 80),
      duration: const Duration(minutes: 12),
    );
    final otherEpisode = MediaEntry(
      id: 'episode-10',
      title: 'Next episode',
      kind: LibraryKind.series,
      seriesId: series.id,
      seasonNumber: 1,
      episodeNumber: 3,
    );
    await controller.saveProgress(
      accountId: 'a',
      media: otherEpisode,
      seriesTitle: series.title,
      position: const Duration(seconds: 95),
      duration: const Duration(minutes: 11),
    );
    expect(controller.continueWatching.length, 1);
    await controller.close();
    // The repository was closed by the controller. Tear-down may close again.
    repository = SqliteLibraryRepository(
      databasePath: '${temp.path}/library.sqlite',
    );
    await repository.initialize();
  });

  test(
    'deleting a provider clears only that provider personal library',
    () async {
      await repository.setFavorite(
        LibraryItem.fromMedia(accountId: 'a', media: movie),
        true,
      );
      await repository.setFavorite(
        LibraryItem.fromMedia(accountId: 'b', media: movie),
        true,
      );
      await repository.deleteAccount('a');
      expect(await repository.favorites('a'), isEmpty);
      expect((await repository.favorites('b')).length, 1);
    },
  );
}
