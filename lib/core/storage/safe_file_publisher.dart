import 'dart:io';

/// Publishes a completed temporary file without replacing an existing file.
///
/// Dart's [File.rename] replaces existing targets on some platforms. Creating
/// the destination exclusively avoids that data-loss scenario. This fallback
/// deliberately copies bytes rather than claiming atomic no-replace semantics:
/// the new destination is visible while it is being populated. A process crash
/// during publication can leave a partial destination that must be inspected.
/// The source remains intact until all bytes are flushed successfully.
class SafeFilePublisher {
  const SafeFilePublisher();

  Future<void> publish(File source, String destination) async {
    final target = File(destination);
    // Exclusive creation is atomic with respect to other creators. If another
    // application has already created the path, never open or modify it.
    await target.create(exclusive: true);
    var published = false;
    RandomAccessFile? output;
    try {
      output = await target.open(mode: FileMode.writeOnly);
      await for (final chunk in source.openRead()) {
        await output.writeFrom(chunk);
      }
      await output.flush();
      await output.close();
      output = null;
      if (await source.length() != await target.length()) {
        throw const FileSystemException('Published file size mismatch');
      }
      published = true;
    } finally {
      if (output != null) {
        try {
          await output.close();
        } on FileSystemException {
          // Avoid hiding the write or flush error that caused cleanup.
        }
      }
      if (!published) {
        try {
          await target.delete();
        } on FileSystemException {
          // Preserve the original error. An incomplete destination may remain.
        }
      }
    }
    // A cleanup failure must not make a fully published file look incomplete.
    try {
      await source.delete();
    } on FileSystemException {
      // An orphaned temporary file can be removed during maintenance.
    }
  }
}
