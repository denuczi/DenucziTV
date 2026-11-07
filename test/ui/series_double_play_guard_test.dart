import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/models/app_controller.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/core/storage/account_store.dart';
import 'package:denuczi_tv/core/storage/settings_store.dart';
import 'package:denuczi_tv/features/library/data/xtream_api.dart';
import 'package:denuczi_tv/features/library/domain/media_models.dart';
import 'package:denuczi_tv/features/library/presentation/series_dialog.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  testWidgets('two rapid episode taps open only one player', (tester) async {
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final network = NetworkClient();
    final preferences = SharedPreferencesAsync();
    final app = AppController(
      network: network,
      api: XtreamApi(network),
      accounts: AccountStore(preferences, const FlutterSecureStorage()),
      settings: SettingsStore(preferences),
    );
    addTearDown(app.dispose);
    const episode = MediaEntry(
      id: 'ep-1',
      title: 'Pilot',
      kind: LibraryKind.series,
      seasonNumber: 1,
      episodeNumber: 1,
    );
    const series = MediaEntry(
      id: 'series-1',
      title: 'Example',
      kind: LibraryKind.series,
    );
    const details = SeriesDetails(
      episodesBySeason: {
        1: [episode],
      },
    );
    final pending = Completer<void>();
    var launches = 0;
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: app,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SeriesDialog(
                series: series,
                detailsLoader: () async => details,
                playbackLauncher: (context, queue, index) {
                  launches++;
                  return pending.future;
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final play = find.byKey(const Key('episode-0'));
    expect(play, findsOneWidget);
    await tester.tap(play);
    await tester.tap(play);
    expect(launches, 1);
    pending.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
