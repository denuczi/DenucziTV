import 'package:denuczi_tv/core/models/account.dart';
import 'package:denuczi_tv/core/models/app_controller.dart';
import 'package:denuczi_tv/core/models/protected_access_grant.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/core/storage/account_store.dart';
import 'package:denuczi_tv/core/storage/settings_store.dart';
import 'package:denuczi_tv/core/theme/app_theme.dart';
import 'package:denuczi_tv/features/library/data/xtream_api.dart';
import 'package:denuczi_tv/features/library/domain/media_models.dart';
import 'package:denuczi_tv/features/library/presentation/download_action_button.dart';
import 'package:denuczi_tv/features/library/presentation/media_artwork.dart';
import 'package:denuczi_tv/features/library/presentation/series_dialog.dart';
import 'package:denuczi_tv/features/personal_library/application/personal_library_controller.dart';
import 'package:denuczi_tv/features/personal_library/data/library_repository.dart';
import 'package:denuczi_tv/features/personal_library/domain/library_item.dart';
import 'package:denuczi_tv/features/personal_library/presentation/my_library_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _UnusedRepository implements LibraryRepository {
  @override
  Future<List<LibraryItem>> favorites(
    String accountId, {
    bool includeUnavailable = false,
  }) async => const [];

  @override
  Future<List<LibraryItem>> history(
    String accountId, {
    bool includeUnavailable = false,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryLibrary extends PersonalLibraryController {
  _MemoryLibrary() : super(_UnusedRepository());

  @override
  Future<void> close() async {}

  @override
  Future<void> markWatched(LibraryItem item, bool watched) async {
    history = [
      LibraryItem(
        accountId: item.accountId,
        mediaId: item.mediaId,
        kind: item.kind,
        title: item.title,
        sourceScope: item.sourceScope,
        completed: watched,
      ),
    ];
    notifyListeners();
  }
}

class _CoverApi extends XtreamApi {
  _CoverApi(super.network);

  @override
  Future<MediaDetails> movieDetails(
    AccountCredentials credentials,
    String id,
  ) async =>
      const MediaDetails(imageUrl: 'https://images.example/current-cover.jpg');
}

class _ConnectedApp extends AppController {
  _ConnectedApp(NetworkClient network, _MemoryLibrary library)
    : super(
        network: network,
        api: _CoverApi(network),
        accounts: AccountStore(
          SharedPreferencesAsync(),
          const FlutterSecureStorage(),
        ),
        settings: SettingsStore(SharedPreferencesAsync()),
        personalLibrary: library,
      ) {
    activeAccount = const Account(
      id: 'account',
      label: 'Test',
      serverUrl: '',
      username: '',
      connectionType: AccountConnectionType.protectedSingleLink,
    );
    showDownloadControls = true;
  }

  final grant = ProtectedAccessGrant(accountId: 'account');
  late final login = AccountCredentials(
    serverUrl: 'https://provider.example',
    username: 'viewer',
    password: 'synthetic',
    label: 'Test',
    protected: true,
    sourceScope: 'current',
    accessGrant: grant,
  );

  @override
  AccountCredentials get credentials => login;

  @override
  void dispose() {
    grant.dispose();
    super.dispose();
  }
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  for (final theme in [AppTheme.light, AppTheme.dark]) {
    testWidgets(
      'episode action spacing and watched colors in ${theme.brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(1100, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final library = _MemoryLibrary();
        final app = _ConnectedApp(NetworkClient(), library);
        addTearDown(app.dispose);
        await tester.pumpWidget(
          ChangeNotifierProvider<AppController>.value(
            value: app,
            child: MaterialApp(
              theme: theme,
              home: Scaffold(
                body: SeriesDialog(
                  series: const MediaEntry(
                    id: 'series',
                    title: 'Series',
                    kind: LibraryKind.series,
                    sourceScope: 'current',
                  ),
                  detailsLoader: () async => const SeriesDetails(
                    episodesBySeason: {
                      1: [
                        MediaEntry(
                          id: 'episode',
                          title: 'Pilot',
                          kind: LibraryKind.series,
                          sourceScope: 'current',
                          seasonNumber: 1,
                          episodeNumber: 1,
                        ),
                      ],
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final watched = find.byTooltip('Mark episode as watched');
        final download = find.byType(DownloadActionButton).first;
        final play = find.byTooltip('Play episode');
        expect(tester.getSize(watched), const Size.square(40));
        expect(tester.getSize(download), const Size.square(40));
        expect(tester.getSize(play), const Size.square(40));
        expect(
          tester.getTopLeft(download).dx - tester.getBottomRight(watched).dx,
          12,
        );
        expect(
          tester.getTopLeft(play).dx - tester.getBottomRight(download).dx,
          12,
        );

        await tester.tap(watched);
        await tester.pumpAndSettle();
        final selected = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.check_circle_rounded),
        );
        expect(
          selected.style!.backgroundColor!.resolve({}),
          theme.brightness == Brightness.dark
              ? const Color(0xFF123D28)
              : const Color(0xFFD8F3DC),
        );
        expect(find.byTooltip('Mark episode as unwatched'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'My library resolves a protected cover missing from stored history',
    (tester) async {
      final library = _MemoryLibrary();
      library.history = const [
        LibraryItem(
          accountId: 'account',
          mediaId: 'movie',
          kind: LibraryKind.movies,
          title: 'Movie',
          sourceScope: 'current',
          positionMs: 1000,
        ),
      ];
      final app = _ConnectedApp(NetworkClient(), library);
      addTearDown(app.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppController>.value(
          value: app,
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const Scaffold(body: MyLibraryPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final artwork = tester.widget<MediaArtwork>(find.byType(MediaArtwork));
      expect(artwork.imageUrl, 'https://images.example/current-cover.jpg');
      expect(library.history.single.imageUrl, isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('favorites keep Live TV, movies and series in separate filters', (
    tester,
  ) async {
    final library = _MemoryLibrary();
    library.favorites = const [
      LibraryItem(
        accountId: 'account',
        mediaId: 'live',
        kind: LibraryKind.live,
        title: 'Live channel',
        sourceScope: 'older',
      ),
      LibraryItem(
        accountId: 'account',
        mediaId: 'movie',
        kind: LibraryKind.movies,
        title: 'Favorite movie',
        sourceScope: 'older',
      ),
      LibraryItem(
        accountId: 'account',
        mediaId: 'series',
        kind: LibraryKind.series,
        title: 'Favorite series',
        sourceScope: 'older',
      ),
    ];
    final app = _ConnectedApp(NetworkClient(), library);
    addTearDown(app.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: app,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: MyLibraryPage()),
        ),
      ),
    );
    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();
    expect(find.text('Live channel'), findsOneWidget);
    expect(find.text('Favorite movie'), findsNothing);

    await tester.tap(find.byKey(const Key('favoriteKind_movies')));
    await tester.pumpAndSettle();
    expect(find.text('Favorite movie'), findsOneWidget);
    expect(find.text('Live channel'), findsNothing);

    await tester.tap(find.byKey(const Key('favoriteKind_series')));
    await tester.pumpAndSettle();
    expect(find.text('Favorite series'), findsOneWidget);
    expect(find.text('Favorite movie'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'favorites search filters locally and clearing restores results',
    (tester) async {
      final library = _MemoryLibrary();
      await library.selectAccount(
        'account',
        sourceScope: 'current',
        protected: true,
      );
      library.favorites = const [
        LibraryItem(
          accountId: 'account',
          mediaId: 'hbo',
          kind: LibraryKind.live,
          title: 'HBO',
          sourceScope: 'current',
        ),
        LibraryItem(
          accountId: 'account',
          mediaId: 'news',
          kind: LibraryKind.live,
          title: 'News One',
          sourceScope: 'current',
        ),
      ];
      final app = _ConnectedApp(NetworkClient(), library);
      addTearDown(app.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppController>.value(
          value: app,
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const Scaffold(body: MyLibraryPage()),
          ),
        ),
      );
      await tester.tap(find.text('Favorites'));
      await tester.pumpAndSettle();
      expect(find.text('HBO'), findsOneWidget);
      expect(find.text('News One'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('favoriteSearchField')),
        'hbo',
      );
      await tester.pump();
      expect(find.text('HBO'), findsOneWidget);
      expect(find.text('News One'), findsNothing);
      final directPlay = tester.widget<InkWell>(
        find.byKey(const Key('favoriteLiveOpen_hbo')),
      );
      expect(
        directPlay.onTap,
        isNotNull,
        reason: 'The artwork and title should play an available channel.',
      );

      await tester.tap(find.byKey(const Key('clearFavoriteSearch')));
      await tester.pump();
      expect(find.text('News One'), findsOneWidget);

      await tester.tap(find.byKey(const Key('clearAllFavoritesAction')));
      await tester.pumpAndSettle();
      expect(find.text('Remove all favorites?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(library.favorites, hasLength(2));
    },
  );
}
