import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/models/app_identity.dart';
import 'package:denuczi_tv/core/storage/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    AppIdentity.version = '0.5.0';
  });

  test('automatic User-Agent follows the application version', () async {
    final settings = SettingsStore(SharedPreferencesAsync());
    expect(await settings.readUserAgent(), 'DenucziTV/0.5.0');
    AppIdentity.version = '0.5.1';
    expect(await settings.readUserAgent(), 'DenucziTV/0.5.1');
    expect(await settings.isCustomUserAgent(), isFalse);
  });

  test(
    'custom User-Agent survives a version update and default reset',
    () async {
      final settings = SettingsStore(SharedPreferencesAsync());
      await settings.writeUserAgent('MyPlayer/8.5');
      AppIdentity.version = '0.5.2';
      expect(await settings.readUserAgent(), 'MyPlayer/8.5');
      expect(await settings.isCustomUserAgent(), isTrue);
      await settings.resetUserAgent();
      expect(await settings.readUserAgent(), 'DenucziTV/0.5.2');
      expect(await settings.isCustomUserAgent(), isFalse);
    },
  );

  test(
    'previous app default migrates while user header remains custom',
    () async {
      final preferences = SharedPreferencesAsync();
      await preferences.setString(
        'settings.user_agent',
        'OpenStreamDesktop/0.4.16',
      );
      final settings = SettingsStore(preferences);
      expect(await settings.readUserAgent(), 'DenucziTV/0.5.0');
      await preferences.setString('settings.user_agent', 'Custom/5.7');
      expect(await settings.readUserAgent(), 'Custom/5.7');
    },
  );
}
