import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/models/app_controller.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/core/storage/account_store.dart';
import 'package:denuczi_tv/core/storage/settings_store.dart';
import 'package:denuczi_tv/core/theme/app_theme.dart';
import 'package:denuczi_tv/features/library/data/xtream_api.dart';
import 'package:denuczi_tv/features/library/domain/media_models.dart';
import 'package:denuczi_tv/features/shell/presentation/desktop_shell.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  testWidgets('only the active library is selected after navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final network = NetworkClient();
    final preferences = SharedPreferencesAsync();
    final controller = AppController(
      network: network,
      api: XtreamApi(network),
      accounts: AccountStore(preferences, const FlutterSecureStorage()),
      settings: SettingsStore(preferences),
    );
    await controller.initialize();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>(
        create: (_) => controller,
        child: MaterialApp(theme: AppTheme.dark, home: const DesktopShell()),
      ),
    );
    await tester.pumpAndSettle();

    Semantics item(String label) =>
        tester.widget<Semantics>(find.byKey(Key('navigation-$label')));

    expect(item('my-library').properties.selected, isTrue);
    expect(item('live-tv').properties.selected, isFalse);
    expect(item('movies').properties.selected, isFalse);
    expect(item('series').properties.selected, isFalse);

    await tester.tap(find.byKey(const Key('navigation-series')));
    await tester.pumpAndSettle();
    expect(controller.kind, LibraryKind.series);
    expect(item('live-tv').properties.selected, isFalse);
    expect(item('movies').properties.selected, isFalse);
    expect(item('series').properties.selected, isTrue);
    final liveSurface = tester.widget<Material>(
      find
          .descendant(
            of: find.byKey(const Key('navigation-live-tv')),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(liveSurface.color, Colors.transparent);

    await tester.tap(find.byKey(const Key('navigation-movies')));
    await tester.pumpAndSettle();
    expect(controller.kind, LibraryKind.movies);
    expect(item('live-tv').properties.selected, isFalse);
    expect(item('movies').properties.selected, isTrue);
    expect(item('series').properties.selected, isFalse);
    expect(tester.takeException(), isNull);
  });
}
