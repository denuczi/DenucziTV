import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/features/updates/domain/semantic_version.dart';
import 'package:denuczi_tv/features/updates/domain/stable_release.dart';
import 'package:denuczi_tv/features/updates/data/update_platform.dart';

import 'update_fixtures.dart';

void main() {
  test('SemVer precedence handles numeric components, prereleases and build metadata', () {
    final chain = [
      '0.6.2-alpha',
      '0.6.2-alpha.1',
      '0.6.2-alpha.beta',
      '0.6.2-beta',
      '0.6.2-beta.2',
      '0.6.2-beta.11',
      '0.6.2-rc.1',
      '0.6.2',
      '0.6.10',
      '1.0.0',
    ];
    for (var i = 0; i < chain.length - 1; i++) {
      expect(
        SemanticVersion.tryParse(chain[i])!
            .compareTo(SemanticVersion.tryParse(chain[i + 1])!),
        lessThan(0),
      );
    }
    expect(
      SemanticVersion.tryParse('v0.6.2')!
          .compareTo(SemanticVersion.tryParse('0.6.2+1')!),
      0,
    );
    expect(
      SemanticVersion.tryParse('0.6.2+2')!
          .compareTo(SemanticVersion.tryParse('0.6.2+10')!),
      0,
    );
    expect(
      SemanticVersion.tryParse('1.0.0--1')!
          .compareTo(SemanticVersion.tryParse('1.0.0-2')!),
      greaterThan(0),
    );
    expect(
      SemanticVersion.tryParse('999999999999999999999.0.0')!
          .compareTo(SemanticVersion.tryParse('2.0.0')!),
      greaterThan(0),
    );
  });

  for (final tag in [
    '',
    'dev',
    'nightly',
    '1.2',
    '1.2.3.4',
    '01.2.3',
    '1.02.3',
    '1.2.03',
    '1.2.3-01',
    '1.2.3+',
    '1.2.3-',
    ' 1.2.3',
    '1.2.3\n',
    'vV1.2.3',
  ]) {
    test(
      'rejects malformed version $tag',
      () => expect(SemanticVersion.tryParse(tag), isNull),
    );
  }

  test(
    'draft, prerelease flag and prerelease SemVer are independently ineligible',
    () {
      expect(
        StableRelease.parse(releaseFixture('v9.0.0', draft: true)),
        isNull,
      );
      expect(
        StableRelease.parse(releaseFixture('v9.0.0', prerelease: true)),
        isNull,
      );
      expect(StableRelease.parse(releaseFixture('v9.0.0-rc.1')), isNull);
      expect(StableRelease.parse(releaseFixture('nightly')), isNull);
    },
  );

  test(
    'release and asset provenance is limited to the exact official repository',
    () {
      for (final url in [
        'http://github.com/denuczi/DenucziTV/releases/tag/v9.0.0',
        'https://github.com/evil/DenucziTV/releases/tag/v9.0.0',
        'https://github.com.evil.test/denuczi/DenucziTV/releases/tag/v9.0.0',
        'https://user@github.com/denuczi/DenucziTV/releases/tag/v9.0.0',
        'https://github.com/denuczi/DenucziTV/releases/tag/v9.0.0?token=secret',
      ]) {
        expect(
          () => StableRelease.parse({
            ...releaseFixture('v9.0.0'),
            'html_url': url,
          }),
          throwsFormatException,
        );
      }
      final wrongAsset = assetFixture('v9.0.0', 'denuczitv_9.0.0+1-1_amd64.deb')
        ..['browser_download_url'] = 'https://evil.test/installer.deb';
      final release = StableRelease.parse({
        ...releaseFixture('v9.0.0'),
        'assets': [wrongAsset],
      })!;
      expect(release.assetFor(UpdateTarget.debianX64), isNull);
    },
  );

  test('only explicit compatible installers are selected and source archives are rejected', () {
    final raw = releaseFixture('v9.0.0');
    raw['assets'] = [
      assetFixture('v9.0.0', 'source.zip'),
      assetFixture('v9.0.0', 'denuczi_tv.exe'),
      assetFixture('v9.0.0', 'denuczitv_9.0.0+1-1_arm64.deb'),
      assetFixture('v9.0.0', 'denuczitv_8.0.0+1-1_amd64.deb'),
      assetFixture('v9.0.0', 'denuczitv_9.0.0+2-1_amd64.deb'),
      assetFixture('v9.0.0', 'denuczitv_9.0.0+10-2_amd64.deb'),
      assetFixture('v9.0.0', 'DenucziTV-Setup-9.0.0-x64.exe'),
    ];
    final release = StableRelease.parse(raw)!;
    expect(
      release.assetFor(UpdateTarget.debianX64)!.name,
      'denuczitv_9.0.0+10-2_amd64.deb',
    );
    expect(
      release.assetFor(UpdateTarget.windowsX64)!.name,
      'DenucziTV-Setup-9.0.0-x64.exe',
    );
    expect(release.assetFor(UpdateTarget.unsupported), isNull);
    expect(
      StableRelease.parse(
        releaseFixture('v9.0.0', debian: false, windows: false),
      )!.assetFor(UpdateTarget.debianX64),
      isNull,
    );
  });

  test(
    'missing, unexpected or unpublished stable metadata fails validation',
    () {
      for (final patch in [
        {'draft': null},
        {'prerelease': 'false'},
        {'published_at': null},
        {'assets': {}},
        {'body': 42},
        {'html_url': null},
      ]) {
        expect(
          () => StableRelease.parse({...releaseFixture('v9.0.0'), ...patch}),
          throwsFormatException,
        );
      }
      final release = StableRelease.parse(
        releaseFixture('v9.0.0', notes: 'X' * 5000),
      )!;
      expect(release.notes.length, 1200);
    },
  );

  test('Linux package support is explicitly Debian/Ubuntu and their declared derivatives', () {
    expect(linuxUpdateTarget('ID=debian\n'), UpdateTarget.debianX64);
    expect(linuxUpdateTarget('ID=ubuntu\n'), UpdateTarget.debianX64);
    expect(
      linuxUpdateTarget('ID=linuxmint\nID_LIKE="ubuntu debian"\n'),
      UpdateTarget.debianX64,
    );
    expect(
      linuxUpdateTarget('ID=fedora\nID_LIKE=rhel\n'),
      UpdateTarget.unsupported,
    );
    expect(linuxUpdateTarget('ID=notdebian\n'), UpdateTarget.unsupported);
    expect(linuxUpdateTarget(''), UpdateTarget.unsupported);
  });
}
