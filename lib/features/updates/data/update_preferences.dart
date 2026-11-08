import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/semantic_version.dart';

class UpdatePostponement {
  const UpdatePostponement(this.version, this.createdAt, this.until);
  final SemanticVersion version;
  final DateTime createdAt;
  final DateTime until;

  bool suppresses(SemanticVersion candidate, DateTime now) =>
      !now.isBefore(createdAt) &&
      now.isBefore(until) &&
      candidate.compareTo(version) <= 0;
}

/// Only non-sensitive timestamps and a semantic version; no account data or URLs.
class UpdatePreferences {
  UpdatePreferences(this._preferences);
  final SharedPreferencesAsync _preferences;
  static const lastCheckKey = 'updates.last_success.v1';
  static const postponementKey = 'updates.postponement.v1';
  static const postponementPeriod = Duration(days: 7);

  Future<DateTime?> readLastSuccess() async {
    final raw = await _preferences.getString(lastCheckKey);
    return raw == null ? null : DateTime.tryParse(raw)?.toUtc();
  }

  Future<void> saveLastSuccess(DateTime time) =>
      _preferences.setString(lastCheckKey, time.toUtc().toIso8601String());

  Future<UpdatePostponement?> readPostponement() async {
    try {
      final raw = await _preferences.getString(postponementKey);
      if (raw == null || raw.length > 2048) return null;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final version = SemanticVersion.tryParse(data['version'] as String);
      final created = DateTime.parse(data['createdAt'] as String).toUtc();
      final until = DateTime.parse(data['until'] as String).toUtc();
      if (version == null ||
          !version.isStable ||
          until.difference(created) != postponementPeriod) {
        return null;
      }
      return UpdatePostponement(version, created, until);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> postpone(SemanticVersion version, DateTime time) =>
      _preferences.setString(
        postponementKey,
        jsonEncode({
          'version': version.canonical,
          'createdAt': time.toUtc().toIso8601String(),
          'until': time.toUtc().add(postponementPeriod).toIso8601String(),
        }),
      );
}
