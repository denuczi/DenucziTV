import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../features/library/data/xtream_api.dart';
import '../../features/personal_library/application/personal_library_controller.dart';
import '../../features/downloads/data/download_manager.dart';
import '../../features/library/domain/media_models.dart';
import '../errors/app_exception.dart';
import '../network/network_client.dart';
import '../network/server_address.dart';
import '../network/user_agent.dart';
import '../storage/account_store.dart';
import '../storage/settings_store.dart';
import 'account.dart';

/// Coordinates application state while leaving transport and persistence
/// responsibilities to independently testable services.
class AppController extends ChangeNotifier {
  AppController({
    required NetworkClient network,
    required XtreamApi api,
    required AccountStore accounts,
    required SettingsStore settings,
    DownloadManager? downloads,
    PersonalLibraryController? personalLibrary,
  }) : this._(
         network,
         api,
         accounts,
         settings,
         downloads ?? DownloadManager(network, settings),
         personalLibrary,
       );

  AppController._(
    this._network,
    this._api,
    this._accounts,
    this._settings,
    this.downloads,
    this.personalLibrary,
  );

  final NetworkClient _network;
  final XtreamApi _api;
  final AccountStore _accounts;
  final SettingsStore _settings;
  final DownloadManager downloads;
  final PersonalLibraryController? personalLibrary;
  Map<String, AccountStatus> accountStatuses = {};
  ThemeMode themeMode = ThemeMode.system;
  String? languageCode;
  bool showDownloadControls = false;
  bool showCopyLinkControls = false;
  bool showExportM3u = false;
  bool allowInsecureDownloadRedirects = false;

  List<Account> savedAccounts = [];
  List<MediaCategory> categories = [];
  List<MediaEntry> entries = [];
  Account? activeAccount;
  AccountStatus? accountStatus;
  LibraryKind kind = LibraryKind.live;
  String? categoryId;
  String search = '';
  String? error;
  String userAgent = UserAgent.defaultValue;
  bool customUserAgent = false;
  bool loading = false;
  bool connecting = false;
  bool restoringAccount = false;
  bool initialized = false;
  bool _disposed = false;

  AccountCredentials? _credentials;
  CancelToken? _catalogCancellation;
  int _catalogVersion = 0;
  int _connectionVersion = 0;
  // Avoid retaining multiple exceptionally large provider catalogs between
  // sections. The visible catalog is still available until navigation changes.
  static const int maxCachedCatalogEntries = 100000;
  final Map<
    LibraryKind,
    ({List<MediaCategory> categories, List<MediaEntry> entries})
  >
  _catalogCache = {};
  List<MediaEntry>? _visibleCache;
  Future<void>? _automaticConnection;
  Future<void> _preferredAccountWrites = Future<void>.value();

  /// The connection continues after initialize() so the UI can render while
  /// the provider is contacted. Useful for awaiting startup in integration tests.
  Future<void>? get automaticConnection => _automaticConnection;

  Future<void> _persistPreferredAccount(String? accountId) {
    final update = _preferredAccountWrites.then(
      (_) => _settings.writeActiveAccountId(accountId),
    );
    _preferredAccountWrites = update.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return update;
  }

  XtreamApi get api => _api;
  NetworkClient get network => _network;
  AccountCredentials? get credentials => _credentials;

  List<MediaEntry> get visibleEntries {
    final cached = _visibleCache;
    if (cached != null) {
      return cached;
    }
    final query = search.trim().toLowerCase();
    if (query.isEmpty && categoryId == null) {
      // No filters: avoid copying a potentially very large provider catalog.
      return _visibleCache = UnmodifiableListView<MediaEntry>(entries);
    }
    return _visibleCache = List.unmodifiable(
      entries.where((entry) {
        if (categoryId != null && categoryId != entry.categoryId) {
          return false;
        }
        return query.isEmpty || entry.title.toLowerCase().contains(query);
      }),
    );
  }

  void _invalidateVisibleEntries() => _visibleCache = null;

