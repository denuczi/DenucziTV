import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:denuczi_tv/features/library/domain/media_models.dart';
import 'package:denuczi_tv/features/personal_library/application/personal_library_controller.dart';
import 'package:denuczi_tv/features/personal_library/data/sqlite_library_repository.dart';
import 'package:denuczi_tv/features/personal_library/domain/library_item.dart';

void main() {
  test('version 1 favorites and progress survive the transactional scope migration', () async {
    final directory = await Directory.systemTemp.createTemp(
      'protected-migration-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/library.sqlite';
    sqfliteFfiInit();
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE favorites (account_id TEXT NOT NULL, kind TEXT NOT NULL, media_id TEXT NOT NULL, title TEXT NOT NULL, image_url TEXT, created_at INTEGER NOT NULL, available INTEGER NOT NULL DEFAULT 1, PRIMARY KEY(account_id,kind,media_id))',
          );
          await db.execute(
            'CREATE TABLE watch_activity (account_id TEXT NOT NULL, kind TEXT NOT NULL, media_id TEXT NOT NULL, title TEXT NOT NULL, image_url TEXT, series_id TEXT, series_title TEXT, season INTEGER, episode INTEGER, container_extension TEXT, position_ms INTEGER NOT NULL DEFAULT 0, duration_ms INTEGER NOT NULL DEFAULT 0, completed INTEGER NOT NULL DEFAULT 0, hidden_from_continue INTEGER NOT NULL DEFAULT 0, available INTEGER NOT NULL DEFAULT 1, updated_at INTEGER NOT NULL, PRIMARY KEY(account_id,kind,media_id))',
          );
          await db.execute(
            'CREATE INDEX watch_recent ON watch_activity(account_id,updated_at DESC)',
          );
          await db.execute(
            'CREATE INDEX favorites_by_account ON favorites(account_id,created_at DESC)',
          );
        },
      ),
    );
    await old.insert('favorites', {
      'account_id': 'manual',
      'kind': 'movies',
      'media_id': '100',
      'title': 'Original',
      'created_at': 1,
    });
    await old.insert('watch_activity', {
      'account_id': 'manual',
      'kind': 'movies',
      'media_id': '100',
      'title': 'Original',
      'position_ms': 42000,
      'duration_ms': 120000,
      'updated_at': 1,
    });
    await old.close();
    final repository = SqliteLibraryRepository(databasePath: path);
    await repository.initialize();
    addTearDown(repository.close);
    expect((await repository.favorites('manual')).single.title, 'Original');
    expect(
      (await repository.progress(
        'manual',
        LibraryKind.movies,
        '100',
      ))!.positionMs,
      42000,
    );
    expect((await repository.favorites('manual')).single.sourceScope, '');
    await repository.setFavorite(
      const LibraryItem(
        accountId: 'manual',
        mediaId: '100',
        kind: LibraryKind.movies,
        title: 'Another source',
        sourceScope: 'new-source',
      ),
      true,
    );
    expect((await repository.favorites('manual')).length, 2);
    expect(
      (await repository.progress('manual', LibraryKind.movies, '100'))!.title,
      'Original',
    );
  });

  test('old generations remain visible but unavailable without attaching their progress to reused IDs', () async {
    final directory = await Directory.systemTemp.createTemp(
      'protected-scopes-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final repository = SqliteLibraryRepository(
      databasePath: '${directory.path}/library.sqlite',
    );
    final library = PersonalLibraryController(repository);
    await library.initialize();
    addTearDown(library.close);
    const old = MediaEntry(
      id: '100',
      title: 'Original film',
      kind: LibraryKind.movies,
      sourceScope: 'old-source',
    );
    const replacement = MediaEntry(
      id: '100',
      title: 'Unrelated film',
      kind: LibraryKind.movies,
      sourceScope: 'new-source',
    );
    await library.selectAccount(
      'protected-account',
      sourceScope: 'old-source',
      protected: true,
    );
    await library.toggleFavorite(old);
    await library.saveProgress(
      accountId: 'protected-account',
      media: old,
      position: const Duration(seconds: 42),
      duration: const Duration(minutes: 2),
    );
    await library.selectAccount(
      'protected-account',
      sourceScope: 'new-source',
      protected: true,
    );
    expect(library.favorites.single.available, isFalse);
    expect(library.history.single.positionMs, 42000);
    expect(library.history.single.available, isFalse);
    expect(await library.progressFor('protected-account', replacement), isNull);
    await library.toggleFavorite(replacement);
    expect(library.favorites.length, 2);
    await library.reconcileCatalog(
      'protected-account',
      LibraryKind.movies,
      [],
      sourceScope: 'new-source',
    );
    expect(library.favorites.every((item) => !item.available), isTrue);
    await library.selectAccount(
      'protected-account',
      sourceScope: null,
      protected: true,
    );
    expect(library.history.single.positionMs, 42000);
    expect(library.favorites.length, 2);
  });
}
