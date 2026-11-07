/// Explicitly supported UI languages. New locales require an ARB translation
/// and one entry here; presentation and preference validation share this list.
class AppLanguageOption {
  const AppLanguageOption(this.code, this.nativeName);

  final String code;
  final String nativeName;
}

abstract final class AppLanguages {
  static const options = <AppLanguageOption>[
    AppLanguageOption('en', 'English'),
    AppLanguageOption('es', 'Español'),
  ];

  static bool supports(String code) =>
      options.any((option) => option.code == code);
}
