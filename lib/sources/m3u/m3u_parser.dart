class Channel {
  const Channel({required this.name, required this.url, this.id = '', this.logoUrl, this.group});

  final String name;
  final String url;
  final String id;
  final String? logoUrl;
  final String? group;

  @override
  bool operator ==(Object other) => other is Channel && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

const int maxPlaylistBytes = 15 * 1024 * 1024;

Map<String, String> parseAttributes(String raw) {
  final attributes = <String, String>{};
  final buffer = StringBuffer();
  var key = '';
  var inQuotes = false;

  for (var i = 0; i < raw.length; i++) {
    final char = raw[i];

    if (char == '"') {
      inQuotes = !inQuotes;
      if (!inQuotes && key.isNotEmpty) {
        attributes[key.trim().toLowerCase()] = buffer.toString();
        buffer.clear();
        key = '';
      }
      continue;
    }

    if (!inQuotes && char == '=') {
      key = buffer.toString().split(' ').last;
      buffer.clear();
      continue;
    }

    buffer.write(char);
  }

  return attributes;
}

List<Channel> parseM3u(String content) {
  final lines = content.split(RegExp(r'\r?\n'));
  final channels = <Channel>[];
  final seen = <String>{};

  String? pendingName;
  Map<String, String> pendingAttributes = const {};

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;

    if (line.startsWith('#EXTINF')) {
      final commaIndex = _titleSeparatorIndex(line);
      if (commaIndex < 0) continue;

      pendingAttributes = parseAttributes(line.substring(0, commaIndex));
      pendingName = line.substring(commaIndex + 1).trim();
      continue;
    }

    if (line.startsWith('#')) continue;

    final name = pendingName;
    if (name == null || name.isEmpty) {
      pendingName = null;
      pendingAttributes = const {};
      continue;
    }

    if (!seen.add(line)) {
      pendingName = null;
      pendingAttributes = const {};
      continue;
    }

    channels.add(
      Channel(
        name: name,
        url: line,
        id: pendingAttributes['tvg-id'] ?? '',
        logoUrl: pendingAttributes['tvg-logo'],
        group: pendingAttributes['group-title'],
      ),
    );

    pendingName = null;
    pendingAttributes = const {};
  }

  return channels;
}

int _titleSeparatorIndex(String line) {
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final char = line[i];
    if (char == '"') inQuotes = !inQuotes;
    if (char == ',' && !inQuotes) return i;
  }
  return -1;
}

List<String> groupsOf(List<Channel> channels) {
  final groups = <String>{};
  for (final channel in channels) {
    final group = channel.group?.trim();
    if (group != null && group.isNotEmpty) groups.add(group);
  }
  final sorted = groups.toList()..sort();
  return sorted;
}

List<Channel> filterChannels(List<Channel> channels, {String? group, String query = ''}) {
  final needle = query.trim().toLowerCase();

  return channels.where((channel) {
    if (group != null && group.isNotEmpty && channel.group != group) {
      return false;
    }
    if (needle.isEmpty) return true;
    return channel.name.toLowerCase().contains(needle) ||
        (channel.group?.toLowerCase().contains(needle) ?? false);
  }).toList();
}
