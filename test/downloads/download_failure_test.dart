import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/models/account.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/core/storage/safe_file_publisher.dart';
import 'package:denuczi_tv/core/storage/settings_store.dart';
import 'package:denuczi_tv/features/downloads/data/download_manager.dart';
import 'package:denuczi_tv/features/downloads/domain/download_task.dart';
import 'package:denuczi_tv/features/library/data/xtream_api.dart';
import 'package:denuczi_tv/features/library/domain/media_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class RacingPublisher extends SafeFilePublisher {
  const RacingPublisher();

  @override
  Future<void> publish(File source, String destination) async {
    // Simulate another process creating a file after the transfer finishes.
    await File(destination).writeAsString('other application data');
    await super.publish(source, destination);
  }
}

Future<void> waitForStatus(
  DownloadManager manager,
  DownloadStatus expected,
) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (manager.tasks.single.status == expected) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('Download did not reach $expected: ${manager.tasks.single.status}');
}

void main() {
  // Keep HTTP transfer tests free of widget bindings: the Flutter test
  // binding replaces HttpClient requests with synthetic HTTP 400 responses.
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test(
    'another process can create the destination without being overwritten',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.contentType = ContentType('video', 'mp4');
        request.response.add(List<int>.filled(128, 0x42));
        await request.response.close();
      });
      final directory = await Directory.systemTemp.createTemp(
        'open-stream-race-',
      );
      final network = NetworkClient();
      final manager = DownloadManager(
        network,
        SettingsStore(SharedPreferencesAsync()),
        publisher: const RacingPublisher(),
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
        media: const [
          MediaEntry(
            id: '9',
            title: 'Race',
            kind: LibraryKind.movies,
            containerExtension: 'mp4',
          ),
        ],
      );
      await waitForStatus(manager, DownloadStatus.failed);
      expect(
        await File(manager.tasks.single.destination).readAsString(),
        'other application data',
      );
    },
  );

  test(
    'follows four relative HTTP redirects and preserves User-Agent',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final visited = <String>[];
      final agents = <String?>[];
      server.listen((request) async {
        visited.add(request.uri.path);
        agents.add(request.headers.value('user-agent'));
        final step = request.uri.path.startsWith('/hop/')
            ? int.tryParse(request.uri.path.split('/').last) ?? 0
            : 0;
        if (step < 4) {
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set(
            HttpHeaders.locationHeader,
            '/hop/${step + 1}',
          );
        } else {
          request.response.headers.contentType = ContentType('video', 'mp4');
          request.response.add(List<int>.filled(256, 0x42));
        }
        await request.response.close();
      });
      final directory = await Directory.systemTemp.createTemp(
        'open-stream-redirect-',
      );
      final network = NetworkClient(userAgent: 'RedirectTest/1.0');
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
        media: const [
          MediaEntry(
            id: '9',
            title: 'Redirect',
            kind: LibraryKind.movies,
            containerExtension: 'mp4',
          ),
        ],
      );
      await waitForStatus(manager, DownloadStatus.completed);
      expect(visited, hasLength(5));
      expect(visited.last, '/hop/4');
      expect(agents, everyElement('RedirectTest/1.0'));
      expect(await File(manager.tasks.single.destination).length(), 256);
    },
  );

  test('rejects a fifth redirect and leaves no completed file', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final step = request.uri.path.startsWith('/hop/')
          ? int.tryParse(request.uri.path.split('/').last) ?? 0
          : 0;
      request.response.statusCode = HttpStatus.temporaryRedirect;
      request.response.headers.set(
        HttpHeaders.locationHeader,
        '/hop/${step + 1}',
      );
      await request.response.close();
    });
    final directory = await Directory.systemTemp.createTemp(
      'open-stream-redirect-limit-',
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
      media: const [
        MediaEntry(
          id: '9',
          title: 'Redirect limit',
          kind: LibraryKind.movies,
          containerExtension: 'mp4',
        ),
      ],
    );
    await waitForStatus(manager, DownloadStatus.failed);
    expect(manager.tasks.single.message, contains('four-redirect limit'));
    expect(await File(manager.tasks.single.destination).exists(), isFalse);
  });

  test('rejects non-HTTP redirect targets', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.statusCode = HttpStatus.movedPermanently;
      request.response.headers.set(
        HttpHeaders.locationHeader,
        'file:///etc/passwd',
      );
      await request.response.close();
    });
    final directory = await Directory.systemTemp.createTemp(
      'open-stream-redirect-scheme-',
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
      media: const [
        MediaEntry(
          id: '9',
          title: 'Invalid redirect',
          kind: LibraryKind.movies,
          containerExtension: 'mp4',
        ),
      ],
    );
    await waitForStatus(manager, DownloadStatus.failed);
    expect(manager.tasks.single.message, contains('unsafe download URL'));
    expect(await File(manager.tasks.single.destination).exists(), isFalse);
  });

  test(
    'absolute redirect to a CDN does not forward the source credentials',
    () async {
      final cdn = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      Uri? requestedCdnUrl;
      String? cdnAgent;
      String? cdnAuthorization;
      cdn.listen((request) async {
        requestedCdnUrl = request.uri;
        cdnAgent = request.headers.value('user-agent');
        cdnAuthorization = request.headers.value('authorization');
        request.response.headers.contentType = ContentType('video', 'mp4');
        request.response.add(List<int>.filled(96, 0x42));
        await request.response.close();
      });
      final provider = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      provider.listen((request) async {
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(
          HttpHeaders.locationHeader,
          'http://127.0.0.1:${cdn.port}/video/download.mp4?ticket=cdn',
        );
        await request.response.close();
      });
      final directory = await Directory.systemTemp.createTemp(
        'open-stream-cdn-',
      );
      final network = NetworkClient(userAgent: 'CDNTest/2.0');
      final manager = DownloadManager(
        network,
        SettingsStore(SharedPreferencesAsync()),
      );
      addTearDown(() async {
        manager.dispose();
        network.dispose();
        await provider.close(force: true);
        await cdn.close(force: true);
        await directory.delete(recursive: true);
      });
      await manager.initialize();
      await manager.setDirectory(directory.path);
      await manager.enqueue(
        credentials: AccountCredentials(
          serverUrl: 'http://127.0.0.1:${provider.port}',
          username: 'confidential-user',
          password: 'confidential-pass',
          label: 'Test',
        ),
        api: XtreamApi(network),
        media: const [
          MediaEntry(
            id: '9',
            title: 'CDN transfer',
            kind: LibraryKind.movies,
            containerExtension: 'mp4',
          ),
        ],
      );
      await waitForStatus(manager, DownloadStatus.completed);
      expect(requestedCdnUrl?.path, '/video/download.mp4');
      expect(requestedCdnUrl?.query, 'ticket=cdn');
      expect(requestedCdnUrl.toString(), isNot(contains('confidential-pass')));
      expect(requestedCdnUrl.toString(), isNot(contains('confidential-user')));
      expect(cdnAgent, 'CDNTest/2.0');
      expect(cdnAuthorization, isNull);
    },
  );
}
