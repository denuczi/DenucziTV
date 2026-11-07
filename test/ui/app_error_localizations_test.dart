import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/l10n/app_error_localizations.dart';
import 'package:denuczi_tv/l10n/app_localizations.dart';

void main() {
  testWidgets('known controller and HTTP errors use Spanish UI messages', (
    tester,
  ) async {
    late BuildContext localizedContext;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) {
            localizedContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      localizeAppError(localizedContext, 'The catalog could not be loaded.'),
      'No se pudo cargar el catálogo.',
    );
    expect(
      localizeAppError(localizedContext, 'The server returned HTTP 401.'),
      'El servidor devolvió el código HTTP 401.',
    );
    expect(
      localizeAppError(
        localizedContext,
        'Network preferences could not be restored. Language preferences could not be restored.',
      ),
      'No se pudieron restaurar las preferencias de red. No se pudieron restaurar las preferencias de idioma.',
    );
    expect(
      localizeAppError(localizedContext, 'Provider-specific message'),
      'Provider-specific message',
    );
  });
}
