import 'dart:io';

import 'package:denuczi_tv/features/library/domain/media_models.dart';
import 'package:denuczi_tv/features/personal_library/application/personal_library_controller.dart';
import 'package:denuczi_tv/features/personal_library/data/sqlite_library_repository.dart';
import 'package:denuczi_tv/features/personal_library/domain/library_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late SqliteLibraryRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('denuczitv-live-favs-');
    repository = SqliteLibraryRepository(
      databasePath: '${directory.path}/library.sqlite',
    );
    await repository.initialize();
  });

  tearDown(() async {
    await repository.close();
    await directory.delete(recursive: true);
  });

  test(
    'Live favorites are unique and isolated by account and source scope',
    () async {
      const channel = MediaEntry(
        id: '10',
        title: 'News',
        kind: LibraryKind.live,
      );
      final first = LibraryItem.fromMedia(accountId: 'a', media: channel);
      await repository.setFavorite(first, true);
      await repository.setFavorite(first, true);
      await repository.setFavorite(
        LibraryItem.fromMedia(accountId: 'b', media: channel),
        true,
      );
      await repository.setFavorite(
        LibraryItem.fromMedia(
          accountId: 'a',
          media: channel.withSourceScope('generation-2'),
        ),
        true,
      );

      expect((await repository.favorites('a')).length, 2);
      expect((await repository.favorites('b')).length, 1);
      expect((await repository.history('a')), isEmpty);
      await repository.deleteAccount('a');
      expect(await repository.favorites('a'), isEmpty);
      expect((await repository.favorites('b')).length, 1);
    },
  );

  test(
    'Live favorites become unavailable and recover after catalog refresh',
    () async {
      const channel = MediaEntry(
        id: '55',
        title: 'Sports',
        kind: LibraryKind.live,
      );
      await repository.setFavorite(
        LibraryItem.fromMedia(accountId: 'a', media: channel),
        true,
      );
      await repository.reconcileAvailable('a', LibraryKind.live, ['other']);
      expect(await repository.favorites('a'), isEmpty);
      expect(
        (await repository.favorites(
          'a',
          includeUnavailable: true,
        )).single.available,
        isFalse,
      );
      await repository.reconcileAvailable('a', LibraryKind.live, ['55']);
      expect((await repository.favorites('a')).single.available, isTrue);
    },
  );

  test(
    'Switching accounts restores original Live favorites, without merging',
    () async {
      const channel = MediaEntry(
        id: '10',
        title: 'Cinema',
        kind: LibraryKind.live,
      );
      final controller = PersonalLibraryController(repository);
      addTearDown(controller.dispose);
      await controller.selectAccount('one');
      await controller.toggleFavorite(channel);
      expect(controller.isFavorite(channel), isTrue);

      await controller.selectAccount('two');
      expect(controller.isFavorite(channel), isFalse);
      await controller.toggleFavorite(channel);
      await controller.selectAccount('one');
      expect(controller.isFavorite(channel), isTrue);
      expect((await repository.favorites('one')).length, 1);
      expect((await repository.favorites('two')).length, 1);
    },
  );

  test('Series episodes cannot be added as standalone favorites', () async {
    final episode = LibraryItem.fromMedia(
      accountId: 'a',
      media: const MediaEntry(
        id: 'episode',
        title: 'Pilot',
        kind: LibraryKind.series,
        seriesId: 'series',
      ),
    );
    await expectLater(
      repository.setFavorite(episode, true),
      throwsArgumentError,
    );
  });
  test(
    'clearing favorites only affects the selected account and not history',
    () async {
      const movie = MediaEntry(
        id: 'movie',
        title: 'Movie',
        kind: LibraryKind.movies,
      );
      const live = MediaEntry(
        id: 'live',
        title: 'Live',
        kind: LibraryKind.live,
      );
      final movieA = LibraryItem.fromMedia(accountId: 'a', media: movie);
      await repository.setFavorite(movieA, true);
      await repository.setFavorite(
        LibraryItem.fromMedia(accountId: 'a', media: live),
        true,
      );
      await repository.setFavorite(
        LibraryItem.fromMedia(accountId: 'b', media: movie),
        true,
      );
      await repository.saveProgress(
        movieA,
        positionMs: 1000,
        durationMs: 2000,
        completed: false,
      );

      final controller = PersonalLibraryController(repository);
      addTearDown(controller.dispose);
      await controller.selectAccount('a');
      expect(controller.favorites, hasLength(2));
      await controller.clearFavorites();

      expect(controller.favorites, isEmpty);
      expect(controller.isFavorite(live), isFalse);
      expect(
        await repository.favorites('a', includeUnavailable: true),
        isEmpty,
      );
      expect((await repository.favorites('b')).length, 1);
      expect((await repository.history('a')).length, 1);

      await controller.selectAccount('b');
      expect(controller.favorites, hasLength(1));
    },
  );
}
