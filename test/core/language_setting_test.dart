import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/storage/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  test('language persists without changing other settings', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final settings = SettingsStore(SharedPreferencesAsync());
    expect(await settings.readLanguageCode(), isNull);
    await settings.writeLanguageCode('es');
    expect(
      await SettingsStore(SharedPreferencesAsync()).readLanguageCode(),
      'es',
    );
    await settings.writeLanguageCode('en');
    expect(await settings.readLanguageCode(), 'en');
    await settings.writeLanguageCode(null);
    expect(await settings.readLanguageCode(), isNull);
    await expectLater(settings.writeLanguageCode('xx'), throwsArgumentError);
  });
}
