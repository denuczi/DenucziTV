import '../../../core/errors/app_exception.dart';
import '../../../core/models/account.dart';
import '../../../core/models/app_identity.dart';
import '../../../core/models/protected_account.dart';
import '../../../core/models/protected_access_grant.dart';
import '../../../core/network/network_client.dart';
import '../../../core/storage/account_store.dart';
import '../../library/data/xtream_api.dart';
import '../../library/domain/media_models.dart';
import '../data/protected_link_resolver.dart';

typedef ProtectedCatalog = ({
  List<MediaCategory> categories,
  List<MediaEntry> entries,
});

class PreparedProtectedAccount {
  const PreparedProtectedAccount(
    this.account,
    this.secret,
    this.status,
    this.catalogs,
  );
  final Account account;
  final ProtectedAccountSecret secret;
  final AccountStatus status;
  final Map<LibraryKind, ProtectedCatalog> catalogs;
}

/// Stages complete connections before an atomic secure-store replacement.
/// No identifier or protected URL is placed in the shared HTTP client.
class ProtectedAccountService {
  ProtectedAccountService(
    this.store,
    this.api,
    this.network, {
    ProtectedLinkResolver? resolver,
    DateTime Function()? clock,
  }) : resolver = resolver ?? ProtectedLinkResolver(),
       now = clock ?? (() => DateTime.now().toUtc());

  final AccountStore store;
  final XtreamApi api;
  final NetworkClient network;
  final ProtectedLinkResolver resolver;
  final DateTime Function() now;
  final Map<String, Future<PreparedProtectedAccount>> _flights = {};
  final Map<String, int> _versions = {};
  final Map<String, List<ProtectedAccessGrant>> _grants = {};
  bool _closed = false;
  static const refreshInterval = Duration(hours: 24);
  static const failureCooldown = Duration(minutes: 15);
  static const manualCooldown = Duration(seconds: 30);

  void invalidate(String id) => _versions[id] = (_versions[id] ?? 0) + 1;

  void revokeAccess(String id) {
    invalidate(id);
    for (final grant in _grants[id] ?? <ProtectedAccessGrant>[]) {
      grant.revoke();
    }
  }

  void checkExpirations() {
    for (final grants in _grants.values) {
      for (final grant in grants) {
        grant.checkExpiry();
      }
    }
  }

  void dispose() {
    _closed = true;
    for (final grants in _grants.values) {
      for (final grant in grants) {
        grant.dispose();
      }
    }
  }

  bool isDue(ProtectedAccountSecret secret) {
    final time = now();
    if (secret.expiredAt(time)) return false;
    if (secret.lastAttempt != null &&
        secret.lastSuccess != secret.lastAttempt &&
        time.difference(secret.lastAttempt!) < failureCooldown) {
      return false;
    }
    return secret.lastSuccess == null ||
        time.difference(secret.lastSuccess!) >= refreshInterval;
  }

  Future<PreparedProtectedAccount> register(
    String label,
    String originalUrl,
  ) async {
    if (label.trim().isEmpty) {
      throw const AppException('A protected account name is required.');
    }
    ProtectedLinkResolver.validateUrl(originalUrl);
    final account = Account(
      id: randomUuid(),
      label: label.trim(),
      serverUrl: '',
      username: '',
      connectionType: AccountConnectionType.protectedSingleLink,
    );
    final prepared = await _resolve(account, originalUrl);
    try {
      await store.saveProtected(
        account,
        prepared.secret,
        create: true,
        stillValid: () => !_closed && !prepared.secret.expiredAt(now()),
      );
    } catch (_) {
      _discardPrepared(prepared);
      rethrow;
    }
    return prepared;
  }

  Future<PreparedProtectedAccount> renew(
    Account account, {
    bool automatic = false,
  }) {
    final existing = _flights[account.id];
    if (existing != null) return existing;
    final future = _renew(account, automatic: automatic);
    _flights[account.id] = future;
    future.then<void>(
      (_) {
        _flights.remove(account.id);
      },
      onError: (Object _, StackTrace stack) {
        _flights.remove(account.id);
      },
    );
    return future;
  }

  Future<PreparedProtectedAccount> _renew(
    Account account, {
    required bool automatic,
  }) async {
    final version = _versions[account.id] ?? 0;
    final previous = await store.readProtected(account);
    final time = now();
    final cooldown = automatic ? failureCooldown : manualCooldown;
    if (previous.lastAttempt != null &&
        time.difference(previous.lastAttempt!) < cooldown) {
      throw const AppException(
        'Please wait before checking the protected link again.',
      );
    }
    // Persist backoff before contacting the origin; a restart does not reset it.
    await store.saveProtected(
      account,
      previous.withAttempt(time),
      stillValid: () => !_closed && (_versions[account.id] ?? 0) == version,
    );
    late PreparedProtectedAccount prepared;
    try {
      prepared = await _resolve(account, previous.originalUrl);
    } on ProtectedLinkExpired catch (error) {
      revokeAccess(account.id);
      final expired = ProtectedAccountSecret(
        originalUrl: previous.originalUrl,
        sourceScope: previous.sourceScope,
        expiresAt: error.expiresAt,
        lastSuccess: previous.lastSuccess,
        lastAttempt: time,
      );
      await store.saveProtected(account, expired);
      rethrow;
    }
    try {
      await store.saveProtected(
        account,
        prepared.secret,
        stillValid: () =>
            !_closed &&
            (_versions[account.id] ?? 0) == version &&
            !prepared.secret.expiredAt(now()),
      );
    } catch (_) {
      _discardPrepared(prepared);
      rethrow;
    }
    for (final grant in _grants[account.id] ?? <ProtectedAccessGrant>[]) {
      if (!identical(grant, prepared.secret.credentials?.accessGrant)) {
        grant.supersede();
      }
    }

    return prepared;
  }

