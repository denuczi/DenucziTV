/// SemVer 2.0 precedence. Build metadata never changes update eligibility.
class SemanticVersion implements Comparable<SemanticVersion> {
  SemanticVersion._(this.core, this.preRelease, this.canonical);

  final List<BigInt> core;
  final List<String> preRelease;
  final String canonical;
  bool get isStable => preRelease.isEmpty;

  static SemanticVersion? tryParse(String value) {
    if (value.length > 128) return null;
    final text = value.startsWith('v') ? value.substring(1) : value;
    final match = RegExp(
      r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$',
    ).firstMatch(text);
    if (match == null || match.end != text.length) return null;
    final identifiers = match.group(4)?.split('.') ?? const <String>[];
    for (final identifier in identifiers) {
      if (RegExp(r'^[0-9]+$').hasMatch(identifier) &&
          identifier.length > 1 &&
          identifier.startsWith('0')) {
        return null;
      }
    }
    return SemanticVersion._(
      List.unmodifiable([
        for (var i = 1; i <= 3; i++) BigInt.parse(match.group(i)!),
      ]),
      List.unmodifiable(identifiers),
      text.split('+').first,
    );
  }

  @override
  int compareTo(SemanticVersion other) {
    for (var i = 0; i < 3; i++) {
      final order = core[i].compareTo(other.core[i]);
      if (order != 0) return order;
    }
    if (preRelease.isEmpty || other.preRelease.isEmpty) {
      return preRelease.isEmpty == other.preRelease.isEmpty
          ? 0
          : (isStable ? 1 : -1);
    }
    for (var i = 0; i < preRelease.length && i < other.preRelease.length; i++) {
      final left = preRelease[i];
      final right = other.preRelease[i];
      final leftNumber = RegExp(r'^[0-9]+$').hasMatch(left)
          ? BigInt.parse(left)
          : null;
      final rightNumber = RegExp(r'^[0-9]+$').hasMatch(right)
          ? BigInt.parse(right)
          : null;
      final order = leftNumber != null && rightNumber != null
          ? leftNumber.compareTo(rightNumber)
          : leftNumber != null
          ? -1
          : rightNumber != null
          ? 1
          : left.compareTo(right);
      if (order != 0) return order;
    }
    return preRelease.length.compareTo(other.preRelease.length);
  }
}
