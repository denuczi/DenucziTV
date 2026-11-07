import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/models/account.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/core/storage/settings_store.dart';
import 'package:denuczi_tv/features/downloads/data/download_manager.dart';
import 'package:denuczi_tv/features/downloads/domain/download_task.dart';
import 'package:denuczi_tv/features/library/data/xtream_api.dart';
import 'package:denuczi_tv/features/library/domain/media_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('concurrent requests reserve the same movie only once', () async {
    final releaseResponse = Completer<void>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await releaseResponse.future;
      request.response.headers.contentType = ContentType('video', 'mp4');
      request.response.add(List<int>.filled(256, 42));
      await request.response.close();
    });
    final folder = await Directory.systemTemp.createTemp('open-stream-dedupe-');
    final network = NetworkClient();
    final manager = DownloadManager(
      network,
      SettingsStore(SharedPreferencesAsync()),
    );
    addTearDown(() async {
      releaseResponse.completeIfPending();
      manager.dispose();
      network.dispose();
      await server.close(force: true);
      await folder.delete(recursive: true);
    });
    await manager.initialize();
    await manager.setDirectory(folder.path);
    final credentials = AccountCredentials(
      serverUrl: 'http://127.0.0.1:${server.port}',
      username: 'user',
      password: 'secret',
      label: 'Test',
    );
    final api = XtreamApi(network);
    const movie = MediaEntry(
      id: '42',
      title: 'Movie',
      kind: LibraryKind.movies,
      containerExtension: 'mp4',
    );
    final first = manager.enqueue(
      credentials: credentials,
      api: api,
      accountId: 'account-a',
      media: [movie],
    );
    final second = manager.enqueue(
      credentials: credentials,
      api: api,
      accountId: 'account-a',
      media: [movie],
    );
    expect(await Future.wait([first, second]), [1, 0]);
    expect(manager.tasks.length, 1);
    expect(manager.taskForMedia('account-a', movie), isNotNull);
    expect(manager.taskForMedia('account-b', movie), isNull);

    releaseResponse.complete();
    for (
      var i = 0;
      i < 200 && manager.tasks.single.status != DownloadStatus.completed;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(manager.tasks.single.status, DownloadStatus.completed);
    expect(
      await manager.enqueue(
        credentials: credentials,
        api: api,
        accountId: 'account-a',
        media: [movie],
      ),
      0,
    );
    expect(manager.tasks.single.mediaKey, isNot(contains('secret')));
    expect(manager.tasks.single.toJson()['mediaKey'], isNotNull);
  });

  test(
    'duplicate season entries are skipped before writing destinations',
    () async {
      final releaseResponse = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        await releaseResponse.future;
        request.response.add(List<int>.filled(16, 1));
        await request.response.close();
      });
      final folder = await Directory.systemTemp.createTemp(
        'open-stream-season-dedupe-',
      );
      final network = NetworkClient();
      final manager = DownloadManager(
        network,
        SettingsStore(SharedPreferencesAsync()),
      );
      addTearDown(() async {
        releaseResponse.completeIfPending();
        manager.dispose();
        network.dispose();
        await server.close(force: true);
        await folder.delete(recursive: true);
      });
      await manager.initialize();
      await manager.setDirectory(folder.path);
      final credentials = AccountCredentials(
        serverUrl: 'http://127.0.0.1:${server.port}',
        username: 'u',
        password: 'p',
        label: 'Test',
      );
      const episode = MediaEntry(
        id: '1',
        title: 'Pilot',
        kind: LibraryKind.series,
        containerExtension: 'mp4',
        seasonNumber: 1,
        episodeNumber: 1,
      );
      final queued = await manager.enqueue(
        credentials: credentials,
        api: XtreamApi(network),
        accountId: 'a',
        media: [episode, episode],
        subfolder: 'Season 1',
      );
      expect(queued, 1);
      expect(manager.tasks, hasLength(1));
      releaseResponse.complete();
    },
  );
}

extension on Completer<void> {
  void completeIfPending() {
    if (!isCompleted) {
      complete();
    }
  }
}
