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
import 'features/updates/application/update_controller.dart';
import 'features/updates/data/github_release_api.dart';
import 'features/updates/data/update_preferences.dart';
import 'features/updates/domain/update_channel.dart';
import 'features/updates/presentation/startup_update_listener.dart';
import 'features/personal_library/application/personal_library_controller.dart';
import 'features/personal_library/application/library_artwork_cache.dart';
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

  final network = NetworkClient();
  final library = PersonalLibraryController(
    SqliteLibraryRepository(),
    artworkCache: LibraryArtworkCache(network),
  );
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
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppController>.value(value: controller),
        // Store-managed builds must not create the GitHub updater at all, so
        // Settings cannot trigger a release request by accident.
        if (AppDistribution.usesGitHubUpdater)
          ChangeNotifierProvider<UpdateController>(
            create: (_) => UpdateController(
              api: GitHubReleaseApi(),
              preferences: UpdatePreferences(preferences),
            ),
          ),
      ],
      child: const DenucziTVApp(),
    ),
  );
}

class DenucziTVApp extends StatefulWidget {
  const DenucziTVApp({super.key});

  @override
  State<DenucziTVApp> createState() => _DenucziTVAppState();
}

class _DenucziTVAppState extends State<DenucziTVApp> {
  final _updateRoutes = UpdateRouteObserver();

  @override
  Widget build(BuildContext context) {
    final updates = context.watch<UpdateController?>();
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
      navigatorObservers: [if (updates != null) _updateRoutes],
      home: updates == null
          ? const DesktopShell()
          : StartupUpdateListener(
              updates: updates,
              routes: _updateRoutes,
              child: const DesktopShell(),
            ),
    );
  }
}
