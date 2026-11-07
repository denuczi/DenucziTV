import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/errors/app_exception.dart';
import 'package:denuczi_tv/features/downloads/data/http_byte_range.dart';

void main() {
  test('parses a valid single-part HTTP resume response', () {
    final range = HttpByteRange.parse(
      'bytes 100-999/1000',
      requestedStart: 100,
    );
    expect(range.start, 100);
    expect(range.length, 900);
    expect(range.total, 1000);
  });
  test('rejects mismatched offsets and invalid ranges', () {
    expect(
      () => HttpByteRange.parse('bytes 100-999/1000', requestedStart: 101),
      throwsA(isA<AppException>()),
    );
    expect(
      () => HttpByteRange.parse('bytes */1000', requestedStart: 100),
      throwsA(isA<AppException>()),
    );
    expect(
      () => HttpByteRange.parse('bytes 100-1000/1000', requestedStart: 100),
      throwsA(isA<AppException>()),
    );
  });
}