  void _discardPrepared(PreparedProtectedAccount prepared) {
    final grant = prepared.secret.credentials?.accessGrant;
    grant?.dispose();
    if (grant != null) _grants[prepared.account.id]?.remove(grant);
  }

  Future<PreparedProtectedAccount> connect(Account account) async {
    final saved = await store.readProtected(account);
    if (saved.expiredAt(now())) {
      throw const AppException('The protected link has expired.');
    }
    if (isDue(saved)) return renew(account, automatic: true);
    final credentials = saved.credentials;
    if (credentials == null) {
      throw const AppException(
        'The protected link must be checked before connecting.',
      );
    }
    try {
      return await _validate(account, saved);
    } on AppException catch (error) {
      if (const {
        'Account access is denied or inactive.',
        'The account has expired.',
        'The server returned HTTP 401.',
        'The server returned HTTP 403.',
      }.contains(error.message)) {
        return renew(account, automatic: true);
      }
      rethrow;
    }
  }

  Future<PreparedProtectedAccount> _resolve(Account account, String url) async {
    final installation = await store.installationIdentity();
    final resolved = await resolver.resolve(
      originalUrl: url,
      label: account.label,
      identificationUserAgent:
          'DenucziTV/${AppIdentity.version} ProtectedLink/1 Installation/$installation',
      genericUserAgent: network.userAgent,
    );
    if (resolved.expiresAt != null && !resolved.expiresAt!.isAfter(now())) {
      throw ProtectedLinkExpired(resolved.expiresAt!);
    }
    final candidate = resolved.credentials;
    // Xtream exposes no globally verifiable content identity in these catalogues.
    // A new authorization gets a new generation even when credentials repeat.
    // Never infer continuity from matching IDs, names or server addresses.
    final scope = randomUuid();
    final time = now();
    final secret = ProtectedAccountSecret(
      originalUrl: url,
      sourceScope: scope,
      expiresAt: resolved.expiresAt,
      lastSuccess: time,
      lastAttempt: time,
      credentials: AccountCredentials(
        serverUrl: candidate.serverUrl,
        username: candidate.username,
        password: candidate.password,
        label: account.label,
        protected: true,
        sourceScope: scope,
        linkExpiresAt: resolved.expiresAt,
      ),
    );
    return _validate(account, secret);
  }

  Future<PreparedProtectedAccount> _validate(
    Account account,
    ProtectedAccountSecret secret,
  ) async {
    final saved = secret.credentials!;
    final grant = ProtectedAccessGrant(
      accountId: account.id,
      expiresAt: secret.expiresAt,
      clock: now,
    );
    (_grants[account.id] ??= []).add(grant);
    final credentials = AccountCredentials(
      serverUrl: saved.serverUrl,
      username: saved.username,
      password: saved.password,
      label: account.label,
      protected: true,
      sourceScope: secret.sourceScope,
      linkExpiresAt: secret.expiresAt,
      accessGrant: grant,
    );
    try {
      final status = await api.authenticate(credentials);
      final catalogs = <LibraryKind, ProtectedCatalog>{};
      // Every section must succeed, including a legitimately empty catalogue.
      // Authentication success alone is not enough to publish a new connection.
      for (final kind in LibraryKind.values) {
        final results = await Future.wait<Object>([
          api.categories(credentials, kind),
          api.catalog(credentials, kind),
        ]);
        catalogs[kind] = (
          categories: results[0] as List<MediaCategory>,
          entries: (results[1] as List<MediaEntry>)
              .map((entry) => entry.withSourceScope(secret.sourceScope))
              .toList(growable: false),
        );
      }
      if (secret.expiredAt(now())) {
        throw ProtectedLinkExpired(secret.expiresAt!);
      }
      return PreparedProtectedAccount(
        account,
        ProtectedAccountSecret(
          originalUrl: secret.originalUrl,
          sourceScope: secret.sourceScope,
          credentials: credentials,
          expiresAt: secret.expiresAt,
          lastAttempt: secret.lastAttempt,
          lastSuccess: secret.lastSuccess,
        ),
        status,
        catalogs,
      );
    } catch (_) {
      grant.dispose();
      _grants[account.id]?.remove(grant);
      rethrow;
    }
  }

  Future<ProtectedAccountSecret> expire(Account account) async {
    final current = await store.readProtected(account);
    if (!current.expiredAt(now()) || current.credentials == null) {
      return current;
    }
    revokeAccess(account.id);
    return store.expireProtected(account, now());
  }
}
