import '../../../core/errors/app_exception.dart';

/// A single-part RFC 9110 Content-Range (multipart responses are unsupported).
final class HttpByteRange {
  const HttpByteRange({
    required this.start,
    required this.end,
    required this.total,
  });

  final int start;
  final int end;
  final int total;

  int get length => end - start + 1;

  static HttpByteRange parse(String? value, {required int requestedStart}) {
    final match = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$')
        .firstMatch(value?.trim() ?? '');
    if (match == null) {
      throw const AppException('The server returned an invalid Content-Range.');
    }
    final start = int.tryParse(match.group(1)!);
    final end = int.tryParse(match.group(2)!);
    final total = int.tryParse(match.group(3)!);
    if (start == null ||
        end == null ||
        total == null ||
        start != requestedStart ||
        end < start ||
        total <= end) {
      throw const AppException(
        'The resumed media range does not match the saved file.',
      );
    }
    return HttpByteRange(start: start, end: end, total: total);
  }
}
