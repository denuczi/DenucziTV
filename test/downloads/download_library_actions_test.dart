import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/errors/app_exception.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/core/platform/desktop_file_opener.dart';
import 'package:denuczi_tv/core/storage/settings_store.dart';
import 'package:denuczi_tv/features/downloads/data/download_manager.dart';
import 'package:denuczi_tv/features/downloads/domain/download_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('removing one history entry preserves the downloaded file', () async {
    final folder = await Directory.systemTemp.createTemp(
      'open-stream-history-',
    );
    final media = File('${folder.path}${Platform.pathSeparator}Movie.mp4');
    await media.writeAsBytes([1, 2, 3]);
    final prefs = SharedPreferencesAsync();
    await prefs.setString(
      'downloads.history.v1',
      _history([
        DownloadTask(
          id: 'one',
          title: 'Movie',
          destination: media.path,
          status: DownloadStatus.completed,
        ),
      ]),
    );
    final network = NetworkClient();
    final manager = DownloadManager(network, SettingsStore(prefs));
    addTearDown(() async {
      manager.dispose();
      network.dispose();
      await folder.delete(recursive: true);
    });
    await manager.initialize();
    await manager.removeFromHistory('one');
    expect(manager.tasks, isEmpty);
    expect(await media.exists(), isTrue);
    expect(await prefs.getString('downloads.history.v1'), '[]');
  });

  test(
    'clear history removes terminal records without deleting files',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'open-stream-history-',
      );
      final media = File('${folder.path}${Platform.pathSeparator}Movie.mp4');
      await media.writeAsBytes([1, 2, 3]);
      final prefs = SharedPreferencesAsync();
      await prefs.setString(
        'downloads.history.v1',
        _history([
          DownloadTask(
            id: 'completed',
            title: 'Movie',
            destination: media.path,
            status: DownloadStatus.completed,
          ),
          DownloadTask(
            id: 'failed',
            title: 'Broken',
            destination: '${folder.path}/none.mp4',
            status: DownloadStatus.failed,
          ),
        ]),
      );
      final network = NetworkClient();
      final manager = DownloadManager(network, SettingsStore(prefs));
      addTearDown(() async {
        manager.dispose();
        network.dispose();
        await folder.delete(recursive: true);
      });
      await manager.initialize();
      expect(await manager.clearHistory(), 2);
      expect(manager.tasks, isEmpty);
      expect(await media.exists(), isTrue);
    },
  );

  test(
    'delete downloaded file removes only the selected completed file',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'open-stream-deletion-',
      );
      final media = File('${folder.path}${Platform.pathSeparator}Delete.mp4');
      final preserved = File('${folder.path}${Platform.pathSeparator}Keep.mp4');
      await media.writeAsBytes([1, 2]);
      await preserved.writeAsBytes([9]);
      final prefs = SharedPreferencesAsync();
      await prefs.setString(
        'downloads.history.v1',
        _history([
          DownloadTask(
            id: 'delete',
            title: 'Delete',
            destination: media.path,
            status: DownloadStatus.completed,
          ),
          DownloadTask(
            id: 'keep',
            title: 'Keep',
            destination: preserved.path,
            status: DownloadStatus.completed,
          ),
        ]),
      );
      final network = NetworkClient();
      final manager = DownloadManager(network, SettingsStore(prefs));
      addTearDown(() async {
        manager.dispose();
        network.dispose();
        await folder.delete(recursive: true);
      });
      await manager.initialize();
      await manager.deleteDownloadedFile('delete');
      expect(await media.exists(), isFalse);
      expect(await preserved.exists(), isTrue);
      expect(manager.tasks.map((entry) => entry.id), ['keep']);
    },
  );

  test('refuses to delete missing files or directory paths', () async {
    final folder = await Directory.systemTemp.createTemp(
      'open-stream-deletion-',
    );
    final prefs = SharedPreferencesAsync();
    await prefs.setString(
      'downloads.history.v1',
      _history([
        DownloadTask(
          id: 'missing',
          title: 'Missing',
          destination: '${folder.path}/missing.mp4',
          status: DownloadStatus.completed,
        ),
        DownloadTask(
          id: 'directory',
          title: 'Folder',
          destination: folder.path,
          status: DownloadStatus.completed,
        ),
      ]),
    );
    final network = NetworkClient();
    final manager = DownloadManager(network, SettingsStore(prefs));
    addTearDown(() async {
      manager.dispose();
      network.dispose();
      await folder.delete(recursive: true);
    });
    await manager.initialize();
    await expectLater(
      manager.deleteDownloadedFile('missing'),
      throwsA(isA<AppException>()),
    );
    await expectLater(
      manager.deleteDownloadedFile('directory'),
      throwsA(isA<AppException>()),
    );
    expect(await folder.exists(), isTrue);
    expect(manager.tasks.length, 2);
  });

  test('desktop file opener reports missing files and folders', () async {
    const opener = DesktopFileOpener();
    final root = await Directory.systemTemp.createTemp('open-stream-open-');
    addTearDown(() => root.delete(recursive: true));
    final missing = '${root.path}/missing/subdirectory/video.mkv';
    await expectLater(opener.play(missing), throwsA(isA<AppException>()));
    await expectLater(
      opener.openContainingFolder(missing),
      throwsA(isA<AppException>()),
    );
  });
}

String _history(List<DownloadTask> tasks) =>
    jsonEncode(tasks.map((entry) => entry.toJson()).toList());
