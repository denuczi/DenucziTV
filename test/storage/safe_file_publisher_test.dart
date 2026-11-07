import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/storage/safe_file_publisher.dart';

void main() {
  test('existing destination is never overwritten', () async {
    final folder = await Directory.systemTemp.createTemp(
      'open-stream-publish-',
    );
    addTearDown(() => folder.delete(recursive: true));
    final temp = File('${folder.path}/temporary.part');
    final destination = File('${folder.path}/movie.mp4');
    await temp.writeAsString('new content');
    await destination.writeAsString('user data');

    await expectLater(
      const SafeFilePublisher().publish(temp, destination.path),
      throwsA(isA<FileSystemException>()),
    );
    expect(await destination.readAsString(), 'user data');
    expect(await temp.readAsString(), 'new content');
  });

  test('publishes only a complete flushed copy', () async {
    final folder = await Directory.systemTemp.createTemp(
      'open-stream-publish-',
    );
    addTearDown(() => folder.delete(recursive: true));
    final temp = File('${folder.path}/temporary.part');
    final destination = File('${folder.path}/movie.mp4');
    final bytes = List<int>.generate(16384, (index) => index % 256);
    await temp.writeAsBytes(bytes);

    await const SafeFilePublisher().publish(temp, destination.path);

    expect(await temp.exists(), isFalse);
    expect(await destination.readAsBytes(), bytes);
  });
}
