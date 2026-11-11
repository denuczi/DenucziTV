import '../../library/domain/media_models.dart';

/// Indexes the provider's stable channel numbers once per player session.
/// Search/category filters never change the numbers or channel order.
class LiveChannelDirectory {
  LiveChannelDirectory(Iterable<MediaEntry> entries) {
    final numbered = <int, MediaEntry>{};
    final seenIds = <String>{};
    for (final entry in entries) {
      final number = entry.channelNumber;
      if (entry.kind != LibraryKind.live ||
          number == null ||
          number <= 0 ||
          numbered.containsKey(number) ||
          !seenIds.add(entry.id)) {
        continue;
      }
      numbered[number] = entry;
    }
    _channels = numbered.values.toList(growable: false)
      ..sort((a, b) => a.channelNumber!.compareTo(b.channelNumber!));
    _byNumber = Map.unmodifiable(numbered);
    _byId = Map.unmodifiable({
      for (var index = 0; index < _channels.length; index++)
        _channels[index].id: index,
    });
  }

  late final List<MediaEntry> _channels;
  late final Map<int, MediaEntry> _byNumber;
  late final Map<String, int> _byId;

  bool get isEmpty => _channels.isEmpty;
  int get length => _channels.length;
  MediaEntry? byNumber(int number) => _byNumber[number];
  MediaEntry? byId(String id) {
    final index = _byId[id];
    return index == null ? null : _channels[index];
  }

  /// Positive steps move to the next channel; negative steps go backwards.
  /// Wraparound ensures the remote remains useful at either end of the list.
  MediaEntry? stepFrom(String currentId, int delta) {
    if (_channels.isEmpty) return null;
    final index = _byId[currentId];
    if (index == null) return null;
    final next = (index + delta) % _channels.length;
    return _channels[next];
  }
}