  Future<void> initialize() async {
    final warnings = <String>[];
    // Each store is independent. One corrupted preferences record must not
    // prevent unrelated settings and downloads from becoming available.
    try {
      customUserAgent = await _settings.isCustomUserAgent();
      userAgent = await _settings.readUserAgent();
      _network.userAgent = userAgent;
    } catch (_) {
      warnings.add('Network preferences could not be restored.');
    }
    try {
      await _accounts.reconcilePendingDeletions();
    } catch (_) {
      warnings.add('Pending credential cleanup could not be completed.');
    }
    try {
      savedAccounts = await _accounts.list();
    } catch (_) {
      warnings.add('Saved accounts could not be read.');
    }
    String? lastActiveAccountId;
    try {
      lastActiveAccountId = await _settings.readActiveAccountId();
    } catch (_) {
      warnings.add('The last selected account could not be restored.');
    }
    try {
      accountStatuses = await _accounts.readStatuses();
    } catch (_) {
      warnings.add('Account metadata could not be restored.');
    }
    try {
      themeMode = await _settings.readThemeMode();
    } catch (_) {
      warnings.add('Appearance preferences could not be restored.');
    }
    try {
      languageCode = await _settings.readLanguageCode();
    } catch (_) {
      warnings.add('Language preferences could not be restored.');
    }
    try {
      showDownloadControls = await _settings.readDownloadControlsEnabled();
    } catch (_) {
      warnings.add('Download button preference could not be restored.');
    }
    try {
      showCopyLinkControls = await _settings.readCopyLinkControlsEnabled();
    } catch (_) {
      warnings.add('Copy-link preference could not be restored.');
    }
    try {
      showExportM3u = await _settings.readExportM3uEnabled();
    } catch (_) {
      warnings.add('M3U export preference could not be restored.');
    }
    try {
      allowInsecureDownloadRedirects = await _settings
          .readAllowInsecureDownloadRedirects();
    } catch (_) {
      warnings.add('Download redirect preferences could not be restored.');
    }
    try {
      await downloads.initialize();
    } catch (_) {
      warnings.add('Download history could not be restored.');
    }
    try {
      await personalLibrary?.initialize();
    } catch (_) {
      warnings.add('Personal library storage could not be opened.');
    }
    if (warnings.isNotEmpty) {
      error = warnings.join(' ');
    }
    initialized = true;
    notifyListeners();

    // Respect explicit disconnection. Older releases did not persist the
    // selection; those users choose a saved profile once after upgrading.
    final preferredId = lastActiveAccountId;
    if (preferredId != null) {
      final matches = savedAccounts.where(
        (account) => account.id == preferredId,
      );
      if (matches.isNotEmpty) {
        // Do not hold the first window hostage to a slow or offline provider.
        // A failure leaves the saved profiles available for manual selection.
        _automaticConnection = _restoreSavedAccount(matches.first);
      } else if (warnings.isEmpty) {
        // An account deleted in an earlier version must not be retried forever.
        unawaited(_persistPreferredAccount(null).catchError((Object error) {}));
      }
    }
  }

  Future<void> _restoreSavedAccount(Account account) async {
    restoringAccount = true;
    notifyListeners();
    try {
      await connectSaved(account);
    } finally {
      restoringAccount = false;
      notifyListeners();
    }
  }

  Future<void> updateUserAgent(String value) async {
    final validated = UserAgent.validate(value);
    await _settings.writeUserAgent(validated);
    _network.userAgent = validated;
    userAgent = validated;
    customUserAgent = true;
    notifyListeners();
  }

  Future<void> resetUserAgent() async {
    await _settings.resetUserAgent();
    final fallback = UserAgent.defaultValue;
    _network.userAgent = fallback;
    userAgent = fallback;
    customUserAgent = false;
    notifyListeners();
  }

  Future<void> updateLanguage(String? code) async {
    await _settings.writeLanguageCode(code);
    languageCode = code;
    notifyListeners();
  }

  Future<void> updateThemeMode(ThemeMode mode) async {
    await _settings.writeThemeMode(mode);
    themeMode = mode;
    notifyListeners();
  }

  Future<void> updateDownloadControls(bool enabled) async {
    await _settings.writeDownloadControlsEnabled(enabled);
    showDownloadControls = enabled;
    notifyListeners();
  }

  Future<void> updateCopyLinkControls(bool enabled) async {
    await _settings.writeCopyLinkControlsEnabled(enabled);
    showCopyLinkControls = enabled;
    notifyListeners();
  }

