import 'dart:convert';
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

const movie = MediaEntry(
  id: '77',
  title: 'Sample movie',
  kind: LibraryKind.movies,
  containerExtension: 'mp4',
);

Future<DownloadStatus> waitForDownload(DownloadManager manager) async {
  for (var attempt = 0; attempt < 240; attempt++) {
    final status = manager.tasks.single.status;
    if (status == DownloadStatus.completed || status == DownloadStatus.failed) {
      return status;
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  fail('Timed out while waiting for the transfer to finish.');
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test(
    'restored partial resumes using byte range and keeps a single record',
    () async {
      final folder = await Directory.systemTemp.createTemp('osd-resume-');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final ranges = <String?>[];
      server.listen((request) async {
        ranges.add(request.headers.value('range'));
        expect(request.headers.value('if-range'), '"stable"');
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set('content-range', 'bytes 128-1023/1024');
        request.response.headers.set('etag', '"stable"');
        request.response.headers.contentLength = 896;
        request.response.add(List<int>.filled(896, 5));
        await request.response.close();
      });
      final preferences = SharedPreferencesAsync();
      final destination = '${folder.path}${Platform.pathSeparator}Saved.mp4';
      await File('$destination.part').writeAsBytes(List<int>.filled(128, 5));
      final existing = DownloadTask(
        id: 'saved-task',
        title: movie.title,
        destination: destination,
        status: DownloadStatus.interrupted,
        bytesReceived: 128,
        totalBytes: 1024,
        etag: '"stable"',
        mediaKey: DownloadManager.mediaKeyFor('account-1', movie),
      );
      await preferences.setString(
        'downloads.history.v1',
        jsonEncode([existing.toJson()]),
      );
      final network = NetworkClient();
      final manager = DownloadManager(network, SettingsStore(preferences));
      addTearDown(() async {
        manager.dispose();
        network.dispose();
        await server.close(force: true);
        await folder.delete(recursive: true);
      });
      await manager.initialize();
      await manager.setDirectory(folder.path);
      expect(manager.tasks.single.bytesReceived, 128);
      final count = await manager.enqueue(
        credentials: AccountCredentials(
          serverUrl: 'http://127.0.0.1:${server.port}',
          username: 'u',
          password: 'p',
          label: 'Test',
        ),
        api: XtreamApi(network),
        media: [movie],
        accountId: 'account-1',
      );
      expect(count, 1);
      expect(await waitForDownload(manager), DownloadStatus.completed);
      expect(ranges, ['bytes=128-']);
      expect(manager.tasks.single.id, 'saved-task');
      expect(await File(destination).length(), 1024);
      expect(await File('$destination.part').exists(), isFalse);
    },
  );

  test(
    'server ignoring Range preserves the partial until history removal',
    () async {
      final folder = await Directory.systemTemp.createTemp('osd-range-');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentLength = 1024;
        request.response.add(List<int>.filled(1024, 9));
        await request.response.close();
      });
      final preferences = SharedPreferencesAsync();
      final destination = '${folder.path}${Platform.pathSeparator}Saved.mp4';
      await File('$destination.part').writeAsBytes(List<int>.filled(128, 5));
      await preferences.setString(
        'downloads.history.v1',
        jsonEncode([
          DownloadTask(
            id: 'saved-task',
            title: movie.title,
            destination: destination,
            status: DownloadStatus.interrupted,
            bytesReceived: 128,
            totalBytes: 1024,
            etag: '"old"',
            mediaKey: DownloadManager.mediaKeyFor('account-1', movie),
          ).toJson(),
        ]),
      );
      final network = NetworkClient();
      final manager = DownloadManager(network, SettingsStore(preferences));
      addTearDown(() async {
        manager.dispose();
        network.dispose();
        await server.close(force: true);
        await folder.delete(recursive: true);
      });
      await manager.initialize();
      await manager.setDirectory(folder.path);
      await manager.enqueue(
        credentials: AccountCredentials(
          serverUrl: 'http://127.0.0.1:${server.port}',
          username: 'u',
          password: 'p',
          label: 'Test',
        ),
        api: XtreamApi(network),
        media: [movie],
        accountId: 'account-1',
      );
      expect(await waitForDownload(manager), DownloadStatus.failed);
      expect(manager.tasks.single.bytesReceived, 128);
      expect(
        await File('$destination.part').readAsBytes(),
        List<int>.filled(128, 5),
      );
      expect(await File(destination).exists(), isFalse);
      await manager.removeFromHistory('saved-task');
      expect(await File('$destination.part').exists(), isFalse);
      expect(manager.tasks, isEmpty);
    },
  );

  test('a provider without validators is checked before appending', () async {
    final folder = await Directory.systemTemp.createTemp('osd-no-tag-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final observed = <String?>[];
    server.listen((request) async {
      final range = request.headers.value('range');
      observed.add(range);
      request.response.statusCode = HttpStatus.partialContent;
      if (range == 'bytes=0-127') {
        request.response.headers.set('content-range', 'bytes 0-127/1024');
        request.response.headers.contentLength = 128;
        request.response.add(List<int>.filled(128, 5));
      } else if (range == 'bytes=128-') {
        request.response.headers.set('content-range', 'bytes 128-1023/1024');
        request.response.headers.contentLength = 896;
        request.response.add(List<int>.filled(896, 5));
      } else {
        request.response.statusCode = HttpStatus.badRequest;
      }
      await request.response.close();
    });
    final preferences = SharedPreferencesAsync();
    final destination = '${folder.path}${Platform.pathSeparator}Saved.mp4';
    await File('$destination.part').writeAsBytes(List<int>.filled(128, 5));
    await preferences.setString(
      'downloads.history.v1',
      jsonEncode([
        DownloadTask(
          id: 'old',
          title: movie.title,
          destination: destination,
          status: DownloadStatus.interrupted,
          bytesReceived: 128,
          totalBytes: 1024,
          mediaKey: DownloadManager.mediaKeyFor('account-1', movie),
        ).toJson(),
      ]),
    );
    final network = NetworkClient();
    final manager = DownloadManager(network, SettingsStore(preferences));
    addTearDown(() async {
      manager.dispose();
      network.dispose();
      await server.close(force: true);
      await folder.delete(recursive: true);
    });
    await manager.initialize();
    await manager.setDirectory(folder.path);
    await manager.enqueue(
      credentials: AccountCredentials(
        serverUrl: 'http://127.0.0.1:${server.port}',
        username: 'u',
        password: 'p',
        label: 'Test',
      ),
      api: XtreamApi(network),
      media: [movie],
      accountId: 'account-1',
    );
    expect(await waitForDownload(manager), DownloadStatus.completed);
    expect(observed, ['bytes=0-127', 'bytes=128-']);
    expect(await File(destination).length(), 1024);
  });

  test('transient 503 is retried without user intervention', () async {
    final folder = await Directory.systemTemp.createTemp('osd-auto-retry-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    server.listen((request) async {
      requests++;
      if (requests == 1) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
      } else {
        request.response.headers.contentLength = 128;
        request.response.headers.contentType = ContentType('video', 'mp4');
        request.response.add(List<int>.filled(128, 3));
      }
      await request.response.close();
    });
    final network = NetworkClient();
    final manager = DownloadManager(
      network,
      SettingsStore(SharedPreferencesAsync()),
    );
    addTearDown(() async {
      manager.dispose();
      network.dispose();
      await server.close(force: true);
      await folder.delete(recursive: true);
    });
    await manager.initialize();
    await manager.setDirectory(folder.path);
    await manager.enqueue(
      credentials: AccountCredentials(
        serverUrl: 'http://127.0.0.1:${server.port}',
        username: 'u',
        password: 'p',
        label: 'Test',
      ),
      api: XtreamApi(network),
      media: [movie],
      accountId: 'account-1',
    );
    expect(await waitForDownload(manager), DownloadStatus.completed);
    expect(requests, 2);
  });
}
