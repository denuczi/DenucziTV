import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/navigation/dialog_launch_guard.dart';
import '../data/github_release_api.dart';
import '../data/update_platform.dart';
import '../data/update_preferences.dart';
import '../domain/semantic_version.dart';
import '../domain/stable_release.dart';

Future<String> installedPackageVersion() async {
  final info = await PackageInfo.fromPlatform();
  if (info.version.contains('+') || info.buildNumber.isEmpty) {
    return info.version;
  }
  return '${info.version}+${info.buildNumber}';
}

class UpdateController extends ChangeNotifier {
  UpdateController({
    required this.api,
    required this.preferences,
    Future<String> Function()? installedVersion,
    Future<UpdateTarget> Function()? target,
    Future<bool> Function(Uri)? openUrl,
    DateTime Function()? clock,
  }) : _installedVersion = installedVersion ?? installedPackageVersion,
       _target = target ?? detectUpdateTarget,
       _openUrl =
           openUrl ??
           ((uri) => launchUrl(uri, mode: LaunchMode.externalApplication)),
       _now = clock ?? (() => DateTime.now().toUtc());

  final GitHubReleaseApi api;
  final UpdatePreferences preferences;
  final Future<String> Function() _installedVersion;
  final Future<UpdateTarget> Function() _target;
  final Future<bool> Function(Uri) _openUrl;
  final DateTime Function() _now;
  final dialogGuard = DialogLaunchGuard();
  SemanticVersion? installed;
  String? installedDisplay;
  UpdateTarget target = UpdateTarget.unsupported;
  DateTime? lastSuccessfulCheck;
  StableRelease? latestRelease;
  UpdateCheckResult result = const UpdateCheckResult(UpdateStatus.idle);
  bool checking = false;
  bool preferenceWarning = false;
  bool _disposed = false;
  bool _automaticStarted = false;
  bool _startupSuppressed = false;
  bool _startupClaimed = false;
  bool _startupCandidateReady = false;
  Future<void>? _initialization;
  Future<UpdateCheckResult>? _flight;
  CancelToken? _cancellation;
  CancelToken? _downloadCancellation;
  static const checkInterval = Duration(hours: 24);
  static const preferenceTimeout = Duration(seconds: 3);

  bool get isDisposed => _disposed;

  UpdateStatus get status => checking ? UpdateStatus.checking : result.status;

  void suppressStartupPrompt() => _startupSuppressed = true;

  Future<void> _initialize() => _initialization ??= _loadMetadata();

  Future<void> _loadMetadata() async {
    try {
      final version = await _installedVersion().timeout(
        const Duration(seconds: 5),
      );
      installed = SemanticVersion.tryParse(version);
      installedDisplay = installed == null ? null : version;
    } catch (_) {
      installed = null;
    }
    if (_disposed) return;
    try {
      target = await _target().timeout(const Duration(seconds: 5));
    } catch (_) {
      target = UpdateTarget.unsupported;
    }
    if (_disposed) return;
    try {
      lastSuccessfulCheck = await preferences.readLastSuccess().timeout(
        preferenceTimeout,
      );
    } catch (_) {
      preferenceWarning = true;
    }
    _emit();
  }

  Future<StableRelease?> checkAtStartup() async {
    if (_automaticStarted || _disposed) return null;
    _automaticStarted = true;
    await _initialize();
    if (_disposed) return null;
    final last = lastSuccessfulCheck;
    final time = _now();
    // A future timestamp cannot lock checks out after a clock correction.
    if (last != null &&
        !last.isAfter(time) &&
        time.difference(last) < checkInterval) {
      return null;
    }
    final checked = await checkManually();
    if (_disposed || !checked.offersUpdate) return null;
    try {
      final postponement = await preferences.readPostponement().timeout(
        preferenceTimeout,
      );
      if (postponement?.suppresses(checked.release!.version, _now()) ?? false) {
        return null;
      }
    } catch (_) {
      preferenceWarning = true;
      _emit();
      // Avoid an unsolicited prompt when the user's postponement cannot be read.
      return null;
    }
    _startupCandidateReady = true;
    return checked.release;
  }

  /// Called once when the startup result arrives, never from build/navigation.
  bool claimStartupPrompt({required bool safe}) {
    if (_disposed || !_startupCandidateReady || _startupClaimed) return false;
    _startupClaimed = true;
    _startupCandidateReady = false;
    return safe && !_startupSuppressed;
  }

