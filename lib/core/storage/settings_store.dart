import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/user_agent.dart';
import '../localization/app_languages.dart';

/// Persistent, non-sensitive application preferences.
class SettingsStore {
  SettingsStore(this._preferences);

  static const _userAgentKey = 'settings.user_agent';
  static const _userAgentModeKey = 'settings.user_agent.mode.v2';
  static const _customUserAgentKey = 'settings.user_agent.custom.v2';
  static final _legacyDefaultUserAgent = RegExp(
    r'^OpenStreamDesktop/0\.\d+\.\d+$',
  );
  static const _activeAccountKey = 'accounts.last_active.v1';
  static const _downloadDirectoryKey = 'downloads.directory.v1';
  static const _downloadHistoryKey = 'downloads.history.v1';
  static const _mediaActionsKey = 'settings.media_actions.v1';
  static const _downloadControlsKey = 'settings.download_controls.v2';
  static const _copyLinkControlsKey = 'settings.copy_link_controls.v2';
  static const _exportM3uKey = 'settings.export_m3u.v2';
  static const _themeModeKey = 'settings.theme_mode.v1';
  static const _languageKey = 'settings.language.v1';
  static const _allowInsecureDownloadRedirectsKey =
      'downloads.allow_https_to_http_redirects.v1';
  final SharedPreferencesAsync _preferences;

  /// Legacy default values are upgraded; user-specified headers are kept.
  Future<bool> isCustomUserAgent() async {
    final mode = await _preferences.getString(_userAgentModeKey);
    if (mode == 'custom') {
      return true;
    }
    if (mode == 'default') {
      return false;
    }
    final legacy = await _preferences.getString(_userAgentKey);
    return legacy != null && !_legacyDefaultUserAgent.hasMatch(legacy);
  }

  Future<String> readUserAgent() async {
    if (!await isCustomUserAgent()) {
      return UserAgent.defaultValue;
    }
    final current = await _preferences.getString(_customUserAgentKey);
    final legacy = await _preferences.getString(_userAgentKey);
    try {
      return UserAgent.validate(current ?? legacy ?? UserAgent.defaultValue);
    } catch (_) {
      return UserAgent.defaultValue;
    }
  }

  /// Explicit saving means custom mode, even if the value equals the default.
  Future<void> writeUserAgent(String value) async {
    await _preferences.setString(
      _customUserAgentKey,
      UserAgent.validate(value),
    );
    await _preferences.setString(_userAgentModeKey, 'custom');
  }

  Future<void> resetUserAgent() =>
      _preferences.setString(_userAgentModeKey, 'default');

  /// Only the profile identifier is persisted here; passwords remain in the
  /// operating system's secure credential store.
  Future<String?> readActiveAccountId() =>
      _preferences.getString(_activeAccountKey);

  Future<void> writeActiveAccountId(String? accountId) async {
    if (accountId == null) {
      await _preferences.remove(_activeAccountKey);
    } else {
      await _preferences.setString(_activeAccountKey, accountId);
    }
  }

  Future<String?> readDownloadDirectory() =>
      _preferences.getString(_downloadDirectoryKey);
  Future<void> writeDownloadDirectory(String value) =>
      _preferences.setString(_downloadDirectoryKey, value);

  Future<String?> readDownloadHistory() =>
      _preferences.getString(_downloadHistoryKey);
  Future<void> writeDownloadHistory(String value) =>
      _preferences.setString(_downloadHistoryKey, value);

  // The v1 switch enabled all three actions. Migrate that preference lazily
  // without resetting the user's previous choice. New installations default off.
  Future<bool> _readAction(String key) async =>
      await _preferences.getBool(key) ??
      await _preferences.getBool(_mediaActionsKey) ??
      false;

  Future<bool> readDownloadControlsEnabled() =>
      _readAction(_downloadControlsKey);
  Future<bool> readCopyLinkControlsEnabled() =>
      _readAction(_copyLinkControlsKey);
  Future<bool> readExportM3uEnabled() => _readAction(_exportM3uKey);

  Future<void> writeDownloadControlsEnabled(bool enabled) =>
      _preferences.setBool(_downloadControlsKey, enabled);
  Future<void> writeCopyLinkControlsEnabled(bool enabled) =>
      _preferences.setBool(_copyLinkControlsKey, enabled);
  Future<void> writeExportM3uEnabled(bool enabled) =>
      _preferences.setBool(_exportM3uKey, enabled);

  // Compatibility with stored v1 preference and older tests.
  Future<bool> readMediaActionsEnabled() =>
      _preferences.getBool(_mediaActionsKey).then((value) => value ?? false);
  Future<void> writeMediaActionsEnabled(bool enabled) =>
      _preferences.setBool(_mediaActionsKey, enabled);

  /// Retains the original v1 key so existing opt-ins are not lost. This
  /// preference now also controls HTTPS-to-HTTP redirects in Xtream API calls.
  /// Native playback continues to use libmpv's own redirect handling.
  Future<bool> readAllowInsecureDownloadRedirects() async =>
      await _preferences.getBool(_allowInsecureDownloadRedirectsKey) ?? false;

  Future<void> writeAllowInsecureDownloadRedirects(bool enabled) =>
      _preferences.setBool(_allowInsecureDownloadRedirectsKey, enabled);

  Future<ThemeMode> readThemeMode() async {
    final stored = await _preferences.getString(_themeModeKey);
    return ThemeMode.values.firstWhere(
      (item) => item.name == stored,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> writeThemeMode(ThemeMode mode) =>
      _preferences.setString(_themeModeKey, mode.name);

  /// Null follows the operating system; explicit choices are preserved.
  Future<String?> readLanguageCode() async {
    final value = await _preferences.getString(_languageKey);
    return value != null && AppLanguages.supports(value) ? value : null;
  }

  Future<void> writeLanguageCode(String? languageCode) async {
    if (languageCode == null) {
      await _preferences.remove(_languageKey);
    } else if (AppLanguages.supports(languageCode)) {
      await _preferences.setString(_languageKey, languageCode);
    } else {
      throw ArgumentError.value(
        languageCode,
        'languageCode',
        'Unsupported language',
      );
    }
  }
}
