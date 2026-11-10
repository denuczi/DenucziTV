import 'package:flutter_test/flutter_test.dart';

import 'package:denuczi_tv/features/updates/domain/update_channel.dart';

void main() {
  test('normal desktop builds keep the GitHub release updater', () {
    expect(updateChannelFor(storeBuild: false), UpdateChannel.githubReleases);
  });

  test('Microsoft Store builds use Store-managed updates', () {
    expect(updateChannelFor(storeBuild: true), UpdateChannel.microsoftStore);
  });

  test('the Store build flag is compile-time and disabled in tests', () {
    expect(AppDistribution.storeBuild, isFalse);
    expect(AppDistribution.updateChannel, UpdateChannel.githubReleases);
    expect(AppDistribution.usesGitHubUpdater, isTrue);
  });
}
