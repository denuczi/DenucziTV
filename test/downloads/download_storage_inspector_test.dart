import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/features/downloads/data/download_storage_inspector.dart';
import 'package:denuczi_tv/features/downloads/domain/download_task.dart';

void main() {
  test(
    'counts real completed media and preserved partials, not missing files',
    () async {
      final folder = await Directory.systemTemp.createTemp('osd-storage-');
      addTearDown(() => folder.delete(recursive: true));
      final movie = File('${folder.path}/movie.mp4');
      final partial = File('${folder.path}/episode.mkv.part');
      await movie.writeAsBytes(List.filled(2048, 42));
      await partial.writeAsBytes(List.filled(256, 11));

      final tasks = [
        DownloadTask(
          id: 'movie',
          title: 'Movie',
          destination: movie.path,
          status: DownloadStatus.completed,
          bytesReceived: 2048,
        ),
        DownloadTask(
          id: 'duplicated',
          title: 'Movie copy in history',
          destination: movie.path,
          status: DownloadStatus.completed,
        ),
        DownloadTask(
          id: 'episode',
          title: 'Episode',
          destination: '${folder.path}/episode.mkv',
          status: DownloadStatus.cancelled,
          bytesReceived: 256,
        ),
        DownloadTask(
          id: 'missing',
          title: 'Missing',
          destination: '${folder.path}/missing.mp4',
          status: DownloadStatus.completed,
        ),
        DownloadTask(
          id: 'queued',
          title: 'Not written yet',
          destination: '${folder.path}/future.mp4',
          status: DownloadStatus.queued,
        ),
      ];
      final result = await const DownloadStorageInspector().inspect(tasks);
      expect(result.completedFiles, 1);
      expect(result.completedBytes, 2048);
      expect(result.partialFiles, 1);
      expect(result.partialBytes, 256);
      expect(result.unavailableFiles, 1);
      expect(result.totalBytes, 2304);
    },
  );

  test('empty download history has zero tracked usage', () async {
    final result = await const DownloadStorageInspector().inspect([]);
    expect(result.totalBytes, 0);
    expect(result.completedFiles, 0);
    expect(result.partialFiles, 0);
  });
}
