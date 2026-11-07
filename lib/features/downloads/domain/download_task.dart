/// A public, credential-free snapshot of a media transfer.
///
/// Provider URLs are deliberately never serialized because they may contain
/// authentication credentials in their paths.
enum DownloadStatus {
  queued,
  downloading,
  completed,
  failed,
  cancelled,
  interrupted,
}

class DownloadTask {
  static const Object _unchanged = Object();
  const DownloadTask({
    required this.id,
    required this.title,
    required this.destination,
    required this.status,
    this.bytesReceived = 0,
    this.totalBytes,
    this.message,
    this.mediaKey,
    this.etag,
    this.lastModified,
  });

  final String id;
  final String title;
  final String destination;
  final DownloadStatus status;
  final int bytesReceived;
  final int? totalBytes;
  final String? message;

  /// Opaque account and provider-media identifier, never a credential-bearing URL.
  final String? mediaKey;

  /// Non-secret HTTP validators used to avoid combining different media files.
  final String? etag;
  final String? lastModified;

  double? get progress => totalBytes == null || totalBytes! <= 0
      ? null
      : (bytesReceived / totalBytes!).clamp(0.0, 1.0);

  /// A percentage is unavailable until the server reports a valid length.
  int? get percentComplete {
    final value = progress;
    return value == null ? null : (value * 100).floor().clamp(0, 100).toInt();
  }

  int? get remainingBytes {
    final total = totalBytes;
    if (total == null || total <= 0) {
      return null;
    }
    return (total - bytesReceived).clamp(0, total).toInt();
  }

  DownloadTask copyWith({
    DownloadStatus? status,
    String? destination,
    int? bytesReceived,
    Object? totalBytes = _unchanged,
    Object? message = _unchanged,
    Object? etag = _unchanged,
    Object? lastModified = _unchanged,
  }) => DownloadTask(
    id: id,
    title: title,
    mediaKey: mediaKey,
    etag: identical(etag, _unchanged) ? this.etag : etag as String?,
    lastModified: identical(lastModified, _unchanged)
        ? this.lastModified
        : lastModified as String?,
    destination: destination ?? this.destination,
    status: status ?? this.status,
    bytesReceived: bytesReceived ?? this.bytesReceived,
    totalBytes: identical(totalBytes, _unchanged)
        ? this.totalBytes
        : totalBytes as int?,
    message: identical(message, _unchanged) ? this.message : message as String?,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'destination': destination,
    'status': status.name,
    'bytesReceived': bytesReceived,
    'totalBytes': totalBytes,
    'message': message,
    if (mediaKey != null) 'mediaKey': mediaKey,
    if (etag != null) 'etag': etag,
    if (lastModified != null) 'lastModified': lastModified,
  };

  factory DownloadTask.fromJson(Map<String, dynamic> value) {
    final status = DownloadStatus.values.firstWhere(
      (item) => item.name == value['status'],
      orElse: () => DownloadStatus.interrupted,
    );
    return DownloadTask(
      id: value['id'] as String,
      title: value['title'] as String,
      destination: value['destination'] as String,
      status:
          status == DownloadStatus.queued ||
              status == DownloadStatus.downloading
          ? DownloadStatus.interrupted
          : status,
      bytesReceived: (value['bytesReceived'] as num?)?.toInt() ?? 0,
      totalBytes: (value['totalBytes'] as num?)?.toInt(),
      message:
          status == DownloadStatus.queued ||
              status == DownloadStatus.downloading
          ? 'Interrupted when the application closed. Start a new download from the catalog.'
          : value['message'] as String?,
      mediaKey: value['mediaKey'] is String
          ? value['mediaKey'] as String
          : null,
      etag: value['etag'] is String ? value['etag'] as String : null,
      lastModified: value['lastModified'] is String
          ? value['lastModified'] as String
          : null,
    );
  }
}
