import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/app_localizations.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:media_kit/media_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'core/models/app_controller.dart';
import 'core/models/app_identity.dart';
import 'features/personal_library/application/personal_library_controller.dart';
import 'features/personal_library/data/sqlite_library_repository.dart';
import 'core/theme/app_theme.dart';
import 'core/network/network_client.dart';
import 'core/storage/account_store.dart';
import 'core/storage/settings_store.dart';
import 'features/library/data/xtream_api.dart';
import 'features/shell/presentation/desktop_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  try {
    final info = await PackageInfo.fromPlatform();
    AppIdentity.version = info.version;
  } catch (_) {
    // Widget tests and unsupported desktop shells use the source fallback.
  }
  try {
    await windowManager.ensureInitialized();
    await windowManager.setTitle(AppIdentity.name);
  } catch (_) {
    // A missing desktop integration must not prevent media playback.
  }

  final library = PersonalLibraryController(SqliteLibraryRepository());
  final network = NetworkClient();
  final preferences = SharedPreferencesAsync();
  final controller = AppController(
    network: network,
    api: XtreamApi(network),
    accounts: AccountStore(preferences, const FlutterSecureStorage()),
    settings: SettingsStore(preferences),
    personalLibrary: library,
  );

  await controller.initialize();
  runApp(
    ChangeNotifierProvider<AppController>.value(
      value: controller,
      child: const DenucziTVApp(),
    ),
  );
}

class DenucziTVApp extends StatelessWidget {
  const DenucziTVApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppIdentity.name,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: context.watch<AppController>().themeMode,
      locale: context.watch<AppController>().languageCode == null
          ? null
          : Locale(context.watch<AppController>().languageCode!),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      home: const DesktopShell(),
    );
  }
}