  Future<void> updateAllowInsecureDownloadRedirects(bool enabled) async {
    await _settings.writeAllowInsecureDownloadRedirects(enabled);
    allowInsecureDownloadRedirects = enabled;
    notifyListeners();
  }

  Future<void> updateExportM3u(bool enabled) async {
    await _settings.writeExportM3uEnabled(enabled);
    showExportM3u = enabled;
    notifyListeners();
  }

  Future<bool> connect(AccountCredentials input, {String? existingId}) async {
    if (connecting) {
      return false;
    }
    connecting = true;
    error = null;
    notifyListeners();
    final version = ++_connectionVersion;
    try {
      final serverUrl = ServerAddress.parse(input.serverUrl).toString();
      if (input.username.trim().isEmpty || input.password.isEmpty) {
        throw const AppException('Username and password are required.');
      }
      final validated = AccountCredentials(
        serverUrl: serverUrl,
        username: input.username.trim(),
        password: input.password,
        label: input.label.trim().isEmpty
            ? input.username.trim()
            : input.label.trim(),
      );
      final status = await _api.authenticate(validated);
      if (version != _connectionVersion) {
        return false;
      }
      final match = savedAccounts.where(
        (item) =>
            item.serverUrl == validated.serverUrl &&
            item.username == validated.username,
      );
      final id =
          existingId ??
          (match.isNotEmpty
              ? match.first.id
              : DateTime.now().microsecondsSinceEpoch.toRadixString(36));
      final account = Account(
        id: id,
        label: validated.label,
        serverUrl: validated.serverUrl,
        username: validated.username,
      );
      await _accounts.save(account, validated.password);
      if (version != _connectionVersion) {
        return false;
      }
      savedAccounts = await _accounts.list();
      accountStatuses[id] = status;
      try {
        await _accounts.writeStatus(id, status);
      } catch (_) {
        // A metadata cache failure must not invalidate an authenticated account.
      }
      _disconnect(clearError: false);
      activeAccount = account;
      accountStatus = status;
      _credentials = validated;
      kind = LibraryKind.live;
      try {
        await personalLibrary?.selectAccount(account.id);
      } catch (_) {
        error = 'The personal library could not be loaded.';
      }
      try {
        await _persistPreferredAccount(account.id);
      } catch (_) {
        // The current connection is valid even when restoring it next time
        // will require manual selection. Do not discard authenticated access.
        error = 'Connected, but the account selection could not be saved.';
      }
      notifyListeners();
      await selectKind(LibraryKind.live);
      return true;
    } catch (failure) {
      if (version == _connectionVersion) {
        error = failure is AppException
            ? failure.message
            : 'Could not save or connect the account.';
        notifyListeners();
      }
      return false;
    } finally {
      if (version == _connectionVersion) {
        connecting = false;
        notifyListeners();
      }
    }
  }

  Future<void> connectSaved(Account account) async {
    final connectionVersion = _connectionVersion;
    try {
      final password = await _accounts.readPassword(account.id);
      if (connectionVersion != _connectionVersion || connecting) {
        return;
      }
      await connect(
        AccountCredentials(
          serverUrl: account.serverUrl,
          username: account.username,
          password: password,
          label: account.label,
        ),
        existingId: account.id,
      );
    } catch (_) {
      if (connectionVersion == _connectionVersion) {
        error = 'Could not read the saved account credentials.';
        notifyListeners();
      }
    }
  }

  Future<void> removeSaved(Account account) async {
    try {
      await _accounts.remove(account.id);
      // Account-scoped history and favorites contain personal activity.
      // If this cleanup fails, the account remains removed; surface a warning
      // so the user knows local activity may still remain on disk.
      try {
        await personalLibrary?.deleteAccount(account.id);
      } catch (_) {
        error = 'Account removed, but local library cleanup failed.';
      }
      savedAccounts = await _accounts.list();
      accountStatuses.remove(account.id);
      if (activeAccount?.id == account.id) {
        await disconnect();
      }
      notifyListeners();
    } catch (_) {
      // Refresh after a partial failure: public metadata may already be gone.
      try {
        savedAccounts = await _accounts.list();
      } catch (_) {
        // Retain the last displayed snapshot if the store is inaccessible.
      }
      error = 'Could not finish deleting the saved account.';
      notifyListeners();
    }
  }

