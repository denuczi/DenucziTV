import 'dart:async';

import 'package:dio/dio.dart';
import 'package:denuczi_tv/features/updates/data/github_release_api.dart';
import 'package:denuczi_tv/features/updates/domain/stable_release.dart';

Map<String, Object?> releaseFixture(
  String tag, {
  bool prerelease = false,
  bool draft = false,
  bool debian = true,
  bool windows = true,
  String? notes = 'Small, fictional test release. Never publish this fixture.',
}) {
  final version = tag
      .replaceFirst(RegExp(r'^v'), '')
      .split('+')
      .first
      .split('-')
      .first;
  final names = [
    if (debian) 'denuczitv_$version+1-1_amd64.deb',
    if (windows) 'DenucziTV-Setup-$version-x64.exe',
  ];
  return {
    'tag_name': tag,
    'draft': draft,
    'prerelease': prerelease,
    'published_at': '2026-01-01T00:00:00Z',
    'html_url': 'https://github.com/denuczi/DenucziTV/releases/tag/$tag',
    'body': notes,
    'assets': [for (final name in names) assetFixture(tag, name)],
  };
}

Map<String, Object?> assetFixture(String tag, String name) => {
  'name': name,
  'state': 'uploaded',
  'size': 1024,
  'browser_download_url':
      'https://github.com/denuczi/DenucziTV/releases/download/$tag/$name',
};

class FakeReleaseApi extends GitHubReleaseApi {
  List<Object?> releases = [releaseFixture('v9.0.0')];
  UpdateStatus? failure;
  Completer<void>? pending;
  Completer<void>? pendingVerification;
  CancelToken? verificationCancellation;
  int requests = 0;
  int verifications = 0;
  bool disposed = false;
  CancelToken? cancellation;

  @override
  Future<List<StableRelease>> fetch(CancelToken token) async {
    requests++;
    cancellation = token;
    await pending?.future;
    if (token.isCancelled) {
      throw const UpdateRequestFailure(UpdateStatus.cancelled);
    }
    if (failure case final status?) throw UpdateRequestFailure(status);
    return releases
        .map(StableRelease.parse)
        .whereType<StableRelease>()
        .toList();
  }

  @override
  Future<StableRelease?> verifyRelease(String tag, CancelToken token) async {
    verifications++;
    verificationCancellation = token;
    await pendingVerification?.future;
    if (token.isCancelled) {
      throw const UpdateRequestFailure(UpdateStatus.cancelled);
    }
    if (failure case final status?) throw UpdateRequestFailure(status);
    for (final raw in releases) {
      if (raw is Map && raw['tag_name'] == tag) return StableRelease.parse(raw);
    }
    return null;
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}
