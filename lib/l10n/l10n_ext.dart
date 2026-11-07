import 'package:flutter/widgets.dart';

import 'app_localizations.dart';
import 'app_localizations_en.dart';

/// Localized UI messages from Flutter's generated ARB catalogs.
extension DenucziLocalizations on BuildContext {
  AppLocalizations get l10n =>
      AppLocalizations.of(this) ?? AppLocalizationsEn();
}