  Future<UpdateCheckResult> checkManually() {
    if (_disposed) {
      return Future.value(const UpdateCheckResult(UpdateStatus.cancelled));
    }
    final running = _flight;
    if (running != null) return running;
    checking = true;
    _emit();
    final operation = _check();
    _flight = operation;
    operation.then<void>(
      (_) {
        _flight = null;
      },
      onError: (Object _, StackTrace stack) {
        _flight = null;
      },
    );
    return operation;
  }

  Future<UpdateCheckResult> _check() async {
    UpdateCheckResult checked;
    try {
      await _initialize();
      if (_disposed) return const UpdateCheckResult(UpdateStatus.cancelled);
      if (installed == null) {
        checked = const UpdateCheckResult(UpdateStatus.metadataUnavailable);
      } else {
        final cancellation = CancelToken();
        _cancellation = cancellation;
        final releases = await api.fetch(cancellation);
        if (_disposed) return const UpdateCheckResult(UpdateStatus.cancelled);
        releases.sort((a, b) {
          final order = b.version.compareTo(a.version);
          if (order != 0) return order;
          final compatibility =
              (b.assetFor(target) != null ? 1 : 0) -
              (a.assetFor(target) != null ? 1 : 0);
          return compatibility != 0 ? compatibility : a.tag.compareTo(b.tag);
        });
        final release = releases.firstOrNull;
        latestRelease = release;
        checked = release == null
            ? const UpdateCheckResult(UpdateStatus.noStableRelease)
            : release.version.compareTo(installed!) <= 0
            ? UpdateCheckResult(UpdateStatus.upToDate, release)
            : UpdateCheckResult(
                release.assetFor(target) == null
                    ? UpdateStatus.packageUnavailable
                    : UpdateStatus.updateAvailable,
                release,
              );
        final success = _now();
        lastSuccessfulCheck = success;
        try {
          await preferences.saveLastSuccess(success).timeout(preferenceTimeout);
        } catch (_) {
          preferenceWarning = true;
        }
      }
    } on UpdateRequestFailure catch (error) {
      checked = UpdateCheckResult(error.status);
    } catch (_) {
      checked = const UpdateCheckResult(UpdateStatus.serverError);
    } finally {
      checking = false;
      _cancellation = null;
    }
    if (!_disposed) {
      result = checked;
      _emit();
    }
    return checked;
  }

  /// The dialog has already closed; storage failure never reopens it.
  Future<void> postpone(StableRelease release) async {
    _startupClaimed = true;
    if (_disposed) return;
    try {
      await preferences
          .postpone(release.version, _now())
          .timeout(preferenceTimeout);
    } catch (_) {
      preferenceWarning = true;
      _emit();
    }
  }

  Future<bool> download(StableRelease release) async {
    if (_disposed ||
        installed == null ||
        release.version.compareTo(installed!) <= 0 ||
        !release.version.isStable ||
        !StableRelease.officialUrl(release.url, ['tag', release.tag])) {
      return false;
    }
    if (release.assetFor(target) == null || _downloadCancellation != null) {
      return false;
    }
    final cancellation = CancelToken();
    _downloadCancellation = cancellation;
    try {
      final verified = await api.verifyRelease(release.tag, cancellation);
      if (_disposed ||
          cancellation.isCancelled ||
          verified == null ||
          verified.version.compareTo(installed!) <= 0) {
        return false;
      }
      final asset = verified.assetFor(target);
      if (asset == null ||
          !StableRelease.officialUrl(asset.url, [
            'download',
            verified.tag,
            asset.name,
          ])) {
        return false;
      }
      return await _launch(asset.url);
    } catch (_) {
      return false;
    } finally {
      _downloadCancellation = null;
    }
  }

  void cancelDownload() => _downloadCancellation?.cancel();

  /// Uses the same injected, timeout-bounded browser launcher as official
  /// downloads. Markdown links never trigger a download or run an installer.
  Future<bool> openReleaseNotesLink(Uri uri) async {
    if (_disposed ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443)) {
      return false;
    }
    return _launch(uri);
  }

  Future<bool> openNotes(StableRelease release) async {
    if (_disposed ||
        installed == null ||
        release.version.compareTo(installed!) <= 0 ||
        !StableRelease.officialUrl(release.url, ['tag', release.tag])) {
      return false;
    }
    return _launch(release.url);
  }

  Future<bool> _launch(Uri uri) async {
    try {
      return await _openUrl(uri).timeout(const Duration(seconds: 10));
    } catch (_) {
      return false;
    }
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancellation?.cancel();
    _downloadCancellation?.cancel();
    api.dispose();
    super.dispose();
  }
}
