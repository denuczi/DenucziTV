import 'dart:io';

import '../domain/download_task.dart';

/// Sizes of files tracked by download history, not the entire download folder.
///
/// Historical records can outlive their files. The inspector only counts real,
/// regular files that still exist and never follows symbolic links.
class DownloadStorageSummary {
  const DownloadStorageSummary({
    required this.completedFiles,
    required this.completedBytes,
    required this.partialFiles,
    required this.partialBytes,
    required this.unavailableFiles,
  });

  final int completedFiles;
  final int completedBytes;
  final int partialFiles;
  final int partialBytes;
  final int unavailableFiles;

  int get totalBytes => completedBytes + partialBytes;
}

class DownloadStorageInspector {
  const DownloadStorageInspector();

  /// Inspects disk state asynchronously without blocking widget builds.
  /// A historical path is counted at most once, even if multiple tasks refer
  /// to it. In-progress and queued files are omitted until they are terminal.
  Future<DownloadStorageSummary> inspect(List<DownloadTask> tasks) async {
    final counted = <String>{};
    var completedFiles = 0;
    var completedBytes = 0;
    var partialFiles = 0;
    var partialBytes = 0;
    var unavailableFiles = 0;

    for (final task in tasks) {
      if (task.status == DownloadStatus.queued ||
          task.status == DownloadStatus.downloading) {
        continue;
      }
      final completed = task.status == DownloadStatus.completed;
      final path = completed ? task.destination : '${task.destination}.part';
      if (!counted.add(path)) {
        continue;
      }
      try {
        final type = await FileSystemEntity.type(path, followLinks: false);
        if (type == FileSystemEntityType.notFound) {
          if (completed) {
            unavailableFiles++;
          }
          continue;
        }
        if (type != FileSystemEntityType.file) {
          unavailableFiles++;
          continue;
        }
        final length = await File(path).length();
        if (completed) {
          completedFiles++;
          completedBytes += length;
        } else {
          partialFiles++;
          partialBytes += length;
        }
      } on FileSystemException {
        unavailableFiles++;
      }
    }
    return DownloadStorageSummary(
      completedFiles: completedFiles,
      completedBytes: completedBytes,
      partialFiles: partialFiles,
      partialBytes: partialBytes,
      unavailableFiles: unavailableFiles,
    );
  }
}
