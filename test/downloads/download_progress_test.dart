import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/features/downloads/domain/download_task.dart';

void main() {
  test('download percent and remaining bytes use the reported size', () {
    const task = DownloadTask(
      id: 'a',
      title: 'Movie',
      destination: '/tmp/movie.mp4',
      status: DownloadStatus.downloading,
      bytesReceived: 15,
      totalBytes: 960,
    );
    expect(task.percentComplete, 1);
    expect(task.remainingBytes, 945);
  });

  test('unknown size has no invented percent or remaining size', () {
    const task = DownloadTask(
      id: 'b',
      title: 'Movie',
      destination: '/tmp/movie.mp4',
      status: DownloadStatus.downloading,
      bytesReceived: 15,
    );
    expect(task.percentComplete, isNull);
    expect(task.remainingBytes, isNull);
  });

  test('transient byte-count overshoot never shows above 100 percent', () {
    const task = DownloadTask(
      id: 'c',
      title: 'Movie',
      destination: '/tmp/movie.mp4',
      status: DownloadStatus.downloading,
      bytesReceived: 102,
      totalBytes: 100,
    );
    expect(task.percentComplete, 100);
    expect(task.remainingBytes, 0);
  });
}
