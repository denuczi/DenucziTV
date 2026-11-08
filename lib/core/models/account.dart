import 'protected_access_grant.dart';

enum AccountConnectionType { xtream, protectedSingleLink }

class Account {
  const Account({
    required this.id,
    required this.label,
    required this.serverUrl,
    required this.username,
    this.connectionType = AccountConnectionType.xtream,
  });

  final String id;
  final String label;
  final String serverUrl;
  final String username;
  final AccountConnectionType connectionType;
  bool get isProtected =>
      connectionType == AccountConnectionType.protectedSingleLink;

  Map<String, String> toJson() => {
    'id': id,
    'label': label,
    'serverUrl': isProtected ? '' : serverUrl,
    'username': isProtected ? '' : username,
    if (isProtected) 'connectionType': connectionType.name,
  };

  factory Account.fromJson(Map<String, dynamic> json) => Account(
    id: json['id'] as String,
    label: json['label'] as String,
    serverUrl: json['serverUrl'] as String,
    username: json['username'] as String,
    connectionType: json['connectionType'] == 'protectedSingleLink'
        ? AccountConnectionType.protectedSingleLink
        : AccountConnectionType.xtream,
  );
}

class AccountCredentials {
  const AccountCredentials({
    required this.serverUrl,
    required this.username,
    required this.password,
    required this.label,
    this.protected = false,
    this.sourceScope = '',
    this.linkExpiresAt,
    this.accessGrant,
  });

  final String serverUrl;
  final String username;
  final String password;
  final String label;
  final bool protected;
  final String sourceScope;
  final DateTime? linkExpiresAt;
  final ProtectedAccessGrant? accessGrant;

  bool get linkExpired =>
      protected &&
      (!(accessGrant?.usable ?? true) ||
          (linkExpiresAt != null &&
              !linkExpiresAt!.isAfter(DateTime.now().toUtc())));
}

class AccountStatus {
  const AccountStatus({
    required this.authorized,
    this.status,
    this.createdAt,
    this.expiration,
    this.activeConnections,
    this.maxConnections,
    this.isTrial,
    this.serverTimezone,
    this.allowedFormats = const [],
  });

  final bool authorized;
  final String? status;
  final DateTime? createdAt;
  final DateTime? expiration;
  final int? activeConnections;
  final int? maxConnections;
  final bool? isTrial;
  final String? serverTimezone;
  final List<String> allowedFormats;

  Map<String, Object?> toJson() => {
    'authorized': authorized,
    'status': status,
    'createdAt': createdAt?.toIso8601String(),
    'expiration': expiration?.toIso8601String(),
    'activeConnections': activeConnections,
    'maxConnections': maxConnections,
    'isTrial': isTrial,
    'serverTimezone': serverTimezone,
    'allowedFormats': allowedFormats,
  };

  factory AccountStatus.fromJson(Map<String, dynamic> json) => AccountStatus(
    authorized: json['authorized'] == true,
    status: json['status'] as String?,
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    expiration: DateTime.tryParse(json['expiration'] as String? ?? ''),
    activeConnections: (json['activeConnections'] as num?)?.toInt(),
    maxConnections: (json['maxConnections'] as num?)?.toInt(),
    isTrial: json['isTrial'] as bool?,
    serverTimezone: json['serverTimezone'] as String?,
    allowedFormats:
        (json['allowedFormats'] as List?)?.whereType<String>().toList() ??
        const [],
  );
}
