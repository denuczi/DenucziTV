import '../errors/app_exception.dart';
import '../models/app_identity.dart';

/// Single source of truth for the HTTP User-Agent used across the application.
abstract final class UserAgent {
  static String get defaultValue => AppIdentity.defaultUserAgent;

  static String validate(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > 256) {
      throw const AppException('User-Agent must contain 1 to 256 characters.');
    }
    for (final unit in normalized.codeUnits) {
      if (unit < 0x20 || unit > 0x7E) {
        throw const AppException(
          'User-Agent must contain printable ASCII characters only.',
        );
      }
    }
    return normalized;
  }
}
