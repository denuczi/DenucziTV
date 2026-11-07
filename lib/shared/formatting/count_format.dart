/// Formats counts without rounding away useful information about large catalogs.
/// English display strings use commas as thousands separators.
String formatItemCount(int value) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final grouped = digits.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return negative ? '-$grouped' : grouped;
}
