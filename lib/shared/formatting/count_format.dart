final _groupingBoundary = RegExp(r'\B(?=(\d{3})+(?!\d))');

/// Formats catalog totals without rounding; English uses comma separators.
String formatItemCount(int value) => _groupDigits(value, ',');

/// Channel numbers always use dots, including with an English UI locale.
/// This is a visual channel identifier, not a locale-dependent total.
String formatChannelNumber(int value) => _groupDigits(value, '.');

String _groupDigits(int value, String separator) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final grouped = digits.replaceAllMapped(_groupingBoundary, (_) => separator);
  return negative ? '-$grouped' : grouped;
}
