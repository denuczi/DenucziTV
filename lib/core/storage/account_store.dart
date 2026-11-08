import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../errors/app_exception.dart';
import '../models/account.dart';
import '../models/protected_account.dart';

/// Abstraction that allows credential operations to be simulated in tests.
abstract interface class AccountSecrets {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureAccountSecrets implements AccountSecrets {
  const SecureAccountSecrets(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Stores public metadata separately from account secrets.
///
/// Deletion is recoverable without a cross-store transaction: a tombstone is
/// persisted before metadata removal, and secret cleanup is retried at startup.
/// The public account list is removed before deleting a secret, so a failed
/// deletion never leaves a visible account with a missing password.
class AccountStore {
  AccountStore(SharedPreferencesAsync preferences, FlutterSecureStorage secrets)
    : this.withSecrets(preferences, SecureAccountSecrets(secrets));

  AccountStore.withSecrets(this._preferences, this._secrets);

  static const _accountsKey = 'accounts.list.v1';
  static const _statusKey = 'accounts.status.v1';
  static const _pendingDeletionKey = 'accounts.pending_secret_deletion.v1';

  final SharedPreferencesAsync _preferences;
  final AccountSecrets _secrets;
  Future<void> _mutations = Future<void>.value();
  Future<String>? _installationIdentity;

  /// Private resolver identity. Never pass this to the shared NetworkClient.
  Future<String> installationIdentity() {
    final pending = _installationIdentity;
    if (pending != null) return pending;
    final operation = _createInstallationIdentity();
    _installationIdentity = operation;
    unawaited(
      operation.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          if (identical(_installationIdentity, operation)) {
            _installationIdentity = null;
          }
        },
      ),
    );
    return operation;
  }

  Future<String> _createInstallationIdentity() => _serialize(() async {
    const key = 'installation.protected_link_uuid.v1';
    final existing = await _secrets.read(key);
    if (existing != null) {
      if (!RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(existing)) {
        throw const AppException('Protected account storage is unavailable.');
      }
      return existing;
    }
    final identity = randomUuid();
    await _secrets.write(key, identity);
    return identity;
  });

  Future<ProtectedAccountSecret> readProtected(Account account) async {
    try {
      final value = await _secrets.read(_protectedKey(account.id));
      if (value == null) throw const FormatException('Missing protected state');
      return ProtectedAccountSecret.decode(value, account.label);
    } catch (_) {
      throw const AppException('Protected account storage is unavailable.');
    }
  }

  Future<void> saveProtected(
    Account account,
    ProtectedAccountSecret state, {
    bool create = false,
    bool updateMetadata = false,
    bool Function()? stillValid,
  }) => _serialize(() async {
    if (!account.isProtected || account.label.trim().isEmpty) {
      throw const AppException('A protected account name is required.');
    }
    final existing = await list();
    if (!create &&
        !existing.any((value) => value.id == account.id && value.isProtected)) {
      throw const AppException('The protected account is no longer available.');
    }
    final key = _protectedKey(account.id);
    final previous = await _secrets.read(key);
    if (stillValid != null && !stillValid()) {
      throw const AppException('The protected account check was cancelled.');
    }
    await _secrets.write(key, state.encode());
    try {
      if (create || updateMetadata) {
        await _preferences.setString(
          _accountsKey,
          jsonEncode([
            ...existing
                .where((value) => value.id != account.id)
                .map((value) => value.toJson()),
            account.toJson(),
          ]),
        );
      }
    } catch (_) {
      if (previous == null) {
        await _secrets.delete(key);
      } else {
        await _secrets.write(key, previous);
      }
      throw const AppException('Protected account storage is unavailable.');
    }
  });

  Future<void> renameProtected(
    Account account,
    String label,
  ) => _serialize(() async {
    if (!account.isProtected || label.trim().isEmpty) {
      throw const AppException('A protected account name is required.');
    }
    final existing = await list();
    if (!existing.any((item) => item.id == account.id && item.isProtected)) {
      throw const AppException('The protected account is no longer available.');
    }
    final renamed = Account(
      id: account.id,
      label: label.trim(),
      serverUrl: '',
      username: '',
      connectionType: AccountConnectionType.protectedSingleLink,
    );
    await _preferences.setString(
      _accountsKey,
      jsonEncode([
        for (final item in existing)
          (item.id == account.id ? renamed : item).toJson(),
      ]),
    );
  });

