import 'dart:async';

import 'package:dio/dio.dart';
import 'package:denuczi_tv/core/errors/app_exception.dart';
import 'package:denuczi_tv/core/models/account.dart';
import 'package:denuczi_tv/core/storage/account_store.dart';
import 'package:denuczi_tv/features/library/data/xtream_api.dart';
import 'package:denuczi_tv/features/library/domain/media_models.dart';

class MemoryProtectedSecrets implements AccountSecrets {
  final values = <String, String>{};
  int writes = 0;
  bool failWrites = false;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('Simulated key store failure');
    writes++;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class CatalogTestApi extends XtreamApi {
  CatalogTestApi(super.network);
  final categoryRequests = <LibraryKind>[];
  final catalogRequests = <LibraryKind>[];
  int authenticationRequests = 0;
  String? failKind;
  bool rejectAuthentication = false;
  Completer<void>? block;
  @override
  Future<AccountStatus> authenticate(AccountCredentials credentials) async {
    authenticationRequests++;
    await block?.future;
    if (rejectAuthentication) {
      throw const AppException('Account access is denied or inactive.');
    }
    return AccountStatus(authorized: true, expiration: DateTime.utc(2098));
  }

  @override
  Future<List<MediaCategory>> categories(
    AccountCredentials credentials,
    LibraryKind kind, {
    CancelToken? cancelToken,
  }) async {
    categoryRequests.add(kind);
    return [MediaCategory(id: credentials.username, name: 'Test category')];
  }

  @override
  Future<List<MediaEntry>> catalog(
    AccountCredentials credentials,
    LibraryKind kind, {
    CancelToken? cancelToken,
  }) async {
    catalogRequests.add(kind);
    if (failKind == kind.name) {
      throw const AppException('The provider returned an invalid catalog.');
    }
    return [
      MediaEntry(
        id: '100',
        title: credentials.username,
        kind: kind,
        sourceScope: credentials.sourceScope,
      ),
    ];
  }
}
