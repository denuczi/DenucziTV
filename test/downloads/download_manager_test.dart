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
  // Keep HTTP transfer tests free of widget bindings: the Flutter test
  // binding replaces HttpClient requests with synthetic HTTP 400 responses.

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('sanitizes unsafe filenames and Windows reserved device names', () {
    expect(
      DownloadManager.safeFileName('../A:Movie\\Name?.mp4'),
      'A Movie Name .mp4',
    );
    expect(DownloadManager.safeFileName('CON'), 'Untitled media');
    expect(DownloadManager.safeFileName('   ...  '), 'Untitled media');
    expect(DownloadManager.safeFileName('T' * 140).length, 100);
  });

  test('streams direct media, uses global User-Agent, and keeps credentials out of history', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    String? receivedAgent;
    server.listen((request) async {
      receivedAgent = request.headers.value('user-agent');
      request.response.headers.contentType = ContentType('video', 'mp4');
      request.response.headers.contentLength = 8192;
      request.response.add(List<int>.filled(8192, 42));
      await request.response.close();
    });
    final folder = await Directory.systemTemp.createTemp('open-stream-test-');
    final preferences = SharedPreferencesAsync();
    final network = NetworkClient(userAgent: 'DesktopTest/1.0');
    final downloads = DownloadManager(network, SettingsStore(preferences));
    addTearDown(() async {
      downloads.dispose();
      network.dispose();
      await server.close(force: true);
      await folder.delete(recursive: true);
    });

    await downloads.initialize();
    await downloads.setDirectory(folder.path);
    final credentials = AccountCredentials(
      serverUrl: 'http://127.0.0.1:${server.port}',
      username: 'test-user',
      password: 'secret-pass',
      label: 'Test',
    );
    final count = await downloads.enqueue(
      credentials: credentials,
      api: XtreamApi(network),
      media: const [
        MediaEntry(
          id: '12',
          title: 'Example movie',
          kind: LibraryKind.movies,
          containerExtension: 'mp4',
        ),
      ],
    );
    expect(count, 1);
    for (
      var i = 0;
      i < 200 && downloads.tasks.first.status != DownloadStatus.completed;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
      if (downloads.tasks.first.status == DownloadStatus.failed) {
        fail('The direct download failed: ${downloads.tasks.first.message}');
      }
    }
    final task = downloads.tasks.single;
    expect(task.status, DownloadStatus.completed);
    expect(await File(task.destination).length(), 8192);
    expect(receivedAgent, 'DesktopTest/1.0');
    expect(await File('${task.destination}.part').exists(), isFalse);
    String rawHistory = '';
    for (var i = 0; i < 80; i++) {
      rawHistory = await preferences.getString('downloads.history.v1') ?? '';
      if (rawHistory.contains('completed')) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(rawHistory, contains('completed'));
    expect(rawHistory, isNot(contains('secret-pass')));
    expect(rawHistory, isNot(contains('test-user')));
  });

  test(
    'rejects a streaming manifest before writing a completed video',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.contentType = ContentType(
          'application',
          'vnd.apple.mpegurl',
        );
        request.response.write('#EXTM3U\n#EXT-X-VERSION:3');
        await request.response.close();
      });
      final folder = await Directory.systemTemp.createTemp('open-stream-test-');
      final network = NetworkClient();
      final downloads = DownloadManager(
        network,
        SettingsStore(SharedPreferencesAsync()),
      );
      addTearDown(() async {
        downloads.dispose();
        network.dispose();
        await server.close(force: true);
        await folder.delete(recursive: true);
      });
      await downloads.initialize();
      await downloads.setDirectory(folder.path);
      await downloads.enqueue(
        credentials: AccountCredentials(
          serverUrl: 'http://127.0.0.1:${server.port}',
          username: 'u',
          password: 'p',
          label: 'Test',
        ),
        api: XtreamApi(network),
        media: const [
          MediaEntry(
            id: '42',
            title: 'HLS movie',
            kind: LibraryKind.movies,
            containerExtension: 'mp4',
          ),
        ],
      );
      for (
        var i = 0;
        i < 200 && downloads.tasks.first.status != DownloadStatus.failed;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(downloads.tasks.single.status, DownloadStatus.failed);
      expect(await File(downloads.tasks.single.destination).exists(), isFalse);
    },
  );

  test(
    'season transfers reserve distinct filenames inside a sanitized subfolder',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.contentType = ContentType('video', 'mp4');
        request.response.add(List<int>.filled(128, 7));
        await request.response.close();
      });
      final directory = await Directory.systemTemp.createTemp(
        'open-stream-season-',
      );
      final network = NetworkClient();
      final manager = DownloadManager(
        network,
        SettingsStore(SharedPreferencesAsync()),
      );
      addTearDown(() async {
        manager.dispose();
        network.dispose();
        await server.close(force: true);
        await directory.delete(recursive: true);
      });

      await manager.initialize();
      await manager.setDirectory(directory.path);
      await manager.enqueue(
        credentials: AccountCredentials(
          serverUrl: 'http://127.0.0.1:${server.port}',
          username: 'u',
          password: 'p',
          label: 'Test',
        ),
        api: XtreamApi(network),
        subfolder: 'Example:Series / Season 01',
        media: const [
          MediaEntry(
            id: '11',
            title: 'Pilot',
            kind: LibraryKind.series,
            seasonNumber: 1,
            episodeNumber: 1,
            containerExtension: 'mp4',
          ),
          MediaEntry(
            id: '12',
            title: 'Pilot',
            kind: LibraryKind.series,
            seasonNumber: 1,
            episodeNumber: 1,
            containerExtension: 'mp4',
          ),
        ],
      );
      final paths = manager.tasks.map((item) => item.destination).toList();
      expect(paths.toSet().length, 2);
      expect(
        paths.every((path) => path.contains('Example Series Season 01')),
        isTrue,
      );
      for (var i = 0; i < 200; i++) {
        if (manager.tasks.every(
          (item) => item.status == DownloadStatus.completed,
        )) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(
        manager.tasks.every((item) => item.status == DownloadStatus.completed),
        isTrue,
      );
      for (final path in paths) {
        expect(await File(path).length(), 128);
      }
    },
  );
}
