import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/features/downloads/domain/download_task.dart';

void main() {
  test(
    'retry resets nullable progress fields rather than retaining stale data',
    () {
      const task = DownloadTask(
        id: '1',
        title: 'Movie',
        destination: '/tmp/movie.mp4',
        status: DownloadStatus.failed,
        bytesReceived: 150,
        totalBytes: 1000,
        message: 'Network error',
      );
      final retried = task.copyWith(
        status: DownloadStatus.queued,
        bytesReceived: 0,
        totalBytes: null,
        message: null,
      );
      expect(retried.bytesReceived, 0);
      expect(retried.totalBytes, isNull);
      expect(retried.message, isNull);
      expect(retried.progress, isNull);
      expect(task.totalBytes, 1000);
    },
  );

  test('an omitted nullable value preserves previous metadata', () {
    const task = DownloadTask(
      id: '1',
      title: 'Movie',
      destination: '/tmp/movie.mp4',
      status: DownloadStatus.queued,
      totalBytes: 50,
    );
    expect(task.copyWith(bytesReceived: 10).totalBytes, 50);
  });
}
