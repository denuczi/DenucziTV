import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../library/domain/media_models.dart';
import '../domain/library_item.dart';
import 'library_repository.dart';

/// SQLite implementation. sqflite_common_ffi runs disk operations off the UI
/// isolate on desktop. Schema changes must use versioned migrations.
class SqliteLibraryRepository implements LibraryRepository {
  SqliteLibraryRepository({this.databasePath, this.factory});

  /// Override the database path or factory for isolated tests.
  final String? databasePath;
  final DatabaseFactory? factory;
  Database? _db;

  Database get _database {
    final db = _db;
    if (db == null) {
      throw StateError('Library database is not initialized.');
    }
    return db;
  }

  @override
  Future<void> initialize() async {
    if (_db != null) {
      return;
    }
    sqfliteFfiInit();
    final directory = await getApplicationSupportDirectoryIfNeeded();
    final path =
        databasePath ??
        '${directory.path}${Platform.pathSeparator}library.sqlite';
    _db = await (factory ?? databaseFactoryFfi).openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.execute('PRAGMA busy_timeout = 3000');
        },
        onCreate: (db, version) => _createTables(db),
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            for (final table in ['favorites', 'watch_activity']) {
              await db.execute('ALTER TABLE $table RENAME TO ${table}_v1');
            }
            await db.execute('DROP INDEX IF EXISTS watch_recent');
            await db.execute('DROP INDEX IF EXISTS favorites_by_account');
            await _createTables(db);
            for (final table in ['favorites', 'watch_activity']) {
              final fields = await db.rawQuery(
                'PRAGMA table_info(${table}_v1)',
              );
              final columns = fields
                  .map((field) => field['name'] as String)
                  .join(',');
              await db.execute(
                "INSERT INTO $table ($columns,source_scope) SELECT $columns,'' FROM ${table}_v1",
              );
              await db.execute('DROP TABLE ${table}_v1');
            }
          }
        },
      ),
    );
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
            CREATE TABLE favorites (
              account_id TEXT NOT NULL,
              source_scope TEXT NOT NULL DEFAULT '',
              kind TEXT NOT NULL,
              media_id TEXT NOT NULL,
              title TEXT NOT NULL,
              image_url TEXT,
              created_at INTEGER NOT NULL,
              available INTEGER NOT NULL DEFAULT 1,
              PRIMARY KEY (account_id, source_scope, kind, media_id)
            )
          ''');
    await db.execute('''
            CREATE TABLE watch_activity (
              account_id TEXT NOT NULL,
              source_scope TEXT NOT NULL DEFAULT '',
              kind TEXT NOT NULL,
              media_id TEXT NOT NULL,
              title TEXT NOT NULL,
              image_url TEXT,
              series_id TEXT,
              series_title TEXT,
              season INTEGER,
              episode INTEGER,
              container_extension TEXT,
              position_ms INTEGER NOT NULL DEFAULT 0 CHECK(position_ms >= 0),
              duration_ms INTEGER NOT NULL DEFAULT 0 CHECK(duration_ms >= 0),
              completed INTEGER NOT NULL DEFAULT 0,
              hidden_from_continue INTEGER NOT NULL DEFAULT 0,
              available INTEGER NOT NULL DEFAULT 1,
              updated_at INTEGER NOT NULL,
              PRIMARY KEY (account_id, source_scope, kind, media_id)
            )
          ''');
    await db.execute(
      'CREATE INDEX watch_recent ON watch_activity(account_id, updated_at DESC)',
    );
    await db.execute(
      'CREATE INDEX favorites_by_account ON favorites(account_id, created_at DESC)',
    );
  }

  /// Tests can provide a database path and do not need Flutter platform mocks.
  Future<Directory> getApplicationSupportDirectoryIfNeeded() async {
    if (databasePath != null) {
      return Directory.systemTemp;
    }
    final base = await getApplicationSupportDirectory();
    final directory = Directory(
      '${base.path}${Platform.pathSeparator}denuczi_tv',
    );
    await directory.create(recursive: true);
    return directory;
  }

  LibraryKind _kind(String raw) => LibraryKind.values.firstWhere(
    (kind) => kind.name == raw,
    orElse: () => LibraryKind.movies,
  );
  int _int(Object? value) =>
      value is int ? value : (value as num?)?.toInt() ?? 0;

  LibraryItem _fromWatch(Map<String, Object?> row) => LibraryItem(
    accountId: row['account_id']! as String,
    mediaId: row['media_id']! as String,
    sourceScope: row['source_scope']! as String,
    kind: _kind(row['kind']! as String),
    title: row['title']! as String,
    imageUrl: row['image_url'] as String?,
    seriesId: row['series_id'] as String?,
    seriesTitle: row['series_title'] as String?,
    season: row['season'] as int?,
    episode: row['episode'] as int?,
    containerExtension: row['container_extension'] as String?,
    positionMs: _int(row['position_ms']),
    durationMs: _int(row['duration_ms']),
    completed: _int(row['completed']) == 1,
    hiddenFromContinue: _int(row['hidden_from_continue']) == 1,
    available: _int(row['available']) == 1,
    updatedAtMs: _int(row['updated_at']),
  );

  @override
  Future<bool> isFavorite(
    String accountId,
    LibraryKind kind,
    String mediaId, {
    String sourceScope = '',
  }) async {
    final rows = await _database.query(
      'favorites',
      columns: ['media_id'],
      where:
          'account_id = ? AND kind = ? AND media_id = ? AND source_scope = ?',
      whereArgs: [accountId, kind.name, mediaId, sourceScope],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<void> setFavorite(LibraryItem item, bool enabled) async {
    if (item.isEpisode) {
      throw ArgumentError('Episodes cannot be favorited individually.');
    }
    if (enabled) {
      await _database.insert('favorites', {
        'account_id': item.accountId,
        'source_scope': item.sourceScope,
        'kind': item.kind.name,
        'media_id': item.mediaId,
        'title': item.title,
        'image_url': item.imageUrl,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'available': 1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      await _database.delete(
        'favorites',
        where:
            'account_id = ? AND kind = ? AND media_id = ? AND source_scope = ?',
        whereArgs: [
          item.accountId,
          item.kind.name,
          item.mediaId,
          item.sourceScope,
        ],
      );
    }
  }

  @override
  Future<void> clearFavorites(String accountId) async {
    await _database.delete(
      'favorites',
      where: 'account_id = ?',
      whereArgs: [accountId],
    );
  }

  @override
  Future<List<LibraryItem>> favorites(
    String accountId, {
    bool includeUnavailable = false,
  }) async {
    final rows = await _database.query(
      'favorites',
      where: includeUnavailable
          ? 'account_id = ?'
          : 'account_id = ? AND available = 1',
      whereArgs: [accountId],
      orderBy: 'created_at DESC',
      limit: 5000,
    );
    return [
      for (final row in rows)
        LibraryItem(
          accountId: accountId,
          mediaId: row['media_id']! as String,
          sourceScope: row['source_scope']! as String,
          available: _int(row['available']) == 1,
          kind: _kind(row['kind']! as String),
          title: row['title']! as String,
          imageUrl: row['image_url'] as String?,
        ),
    ];
  }

  @override
  Future<LibraryItem?> progress(
    String accountId,
    LibraryKind kind,
    String mediaId, {
    String sourceScope = '',
  }) async {
    final rows = await _database.query(
      'watch_activity',
      where:
          'account_id = ? AND kind = ? AND media_id = ? AND source_scope = ?',
      whereArgs: [accountId, kind.name, mediaId, sourceScope],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromWatch(rows.first);
  }

  @override
  Future<void> saveProgress(
    LibraryItem item, {
    required int positionMs,
    required int durationMs,
    required bool completed,
  }) async {
    if (item.kind == LibraryKind.live) {
      return;
    }
    final safeDuration = durationMs < 0 ? 0 : durationMs;
    final safePosition = positionMs < 0
        ? 0
        : (safeDuration > 0 ? positionMs.clamp(0, safeDuration) : positionMs);
    await _database.transaction((txn) async {
      final existing = await txn.query(
        'watch_activity',
        where:
            'account_id = ? AND kind = ? AND media_id = ? AND source_scope = ?',
        whereArgs: [
          item.accountId,
          item.kind.name,
          item.mediaId,
          item.sourceScope,
        ],
        limit: 1,
      );
      final previous = existing.isEmpty ? null : existing.first;
      await txn.insert('watch_activity', {
        'account_id': item.accountId,
        'source_scope': item.sourceScope,
        'kind': item.kind.name,
        'media_id': item.mediaId,
        'title': item.title,
        'image_url': item.imageUrl,
        'series_id': item.seriesId,
        'series_title': item.seriesTitle,
        'season': item.season,
        'episode': item.episode,
        'container_extension': item.containerExtension,
        'position_ms': safePosition,
        'duration_ms': safeDuration,
        'completed': completed ? 1 : 0,
        'hidden_from_continue': 0,
        'available': previous?['available'] ?? 1,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  @override
  Future<void> markWatched(LibraryItem item, bool watched) async {
    final existing = await progress(
      item.accountId,
      item.kind,
      item.mediaId,
      sourceScope: item.sourceScope,
    );
    if (existing == null) {
      await saveProgress(
        item,
        positionMs: 0,
        durationMs: 0,
        completed: watched,
      );
    } else {
      await _database.update(
        'watch_activity',
        {
          'completed': watched ? 1 : 0,
          'hidden_from_continue': watched ? 1 : 0,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where:
            'account_id = ? AND kind = ? AND media_id = ? AND source_scope = ?',
        whereArgs: [
          item.accountId,
          item.kind.name,
          item.mediaId,
          item.sourceScope,
        ],
      );
    }
  }

  @override
  Future<List<LibraryItem>> history(
    String accountId, {
    bool includeUnavailable = false,
  }) async {
    final rows = await _database.query(
      'watch_activity',
      where: includeUnavailable
          ? 'account_id = ?'
          : 'account_id = ? AND available = 1',
      whereArgs: [accountId],
      orderBy: 'updated_at DESC',
      limit: 5000,
    );
    return rows.map(_fromWatch).toList(growable: false);
  }

  @override
  Future<void> removeHistory(LibraryItem item) async {
    await _database.delete(
      'watch_activity',
      where:
          'account_id = ? AND kind = ? AND media_id = ? AND source_scope = ?',
      whereArgs: [
        item.accountId,
        item.kind.name,
        item.mediaId,
        item.sourceScope,
      ],
    );
  }

  @override
  Future<void> hideFromContinue(LibraryItem item) async {
    await _database.update(
      'watch_activity',
      {'hidden_from_continue': 1},
      where:
          'account_id = ? AND kind = ? AND media_id = ? AND source_scope = ?',
      whereArgs: [
        item.accountId,
        item.kind.name,
        item.mediaId,
        item.sourceScope,
      ],
    );
  }

  @override
  Future<void> clearHistory(String accountId) async {
    await _database.delete(
      'watch_activity',
      where: 'account_id = ?',
      whereArgs: [accountId],
    );
  }

  @override
  Future<void> deleteAccount(String accountId) async {
    await _database.transaction((txn) async {
      await txn.delete(
        'watch_activity',
        where: 'account_id = ?',
        whereArgs: [accountId],
      );
      await txn.delete(
        'favorites',
        where: 'account_id = ?',
        whereArgs: [accountId],
      );
    });
  }

  @override
  Future<void> reconcileAvailable(
    String accountId,
    LibraryKind kind,
    Iterable<String> ids, {
    String sourceScope = '',
  }) async {
    // Only compare locally tracked IDs. Avoid building an extra million-item
    // HashSet solely for validating a small personal library.
    final tracked = await _database.query(
      'watch_activity',
      columns: ['media_id', 'series_id'],
      where: 'account_id = ? AND kind = ? AND source_scope = ?',
      whereArgs: [accountId, kind.name, sourceScope],
    );
    final favorites = await _database.query(
      'favorites',
      columns: ['media_id'],
      where: 'account_id = ? AND kind = ? AND source_scope = ?',
      whereArgs: [accountId, kind.name, sourceScope],
    );
    final desired = <String>{
      ...tracked.map((row) => (row['series_id'] ?? row['media_id']) as String),
      ...favorites.map((row) => row['media_id'] as String),
    };
    if (desired.isEmpty) {
      return;
    }
    final existing = <String>{};
    for (final id in ids) {
      if (desired.contains(id)) existing.add(id);
      if (existing.length == desired.length) {
        break;
      }
    }
    await _database.transaction((txn) async {
      for (final id in desired) {
        final available = existing.contains(id) ? 1 : 0;
        await txn.update(
          'favorites',
          {'available': available},
          where: 'account_id = ? AND kind = ? AND media_id = ? AND source_scope = ?',
          whereArgs: [accountId, kind.name, id, sourceScope],
        );
        await txn.update(
          'watch_activity',
          {'available': available},
          where: 'account_id = ? AND kind = ? AND (media_id = ? OR series_id = ?) AND source_scope = ?',
          whereArgs: [accountId, kind.name, id, id, sourceScope],
        );
      }
    });
  }

  @override
  Future<void> close() async {
    final db = _db;
    _db = null;
    await db?.close();
  }
}
