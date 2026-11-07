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
import 'package:denuczi_tv/features/library/presentation/media_details_dialog.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  Future<void> mountDetails(
    WidgetTester tester, {
    required Future<MediaDetails> Function() detailsLoader,
    String? catalogSynopsis,
  }) async {
    tester.view.physicalSize = const Size(1000, 800);
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
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: MaterialApp(
          home: Scaffold(
            body: MediaDetailsDialog(
              entry: MediaEntry(
                id: 'movie-1',
                title: 'Example movie',
                kind: LibraryKind.movies,
                plot: catalogSynopsis,
              ),
              detailsLoader: detailsLoader,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('pending metadata never claims the synopsis is unavailable', (
    tester,
  ) async {
    final pending = Completer<MediaDetails>();
    await mountDetails(tester, detailsLoader: () => pending.future);

    expect(find.text('Loading synopsis…'), findsOneWidget);
    expect(find.text('No synopsis available.'), findsNothing);
    pending.complete(const MediaDetails(plot: 'Synopsis from provider'));
    await tester.pumpAndSettle();
    expect(find.text('Synopsis from provider'), findsOneWidget);
    expect(find.text('Loading synopsis…'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing synopsis is only reported after a successful response', (
    tester,
  ) async {
    final pending = Completer<MediaDetails>();
    await mountDetails(tester, detailsLoader: () => pending.future);
    expect(find.text('No synopsis available.'), findsNothing);
    pending.complete(const MediaDetails());
    await tester.pumpAndSettle();
    expect(find.text('No synopsis available.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed metadata can be retried without losing the dialog', (
    tester,
  ) async {
    final firstAttempt = Completer<MediaDetails>();
    final retryAttempt = Completer<MediaDetails>();
    var attempts = 0;
    await mountDetails(
      tester,
      detailsLoader: () {
        attempts += 1;
        return attempts == 1 ? firstAttempt.future : retryAttempt.future;
      },
    );
    firstAttempt.completeError(StateError('Temporary provider outage'));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not load additional movie details.'),
      findsOneWidget,
    );
    expect(find.text('Synopsis could not be loaded.'), findsOneWidget);
    expect(find.text('No synopsis available.'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(attempts, 2);
    expect(find.text('Loading synopsis…'), findsOneWidget);
    expect(find.text('Could not load additional movie details.'), findsNothing);

    retryAttempt.complete(const MediaDetails(plot: 'Recovered synopsis'));
    await tester.pumpAndSettle();
    expect(find.text('Recovered synopsis'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a synchronous provider error during retry stays recoverable', (
    tester,
  ) async {
    final firstAttempt = Completer<MediaDetails>();
    var attempts = 0;
    await mountDetails(
      tester,
      detailsLoader: () {
        attempts += 1;
        if (attempts == 1) {
          return firstAttempt.future;
        }
        if (attempts == 2) {
          throw StateError('Unexpected synchronous provider failure');
        }
        return Future.value(const MediaDetails(plot: 'Recovered after retry'));
      },
    );

    firstAttempt.completeError(StateError('Temporary provider outage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(
      find.text('Could not load additional movie details.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(attempts, 3);
    expect(find.text('Recovered after retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a synchronous failure during initial load can be retried', (
    tester,
  ) async {
    var attempts = 0;
    await mountDetails(
      tester,
      detailsLoader: () {
        attempts += 1;
        if (attempts == 1) {
          throw StateError('Synchronous failure on first load');
        }
        return Future.value(
          const MediaDetails(plot: 'Recovered on initial-load retry'),
        );
      },
    );

    await tester.pumpAndSettle();
    expect(
      find.text('Could not load additional movie details.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('Recovered on initial-load retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('catalog synopsis stays visible during a metadata request', (
    tester,
  ) async {
    final pending = Completer<MediaDetails>();
    await mountDetails(
      tester,
      detailsLoader: () => pending.future,
      catalogSynopsis: 'Synopsis already provided in the catalog',
    );
    expect(
      find.text('Synopsis already provided in the catalog'),
      findsOneWidget,
    );
    expect(find.text('No synopsis available.'), findsNothing);
    pending.complete(const MediaDetails(plot: '   '));
    await tester.pumpAndSettle();
    expect(
      find.text('Synopsis already provided in the catalog'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
