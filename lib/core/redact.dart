String redactUrl(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.host.isEmpty) return '[redacted]';
  final scheme = uri.scheme.isEmpty ? 'https' : uri.scheme;
  return '$scheme://${uri.host}';
}

String redactPath(String raw) {
  final normalized = raw.replaceAll(r'\', '/');
  final match = RegExp(r'^([A-Za-z]:)?/(Users|home)/[^/]+').firstMatch(normalized);
  if (match == null) return normalized;
  return '~${normalized.substring(match.end)}';
}

String describePlaylist(int channelCount) => 'playlist($channelCount channels)';
