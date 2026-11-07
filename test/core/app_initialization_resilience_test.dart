import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/models/app_controller.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/core/storage/account_store.dart';
import 'package:denuczi_tv/core/storage/settings_store.dart';
import 'package:denuczi_tv/features/library/data/xtream_api.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class FailingUserAgentStore extends SettingsStore {
  FailingUserAgentStore(super.preferences);

  @override
  Future<String> readUserAgent() async => throw StateError('Simulated failure');
}

class EmptySecrets implements AccountSecrets {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('a failed network preference does not block theme and account initialization', () async {
    final preferences = SharedPreferencesAsync();
    await preferences.setString('settings.theme_mode.v1', ThemeMode.light.name);
    final settings = FailingUserAgentStore(preferences);
    final network = NetworkClient();
    final controller = AppController(
      network: network,
      api: XtreamApi(network),
      accounts: AccountStore.withSecrets(preferences, EmptySecrets()),
      settings: settings,
    );
    addTearDown(controller.dispose);

    await controller.initialize();

    expect(controller.initialized, isTrue);
    expect(controller.themeMode, ThemeMode.light);
    expect(controller.error, contains('Network preferences'));
    expect(controller.savedAccounts, isEmpty);
  });
}
