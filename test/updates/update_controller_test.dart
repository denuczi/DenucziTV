import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:denuczi_tv/features/updates/application/update_controller.dart';
import 'package:denuczi_tv/features/updates/data/update_preferences.dart';
import 'package:denuczi_tv/features/updates/domain/stable_release.dart';
import 'package:denuczi_tv/features/updates/domain/semantic_version.dart';

import 'update_fixtures.dart';

class _FailingWrites extends UpdatePreferences {
  _FailingWrites(super.preferences);
  @override
  Future<void> saveLastSuccess(DateTime time) async =>
      throw StateError('Preferences unavailable');
  @override
  Future<void> postpone(SemanticVersion version, DateTime time) async =>
      throw StateError('Preferences unavailable');
}

void main() {
  late SharedPreferencesAsync preferences;
  late UpdatePreferences storage;
  late FakeReleaseApi api;
  late DateTime time;
  late List<Uri> opened;
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    preferences = SharedPreferencesAsync();
    storage = UpdatePreferences(preferences);
    api = FakeReleaseApi();
    time = DateTime.utc(2099, 1, 1);
    opened = [];
  });
  UpdateController create({
    String installed = '0.6.2+1',
    UpdateTarget target = UpdateTarget.debianX64,
    FakeReleaseApi? transport,
    UpdatePreferences? persistence,
    Future<bool> Function(Uri)? launch,
  }) {
    final controller = UpdateController(
      api: transport ?? api,
      preferences: persistence ?? storage,
      installedVersion: () async => installed,
      target: () async => target,
      clock: () => time,
      openUrl:
          launch ??
          (uri) async {
            opened.add(uri);
            return true;
          },
    );
    addTearDown(controller.dispose);
    return controller;
  }

  test('the default installed version comes from package metadata, including build number', () async {
    PackageInfo.setMockInitialValues(
      appName: 'DenucziTV',
      packageName: 'test.denuczitv',
      version: '0.6.2',
      buildNumber: '7',
      buildSignature: '',
    );
    expect(await installedPackageVersion(), '0.6.2+7');
    PackageInfo.setMockInitialValues(
      appName: 'DenucziTV',
      packageName: 'test.denuczitv',
      version: '0.6.2-rc.1',
      buildNumber: '1',
      buildSignature: '',
    );
    expect(await installedPackageVersion(), '0.6.2-rc.1+1');
  });

  test(
    'empty and prerelease-only responses are successful no-stable states',
    () async {
      api.releases = [];
      final updates = create();
      expect(await updates.checkAtStartup(), isNull);
      expect(updates.status, UpdateStatus.noStableRelease);
      expect(await storage.readLastSuccess(), time);
      api.releases = [
        releaseFixture('v99.0.0', prerelease: true),
        releaseFixture('v10.0.0', draft: true),
        releaseFixture('nightly'),
      ];
      expect(
        (await updates.checkManually()).status,
        UpdateStatus.noStableRelease,
      );
      expect(opened, isEmpty);
    },
  );

  test('selects the greatest stable SemVer rather than publication order or newer prereleases', () async {
    api.releases = [
      releaseFixture('v0.6.3'),
      {...releaseFixture('v0.6.10'), 'published_at': '2020-01-01T00:00:00Z'},
      releaseFixture('v99.0.0', prerelease: true),
      releaseFixture('v100.0.0', draft: true),
    ];
    final updates = create();
    final release = await updates.checkAtStartup();
    expect(release!.version.canonical, '0.6.10');
    expect(updates.status, UpdateStatus.updateAvailable);
    expect(updates.installedDisplay, '0.6.2+1');
  });

  for (final tag in ['v0.6.2', '0.6.2+99', 'v0.5.9']) {
    test('equal or older stable $tag is not offered', () async {
      api.releases = [releaseFixture(tag)];
      final updates = create();
      expect(await updates.checkAtStartup(), isNull);
      expect(updates.status, UpdateStatus.upToDate);
      expect(await updates.download(updates.latestRelease!), isFalse);
      expect(opened, isEmpty);
    });
  }

  test('an explicit prerelease installation can upgrade to the same numeric stable version', () async {
    api.releases = [releaseFixture('v0.6.2')];
    final updates = create(installed: '0.6.2-rc.1+1');
    expect((await updates.checkAtStartup())!.version.canonical, '0.6.2');
    expect(updates.status, UpdateStatus.updateAvailable);
  });

  test('the highest stable without an installer never substitutes an older package', () async {
    api.releases = [
      releaseFixture('v9.0.0', debian: false),
      releaseFixture('v8.0.0'),
    ];
    final updates = create();
    final checked = await updates.checkManually();
    expect(checked.status, UpdateStatus.packageUnavailable);
    expect(checked.release!.version.canonical, '9.0.0');
    expect(await updates.download(checked.release!), isFalse);
    expect(await updates.openNotes(checked.release!), isTrue);
    expect(opened.single.path, '/denuczi/DenucziTV/releases/tag/v9.0.0');
  });

  test('24-hour startup throttling does not block manual checks', () async {
    await storage.saveLastSuccess(time.subtract(const Duration(hours: 23)));
    final updates = create();
    expect(await updates.checkAtStartup(), isNull);
    expect(api.requests, 0);
    expect(
      (await updates.checkManually()).status,
      UpdateStatus.updateAvailable,
    );
    expect(api.requests, 1);
    expect(await updates.checkAtStartup(), isNull);
    expect(api.requests, 1);
  });

  test('simultaneous checks share one request and claim at most one startup dialog', () async {
    api.pending = Completer<void>();
    final updates = create();
    final startup = updates.checkAtStartup();
    final first = updates.checkManually();
    final second = updates.checkManually();
    expect(first, same(second));
    expect(updates.checking, isTrue);
    api.pending!.complete();
    await Future.wait([first, second]);
    await startup;
    expect(api.requests, 1);
    expect(updates.claimStartupPrompt(safe: true), isTrue);
    expect(updates.claimStartupPrompt(safe: true), isFalse);
  });

  test('manual-only results cannot claim a startup prompt', () async {
    final updates = create();
    await updates.checkManually();
    expect(updates.claimStartupPrompt(safe: true), isFalse);
  });

  test(
    'critical interaction permanently suppresses only the startup prompt',
    () async {
      final updates = create();
      updates.suppressStartupPrompt();
      await updates.checkAtStartup();
      expect(updates.claimStartupPrompt(safe: true), isFalse);
      expect((await updates.checkManually()).offersUpdate, isTrue);
    },
  );

  test(
    'unsafe completion is consumed instead of delayed until playback ends',
    () async {
      final updates = create();
      await updates.checkAtStartup();
      expect(updates.claimStartupPrompt(safe: false), isFalse);
      expect(updates.claimStartupPrompt(safe: true), isFalse);
    },
  );

  test(
    'postponement persists for seven days but manual checks bypass it',
    () async {
      final updates = create();
      final release = await updates.checkAtStartup();
      await updates.postpone(release!);
      expect(opened, isEmpty);
      final saved = await storage.readPostponement();
      expect(saved!.until.difference(saved.createdAt), const Duration(days: 7));
      time = time.add(const Duration(hours: 25));
      final restartedApi = FakeReleaseApi();
      final restarted = create(transport: restartedApi);
      expect(await restarted.checkAtStartup(), isNull);
      expect(restartedApi.requests, 1);
      expect((await restarted.checkManually()).offersUpdate, isTrue);
      time = time.add(const Duration(days: 7));
      final later = create(transport: FakeReleaseApi());
      expect(await later.checkAtStartup(), isNotNull);
    },
  );

  test('postponement expires at exactly seven days and never suppresses a higher version', () async {
    final version = SemanticVersion.tryParse('9.0.0')!;
    await storage.postpone(version, time);
    final saved = (await storage.readPostponement())!;
    expect(
      saved.suppresses(
        version,
        time
            .add(const Duration(days: 7))
            .subtract(const Duration(microseconds: 1)),
      ),
      isTrue,
    );
    expect(
      saved.suppresses(version, time.add(const Duration(days: 7))),
      isFalse,
    );
    expect(
      saved.suppresses(SemanticVersion.tryParse('10.0.0')!, time),
      isFalse,
    );
    expect(
      saved.suppresses(version, time.subtract(const Duration(seconds: 1))),
      isFalse,
    );
  });

  test(
    'a genuinely newer stable version bypasses an older version postponement',
    () async {
      final updates = create();
      await updates.postpone((await updates.checkAtStartup())!);
      time = time.add(const Duration(hours: 25));
      final nextApi = FakeReleaseApi()..releases = [releaseFixture('v10.0.0')];
      final next = create(transport: nextApi);
      expect((await next.checkAtStartup())!.version.canonical, '10.0.0');
    },
  );

  test('future timestamps and corrupt preferences cannot lock out checks indefinitely', () async {
    await storage.saveLastSuccess(time.add(const Duration(days: 3)));
    await preferences.setString(
      UpdatePreferences.postponementKey,
      'invalid JSON',
    );
    final updates = create();
    expect(await updates.checkAtStartup(), isNotNull);
    expect(api.requests, 1);
    expect(updates.lastSuccessfulCheck, time);
  });

  for (final failure in [
    UpdateStatus.offline,
    UpdateStatus.timedOut,
    UpdateStatus.rateLimited,
    UpdateStatus.serverError,
    UpdateStatus.invalidResponse,
  ]) {
    test(
      '$failure never becomes up-to-date or overwrites a successful timestamp',
      () async {
        final previous = time.subtract(const Duration(days: 2));
        await storage.saveLastSuccess(previous);
        api.failure = failure;
        final updates = create();
        expect(await updates.checkAtStartup(), isNull);
        expect(updates.status, failure);
        expect(updates.checking, isFalse);
        expect(await storage.readLastSuccess(), previous);
      },
    );
  }

  test('metadata failure does not use the streaming identity fallback as an installed version', () async {
    final updates = UpdateController(
      api: api,
      preferences: storage,
      installedVersion: () async => throw StateError('No package metadata'),
      target: () async => UpdateTarget.debianX64,
    );
    addTearDown(updates.dispose);
    expect(
      (await updates.checkManually()).status,
      UpdateStatus.metadataUnavailable,
    );
    expect(api.requests, 0);
    expect(updates.installed, isNull);
  });

  test('preference write failure does not force installation or reopen a declined update', () async {
    final updates = create(persistence: _FailingWrites(preferences));
    final release = await updates.checkAtStartup();
    await updates.postpone(release!);
    expect(updates.preferenceWarning, isTrue);
    expect(updates.claimStartupPrompt(safe: true), isFalse);
    expect(opened, isEmpty);
  });

  test(
    'downloads use the official asset and launcher failures are contained',
    () async {
      final updates = create();
      final release = (await updates.checkManually()).release!;
      expect(await updates.download(release), isTrue);
      expect(
        opened.single.toString(),
        'https://github.com/denuczi/DenucziTV/releases/download/v9.0.0/denuczitv_9.0.0+1-1_amd64.deb',
      );
      final failing = create(
        transport: FakeReleaseApi(),
        launch: (_) async => throw StateError('Private exception'),
      );
      final failedRelease = (await failing.checkManually()).release!;
      expect(await failing.download(failedRelease), isFalse);
    },
  );

  test(
    'a release changed to prerelease after discovery is never downloaded',
    () async {
      final updates = create();
      final release = (await updates.checkManually()).release!;
      api.releases = [releaseFixture('v9.0.0', prerelease: true)];
      expect(await updates.download(release), isFalse);
      expect(api.verifications, 1);
      expect(opened, isEmpty);
    },
  );

  test(
    'cancelling a pending download verification prevents a late browser launch',
    () async {
      final updates = create();
      final release = (await updates.checkManually()).release!;
      api.pendingVerification = Completer<void>();
      final download = updates.download(release);
      await Future<void>.delayed(Duration.zero);
      updates.cancelDownload();
      expect(api.verificationCancellation!.isCancelled, isTrue);
      api.pendingVerification!.complete();
      expect(await download, isFalse);
      expect(opened, isEmpty);
    },
  );

  test('disposal cancels HTTP and suppresses late notifications', () async {
    api.pending = Completer<void>();
    final updates = UpdateController(
      api: api,
      preferences: storage,
      installedVersion: () async => '0.6.2+1',
      target: () async => UpdateTarget.debianX64,
    );
    var notifications = 0;
    updates.addListener(() => notifications++);
    final check = updates.checkManually();
    for (var i = 0; i < 100 && api.requests == 0; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(api.requests, 1);
    updates.dispose();
    final before = notifications;
    expect(api.disposed, isTrue);
    expect(api.cancellation!.isCancelled, isTrue);
    api.pending!.complete();
    expect((await check).status, UpdateStatus.cancelled);
    expect(notifications, before);
  });
  test(
    'manual-only results cannot claim an automatic startup prompt',
    () async {
      final updates = create();
      expect((await updates.checkManually()).offersUpdate, isTrue);
      expect(updates.claimStartupPrompt(safe: true), isFalse);
    },
  );
}