  Future<void> selectKind(LibraryKind selected) async {
    kind = selected;
    _invalidateVisibleEntries();
    categoryId = null;
    search = '';
    error = null;
    final credentials = _credentials;
    _catalogCancellation?.cancel();
    final version = ++_catalogVersion;
    if (credentials == null) {
      loading = false;
      categories = [];
      entries = [];
      notifyListeners();
      return;
    }
    final cached = _catalogCache[selected];
    if (cached != null) {
      categories = cached.categories;
      entries = cached.entries;
      _invalidateVisibleEntries();
      loading = false;
      notifyListeners();
      return;
    }
    categories = [];
    entries = [];
    loading = true;
    notifyListeners();
    final token = CancelToken();
    _catalogCancellation = token;
    try {
      // Each endpoint is independent and can complete in parallel.
      final results = await Future.wait<Object>([
        _api.categories(credentials, selected, cancelToken: token),
        _api.catalog(credentials, selected, cancelToken: token),
      ]);
      if (version != _catalogVersion || token.isCancelled) {
        return;
      }
      final resolvedCategories = results[0] as List<MediaCategory>;
      final resolvedEntries = results[1] as List<MediaEntry>;
      if (resolvedEntries.length <= maxCachedCatalogEntries) {
        _catalogCache[selected] = (
          categories: resolvedCategories,
          entries: resolvedEntries,
        );
      } else {
        _catalogCache.remove(selected);
      }
      categories = resolvedCategories;
      entries = resolvedEntries;
      _invalidateVisibleEntries();
      if (selected != LibraryKind.live &&
          resolvedEntries.isNotEmpty &&
          activeAccount != null) {
        final accountId = activeAccount!.id;
        unawaited(
          personalLibrary
                  ?.reconcileCatalog(
                    accountId,
                    selected,
                    resolvedEntries.map((item) => item.id),
                  )
                  .catchError((Object _) {}) ??
              Future<void>.value(),
        );
      }
    } catch (failure) {
      if (version != _catalogVersion || token.isCancelled) {
        return;
      }
      error = failure is AppException
          ? failure.message
          : 'The catalog could not be loaded.';
    } finally {
      if (version == _catalogVersion) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> refresh() async {
    final selectedKind = kind;
    final accountId = activeAccount?.id;
    final previousCategory = categoryId;
    final previousSearch = search;
    _catalogCache.remove(selectedKind);
    final pending = selectKind(selectedKind);
    final version = _catalogVersion;
    await pending;
    if (version != _catalogVersion ||
        activeAccount?.id != accountId ||
        kind != selectedKind) {
      return;
    }
    categoryId = previousCategory;
    search = previousSearch;
    _invalidateVisibleEntries();
    notifyListeners();
  }

  void filterCategory(String? value) {
    categoryId = value;
    _invalidateVisibleEntries();
    notifyListeners();
  }

  void setSearch(String value) {
    search = value;
    _invalidateVisibleEntries();
    notifyListeners();
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  Future<void> disconnect() async {
    ++_connectionVersion;
    _disconnect(clearError: true);
    connecting = false;
    notifyListeners();
    try {
      await _persistPreferredAccount(null);
    } catch (_) {
      error = 'Disconnected, but the saved selection could not be cleared.';
      notifyListeners();
    }
  }

  void _disconnect({required bool clearError}) {
    _catalogCancellation?.cancel();
    ++_catalogVersion;
    _catalogCache.clear();
    activeAccount = null;
    accountStatus = null;
    _credentials = null;
    // Scope switches immediately, even if a previous database read finishes later.
    unawaited(personalLibrary?.selectAccount(null) ?? Future<void>.value());
    entries = [];
    categories = [];
    _invalidateVisibleEntries();
    categoryId = null;
    loading = false;
    if (clearError) {
      error = null;
    }
  }

  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_connectionVersion;
    _catalogCancellation?.cancel();
    downloads.dispose();
    unawaited(
      personalLibrary?.close().catchError((Object _) {}) ??
          Future<void>.value(),
    );
    _network.dispose();
    super.dispose();
  }
}
