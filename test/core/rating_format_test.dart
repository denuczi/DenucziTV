import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/features/library/domain/rating_format.dart';

void main() {
  test('truncates numeric scores to compact labels without rounding', () {
    expect(formatCompactRating('6.307'), '6.3');
    expect(formatCompactRating('2.2332'), '2.2');
    expect(formatCompactRating('2212'), '2');
    expect(formatCompactRating('8.99'), '8.9');
    expect(formatCompactRating('7.0'), '7');
    expect(formatCompactRating('10'), '10');
    expect(formatCompactRating('10.0'), '10');
    expect(formatCompactRating('3,88'), '3.8');
  });

  test('rejects non-numeric values and preserves null', () {
    expect(formatCompactRating(null), isNull);
    expect(formatCompactRating(''), isNull);
    expect(formatCompactRating('Not rated'), isNull);
    expect(formatCompactRating('-1.2'), isNull);
    expect(formatCompactRating('Infinity'), isNull);
  });
}