  /// Reads and clears one authorization in the same storage mutation queue.
  /// A renewal committed before this operation must never be overwritten.
  Future<ProtectedAccountSecret> expireProtected(
    Account account,
    DateTime time,
  ) => _serialize(() async {
    final current = await readProtected(account);
    if (!current.expiredAt(time) || current.credentials == null) return current;
    final cleared = current.withoutConnection();
    await _secrets.write(_protectedKey(account.id), cleared.encode());
    return cleared;
  });

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _mutations = _mutations.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  Future<List<Account>> list() async {
    final raw = await _preferences.getString(_accountsKey);
    if (raw == null) {
      return [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        throw const FormatException('Invalid account list');
      }
      return decoded
          .map(
            (item) => Account.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(growable: false);
    } catch (_) {
      throw const AppException('Saved account information is corrupted.');
    }
  }

  Future<void> save(Account account, String password) => _serialize(() async {
    final existing = await list();
    final key = _passwordKey(account.id);
    final pending = await _readPending();
    final previousPassword = await _secrets.read(key);
    await _secrets.write(key, password);
    try {
      final updated = [
        ...existing.where((entry) => entry.id != account.id),
        account,
      ];
      await _preferences.setString(
        _accountsKey,
        jsonEncode(updated.map((entry) => entry.toJson()).toList()),
      );
    } catch (_) {
      try {
        if (previousPassword != null) {
          await _secrets.write(key, previousPassword);
        } else {
          await _secrets.delete(key);
        }
      } catch (_) {
        throw const AppException(
          'Account metadata was not saved, and credential rollback failed. '
          'Verify the saved account before trying again.',
        );
      }
      rethrow;
    }
    if (pending.contains(account.id)) {
      try {
        await _preferences.setStringList(
          _pendingDeletionKey,
          pending.where((id) => id != account.id).toList(),
        );
      } catch (_) {
        // Reconciliation sees the visible account and safely removes the marker.
      }
    }
  });

  Future<String> readPassword(String accountId) async {
    final password = await _secrets.read(_passwordKey(accountId));
    if (password == null || password.isEmpty) {
      throw const AppException(
        'No stored password is available for this account.',
      );
    }
    return password;
  }

  Future<Map<String, AccountStatus>> readStatuses() async {
    final raw = await _preferences.getString(_statusKey);
    if (raw == null) {
      return {};
    }
    try {
      final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return json.map(
        (key, value) => MapEntry(
          key,
          AccountStatus.fromJson(Map<String, dynamic>.from(value as Map)),
        ),
      );
    } catch (_) {
      // This is a replaceable, non-sensitive cache.
      return {};
    }
  }

  Future<void> writeStatus(String accountId, AccountStatus status) =>
      _serialize(() async {
        final records = await readStatuses();
        records[accountId] = status;
        await _preferences.setString(
          _statusKey,
          jsonEncode(
            records.map((key, value) => MapEntry(key, value.toJson())),
          ),
        );
      });

  Future<List<String>> _readPending() async =>
      await _preferences.getStringList(_pendingDeletionKey) ?? <String>[];

  /// Replays incomplete secret deletions after a crash or storage failure.
  Future<void> reconcilePendingDeletions() => _serialize(() async {
    final pending = await _readPending();
    if (pending.isEmpty) {
      return;
    }
    // If account metadata is corrupt or unavailable, do not delete secrets.
    final visible = (await list()).map((account) => account.id).toSet();
    final remaining = <String>[];
    for (final id in pending.toSet()) {
      if (visible.contains(id)) {
        continue;
      }
      try {
        await _secrets.delete(_passwordKey(id));
        await _secrets.delete(_protectedKey(id));
      } catch (_) {
        remaining.add(id);
      }
    }
    await _preferences.setStringList(_pendingDeletionKey, remaining);
  });

  Future<void> remove(String accountId) => _serialize(() async {
    final existing = await list();
    if (!existing.any((account) => account.id == accountId)) {
      return;
    }
    final pending = await _readPending();
    if (!pending.contains(accountId)) {
      await _preferences.setStringList(_pendingDeletionKey, [
        ...pending,
        accountId,
      ]);
    }
    final updated = existing.where((item) => item.id != accountId);
    // Commit the public list before deleting the credential.
    await _preferences.setString(
      _accountsKey,
      jsonEncode(updated.map((item) => item.toJson()).toList()),
    );
    try {
      final statuses = await readStatuses();
      statuses.remove(accountId);
      await _preferences.setString(
        _statusKey,
        jsonEncode(statuses.map((key, value) => MapEntry(key, value.toJson()))),
      );
    } catch (_) {
      // The status is a replaceable cache and must not roll back deletion.
    }
    try {
      await _secrets.delete(_passwordKey(accountId));
      await _secrets.delete(_protectedKey(accountId));
      await _preferences.setStringList(
        _pendingDeletionKey,
        (await _readPending()).where((id) => id != accountId).toList(),
      );
    } catch (_) {
      // The tombstone is retained to retry cleanup on the next launch.
      // Never restore a public account after its metadata has been removed.
    }
  });

  String _passwordKey(String id) => 'account.$id.password';
  String _protectedKey(String id) => 'account.$id.protected.v1';
}
