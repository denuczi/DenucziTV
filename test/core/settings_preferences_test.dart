import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/storage/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test(
    'media actions are opt-in and theme follows the system by default',
    () async {
      final settings = SettingsStore(SharedPreferencesAsync());
      expect(await settings.readMediaActionsEnabled(), isFalse);
      expect(await settings.readThemeMode(), ThemeMode.system);
      await settings.writeMediaActionsEnabled(true);
      await settings.writeThemeMode(ThemeMode.light);
      expect(await settings.readMediaActionsEnabled(), isTrue);
      expect(await settings.readThemeMode(), ThemeMode.light);
    },
  );

  test(
    'individual media controls default off and persist separately',
    () async {
      final settings = SettingsStore(SharedPreferencesAsync());
      expect(await settings.readDownloadControlsEnabled(), isFalse);
      expect(await settings.readCopyLinkControlsEnabled(), isFalse);
      expect(await settings.readExportM3uEnabled(), isFalse);

      await settings.writeDownloadControlsEnabled(true);
      expect(await settings.readDownloadControlsEnabled(), isTrue);
      expect(await settings.readCopyLinkControlsEnabled(), isFalse);
      expect(await settings.readExportM3uEnabled(), isFalse);

      await settings.writeExportM3uEnabled(true);
      expect(await settings.readExportM3uEnabled(), isTrue);
      expect(await settings.readCopyLinkControlsEnabled(), isFalse);
    },
  );

  test('legacy combined media setting is migrated independently', () async {
    final settings = SettingsStore(SharedPreferencesAsync());
    await settings.writeMediaActionsEnabled(true);
    expect(await settings.readDownloadControlsEnabled(), isTrue);
    expect(await settings.readCopyLinkControlsEnabled(), isTrue);
    expect(await settings.readExportM3uEnabled(), isTrue);

    await settings.writeCopyLinkControlsEnabled(false);
    expect(await settings.readCopyLinkControlsEnabled(), isFalse);
    expect(await settings.readDownloadControlsEnabled(), isTrue);
    expect(await settings.readExportM3uEnabled(), isTrue);
  });

  test(
    'last selected account is persisted without storing credentials',
    () async {
      final settings = SettingsStore(SharedPreferencesAsync());
      expect(await settings.readActiveAccountId(), isNull);
      await settings.writeActiveAccountId('account-123');
      expect(await settings.readActiveAccountId(), 'account-123');
      await settings.writeActiveAccountId(null);
      expect(await settings.readActiveAccountId(), isNull);
    },
  );

  test('HTTPS-to-HTTP redirect consent stays opt-in and persistent', () async {
    final settings = SettingsStore(SharedPreferencesAsync());
    expect(await settings.readAllowInsecureDownloadRedirects(), isFalse);
    await settings.writeAllowInsecureDownloadRedirects(true);
    expect(await settings.readAllowInsecureDownloadRedirects(), isTrue);

    final reloaded = SettingsStore(SharedPreferencesAsync());
    expect(await reloaded.readAllowInsecureDownloadRedirects(), isTrue);
    await reloaded.writeAllowInsecureDownloadRedirects(false);
    expect(await settings.readAllowInsecureDownloadRedirects(), isFalse);
  });

  test('download directory is persisted', () async {
    final settings = SettingsStore(SharedPreferencesAsync());
    await settings.writeDownloadDirectory('/tmp/Example Downloads');
    expect(await settings.readDownloadDirectory(), '/tmp/Example Downloads');
  });
}
