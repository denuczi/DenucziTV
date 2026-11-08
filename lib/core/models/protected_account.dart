import 'dart:convert';
import 'dart:math';

import 'account.dart';
import '../errors/app_exception.dart';

class ProtectedLinkExpired extends AppException {
  const ProtectedLinkExpired(this.expiresAt)
    : super('The protected link has expired.');
  final DateTime expiresAt;
}

/// Uses only operating-system entropy, never hardware or operating-system IDs.
String randomUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final text = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${text.substring(0, 8)}-${text.substring(8, 12)}-${text.substring(12, 16)}-${text.substring(16, 20)}-${text.substring(20)}';
}

enum ProtectedSyncState { pending, checking, updated, failed, expired }

/// Stored as one secure-store value. Never serialize this into preferences,
/// diagnostics, notifications, public account metadata, or download history.
class ProtectedAccountSecret {
  const ProtectedAccountSecret({
    required this.originalUrl,
    required this.sourceScope,
    this.credentials,
    this.expiresAt,
    this.lastSuccess,
    this.lastAttempt,
  });

  final String originalUrl;
  final String sourceScope;
  final AccountCredentials? credentials;
  final DateTime? expiresAt;
  final DateTime? lastSuccess;
  final DateTime? lastAttempt;

  bool expiredAt(DateTime now) => expiresAt != null && !expiresAt!.isAfter(now);

  ProtectedAccountSecret withAttempt(DateTime time) => ProtectedAccountSecret(
    originalUrl: originalUrl,
    sourceScope: sourceScope,
    credentials: credentials,
    expiresAt: expiresAt,
    lastSuccess: lastSuccess,
    lastAttempt: time,
  );

  ProtectedAccountSecret withoutConnection() => ProtectedAccountSecret(
    originalUrl: originalUrl,
    sourceScope: sourceScope,
    expiresAt: expiresAt,
    lastSuccess: lastSuccess,
    lastAttempt: lastAttempt,
  );

  String encode() => jsonEncode({
    'version': 1,
    'originalUrl': originalUrl,
    'sourceScope': sourceScope,
    'expiresAt': expiresAt?.toUtc().toIso8601String(),
    'lastSuccess': lastSuccess?.toUtc().toIso8601String(),
    'lastAttempt': lastAttempt?.toUtc().toIso8601String(),
    if (credentials case final value?)
      'connection': {
        'serverUrl': value.serverUrl,
        'username': value.username,
        'password': value.password,
      },
  });

  factory ProtectedAccountSecret.decode(String encoded, String label) {
    final json = jsonDecode(encoded) as Map<String, dynamic>;
    if (json['version'] != 1) {
      throw const FormatException('Unsupported protected account format');
    }
    DateTime? timestamp(String key) {
      if (!json.containsKey(key)) {
        throw const FormatException('Incomplete protected account state');
      }
      final value = json[key];
      if (value == null) return null;
      final parsed = value is String ? DateTime.tryParse(value) : null;
      if (parsed == null || !parsed.isUtc) {
        throw const FormatException('Invalid protected account timestamp');
      }
      return parsed;
    }

    final expires = timestamp('expiresAt');
    final scope = json['sourceScope'] as String;
    if (scope.isEmpty || (json['originalUrl'] as String).trim().isEmpty) {
      throw const FormatException('Incomplete protected account state');
    }
    final value = json['connection'] as Map<String, dynamic>?;
    if (value != null &&
        ['serverUrl', 'username', 'password'].any(
          (key) =>
              value[key] is! String || (value[key] as String).trim().isEmpty,
        )) {
      throw const FormatException('Incomplete protected connection');
    }
    return ProtectedAccountSecret(
      originalUrl: json['originalUrl'] as String,
      sourceScope: scope,
      expiresAt: expires,
      lastSuccess: timestamp('lastSuccess'),
      lastAttempt: timestamp('lastAttempt'),
      credentials: value == null
          ? null
          : AccountCredentials(
              serverUrl: value['serverUrl'] as String,
              username: value['username'] as String,
              password: value['password'] as String,
              label: label,
              protected: true,
              sourceScope: scope,
              linkExpiresAt: expires,
            ),
    );
  }
}
