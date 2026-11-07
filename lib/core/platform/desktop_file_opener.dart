import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import '../errors/app_exception.dart';

/// Delegates local file and directory opening to the operating system.
///
/// No shell commands are constructed from user-controlled paths. Desktop
/// platforms resolve file: URIs through their registered application handlers.
class DesktopFileOpener {
  const DesktopFileOpener();

  Future<void> play(String path) async {
    final file = File(path);
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const AppException(
        'The downloaded file is missing or is no longer a regular file.',
      );
    }
    await _open(file.absolute.uri, 'No application could open this video.');
  }

  Future<void> openContainingFolder(String path) async {
    final directory = File(path).absolute.parent;
    if (!await directory.exists()) {
      throw const AppException('The download folder no longer exists.');
    }
    await _open(directory.uri, 'Could not open the download folder.');
  }

  Future<void> _open(Uri uri, String failureMessage) async {
    try {
      if (!await launchUrl(uri)) {
        throw AppException(failureMessage);
      }
    } on AppException {
      rethrow;
    } catch (_) {
      throw AppException(failureMessage);
    }
  }
}
