import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/shared/formatting/count_format.dart';

void main() {
  test('catalog counts remain exact and easy to scan', () {
    expect(formatItemCount(0), '0');
    expect(formatItemCount(48), '48');
    expect(formatItemCount(999), '999');
    expect(formatItemCount(1000), '1,000');
    expect(formatItemCount(30029), '30,029');
    expect(formatItemCount(1234567), '1,234,567');
    expect(formatItemCount(-5000), '-5,000');
  });
}
