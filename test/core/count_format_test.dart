import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/shared/formatting/count_format.dart';

void main() {
  test('channel numbers use dot groups without rounding', () {
    expect(formatChannelNumber(1), '1');
    expect(formatChannelNumber(10), '10');
    expect(formatChannelNumber(999), '999');
    expect(formatChannelNumber(1000), '1.000');
    expect(formatChannelNumber(3000), '3.000');
    expect(formatChannelNumber(1000000), '1.000.000');
    expect(
      formatChannelNumber(9223372036854775807),
      '9.223.372.036.854.775.807',
    );
  });

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
