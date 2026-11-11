// Development-only preview. All release data is fictional; no GitHub requests,
// real preference writes, browser launches, or installer execution are performed.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:denuczi_tv/core/theme/app_theme.dart';
import 'package:denuczi_tv/features/updates/application/update_controller.dart';
import 'package:denuczi_tv/features/updates/data/update_preferences.dart';
import 'package:denuczi_tv/features/updates/presentation/update_dialog.dart';
import 'package:denuczi_tv/l10n/app_localizations.dart';
import 'package:denuczi_tv/l10n/l10n_ext.dart';

import '../test/updates/update_fixtures.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  runApp(
    ChangeNotifierProvider(
      create: (_) => UpdateController(
        api: FakeReleaseApi()
          ..releases = [
            releaseFixture(
              'v9.0.0',
              notes: """
# DenucziTV 9.0.0

## What's improved

- **Live TV:** faster channel switching.
- **Library:** better artwork caching.
- **Updates:** readable release notes with `Markdown` support.

## Compatibility

| Platform | Package |
| --- | --- |
| Windows x64 | Setup EXE |
| Debian x64 | DEB |

> This is a fictional preview. No installer is downloaded.

[View project repository](https://github.com/denuczi/DenucziTV)

```dart
final update = 'preview only';
```
""",
            ),
          ],
        preferences: UpdatePreferences(SharedPreferencesAsync()),
        openUrl: (_) async => false,
      ),
      child: const _PreviewApp(),
    ),
  );
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: const bool.fromEnvironment('UPDATE_PREVIEW_DARK')
        ? ThemeMode.dark
        : ThemeMode.light,
    locale: const Locale(
      String.fromEnvironment('UPDATE_PREVIEW_LANGUAGE', defaultValue: 'en'),
    ),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: FilledButton.icon(
            icon: const Icon(Icons.system_update_alt_rounded),
            label: Text(context.l10n.updatesCheck),
            onPressed: () async {
              final updates = context.read<UpdateController>();
              final result = await updates.checkManually();
              if (context.mounted && result.offersUpdate) {
                await showStableUpdateDialog(context, updates, result.release!);
              }
            },
          ),
        ),
      ),
    ),
  );
}
