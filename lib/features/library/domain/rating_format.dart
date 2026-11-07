/// Returns a compact provider score for UI labels.
///
/// The provider supplies ratings in different formats and with inconsistent
/// precision. Display at most the first integral digit plus one decimal, or
/// `10` for the top score. Extra digits are truncated, never rounded.
/// This is only a display policy; the source value is kept unchanged.
/// Non-numeric or negative values are treated as unavailable.
final _numericRating = RegExp(r'^\d+(?:[.,]\d+)?$');

String? formatCompactRating(String? raw) {
  if (raw == null) {
    return null;
  }
  final text = raw.trim();
  if (!_numericRating.hasMatch(text)) {
    return null;
  }

  final parts = text.replaceAll(',', '.').split('.');
  final integer = parts.first;
  if (integer == '10') {
    // A score of ten has no room for a fractional digit.
    return '10';
  }
  // Some providers return unscaled integer strings such as "2212". In the
  // compact UI these are deliberately shortened, not mathematically rounded.
  final digit = integer[0];
  if (parts.length == 1 || parts[1].isEmpty || parts[1][0] == '0') {
    return digit;
  }
  return '$digit.${parts[1][0]}';
}
