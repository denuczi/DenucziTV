/// Public application identity. Version comes from the installed package.
///
/// This fallback is used by widget tests that do not initialize platform
/// plugins. Release builds read the version from pubspec via PackageInfo.
abstract final class AppIdentity {
  static const name = 'DenucziTV';
  static const author = 'Ignacio Sanguina';
  static const repository = 'https://github.com/denuczi/DenucziTV';
  static String version = '0.5.3';
  static String get defaultUserAgent => 'DenucziTV/$version';
}
