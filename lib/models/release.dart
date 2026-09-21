import 'provider_kind.dart';

class SourceMirror {
  const SourceMirror({
    required this.label,
    required this.url,
    this.headers = const {},
    this.directFile = false,
  });

  final String label;
  final String url;
  final Map<String, String> headers;
  final bool directFile;
}

class Release {
  const Release({
    required this.kind,
    required this.filename,
    this.quality,
    this.codec,
    this.language,
    this.sizeBytes,
    this.season,
    this.episode,
    this.mirrors = const [],
    this.resourceId,
  });

  final ProviderKind kind;
  final String filename;
  final String? quality;
  final String? codec;
  final String? language;
  final int? sizeBytes;
  final int? season;
  final int? episode;
  final List<SourceMirror> mirrors;
  final String? resourceId;

  bool get isMultiResolution {
    final value = quality?.trim().toLowerCase();
    return value == 'multi' || value == 'multi-res';
  }

  int get resolution {
    final raw = quality?.trim();
    if (raw == null || raw.isEmpty) return 1080;
    final lower = raw.toLowerCase();
    if (lower == '4k' || lower == 'uhd') return 2160;
    return int.tryParse(lower.replaceAll(RegExp(r'p$'), '')) ?? 1080;
  }

  int get sortResolution => isMultiResolution ? -1 : resolution;

  String get sourceLabel =>
      mirrors.isNotEmpty ? mirrors.first.label : kind.label;

  String? get directUrl => mirrors.isNotEmpty ? mirrors.first.url : null;

  String get sizeLabel {
    final bytes = sizeBytes;
    if (bytes == null || bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 100 || unit == 0 ? 0 : 1)} ${units[unit]}';
  }
}

class SubtitleOption {
  const SubtitleOption({required this.name, required this.url});

  final String name;
  final String url;
}

class PlaybackSource {
  const PlaybackSource({
    required this.kind,
    required this.url,
    this.headers = const {},
    this.subtitle,
    this.subtitles = const [],
    required this.sourceLabel,
  });

  final ProviderKind kind;
  final String url;
  final Map<String, String> headers;
  final String? subtitle;
  final List<SubtitleOption> subtitles;
  final String sourceLabel;

  bool get isDash => url.contains('.mpd') || url.contains('/dash/');

  bool get isHls => url.contains('.m3u8');
}
