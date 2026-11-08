import 'dart:async';

/// A revocable runtime authorization shared by API calls, players and downloads.
/// A credential snapshot cannot bypass expiry merely by outliving its account UI.
class ProtectedAccessGrant {
  ProtectedAccessGrant({
    required this.accountId,
    this.expiresAt,
    DateTime Function()? clock,
  }) : _now = clock ?? (() => DateTime.now().toUtc()) {
    _revocations = StreamController<void>.broadcast(
      onListen: () {
        if (!_revoked && expiresAt != null) {
          _clockWatch = Timer.periodic(
            const Duration(seconds: 1),
            (_) => checkExpiry(),
          );
        }
      },
      onCancel: () => _clockWatch?.cancel(),
    );
    final expiry = expiresAt;
    if (expiry != null) {
      final remaining = expiry.difference(_now());
      _timer = Timer(
        remaining.isNegative ? Duration.zero : remaining,
        checkExpiry,
      );
    }
  }
  final String accountId;
  final DateTime? expiresAt;
  final DateTime Function() _now;
  late final StreamController<void> _revocations;
  Timer? _clockWatch;
  Timer? _timer;
  bool _revoked = false;
  bool _superseded = false;
  bool _closed = false;
  Stream<void> get revocations => _revocations.stream;
  bool get allowsNewSessions => usable && !_superseded;

  /// Existing streams and transfers retain their original authorization;
  /// starting another operation from an obsolete snapshot is prohibited.
  void supersede() => _superseded = true;

  bool get usable {
    checkExpiry();
    return !_revoked;
  }

  void checkExpiry() {
    if (expiresAt != null && !expiresAt!.isAfter(_now())) revoke();
  }

  void revoke() {
    if (_revoked) return;
    _revoked = true;
    _timer?.cancel();
    _clockWatch?.cancel();
    if (!_closed) _revocations.add(null);
  }

  void dispose() {
    revoke();
    _closed = true;
    unawaited(_revocations.close());
  }
}
