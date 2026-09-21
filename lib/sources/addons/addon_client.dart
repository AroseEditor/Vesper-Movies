import 'package:dio/dio.dart';

import '../../core/errors.dart';
import '../../models/provider_kind.dart';
import '../../models/release.dart';
import '../moviebox/adapt.dart';

class InstalledAddon {
  const InstalledAddon({
    required this.manifestUrl,
    required this.name,
    this.description,
    this.enabled = true,
    this.providesStream = true,
  });

  final String manifestUrl;
  final String name;
  final String? description;
  final bool enabled;
  final bool providesStream;

  String get baseUrl {
    var base = manifestUrl.trim();
    if (base.endsWith('/manifest.json')) {
      base = base.substring(0, base.length - '/manifest.json'.length);
    }
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return base;
  }

  InstalledAddon copyWith({bool? enabled}) => InstalledAddon(
    manifestUrl: manifestUrl,
    name: name,
    description: description,
    enabled: enabled ?? this.enabled,
    providesStream: providesStream,
  );

  Map<String, dynamic> toJson() => {
    'manifestUrl': manifestUrl,
    'name': name,
    'description': description,
    'enabled': enabled,
    'providesStream': providesStream,
  };

  static InstalledAddon? fromJson(Object? source) {
    if (source is! Map) return null;
    final url = source['manifestUrl'];
    if (url is! String || url.isEmpty) return null;

    return InstalledAddon(
      manifestUrl: url,
      name: source['name'] is String ? source['name'] as String : 'Addon',
      description: source['description'] as String?,
      enabled: source['enabled'] != false,
      providesStream: source['providesStream'] != false,
    );
  }
}

const Set<String> allowedStreamHeaders = {
  'user-agent',
  'referer',
  'origin',
  'cookie',
  'authorization',
  'accept',
  'accept-language',
};

class AddonClient {
  AddonClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 20),
              followRedirects: true,
              maxRedirects: 5,
              validateStatus: (status) => status != null && status < 500,
            ),
          );

  final Dio _dio;

  Future<InstalledAddon> install(String rawUrl, {CancelToken? cancel}) async {
    var url = rawUrl.trim();
    if (url.startsWith('stremio://')) {
      url = url.replaceFirst('stremio://', 'https://');
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      throw const ParseError('addon url');
    }
    if (!url.endsWith('.json')) {
      url =
          '${url.endsWith('/') ? url.substring(0, url.length - 1) : url}/manifest.json';
    }

    final payload = await _fetch(url, cancel);
    if (payload == null) throw const Unavailable();

    final resources = <String>[];
    for (final entry in readList(payload, const ['resources'])) {
      if (entry is String) resources.add(entry.toLowerCase());
      if (entry is Map) {
        final name = readString(entry, const ['name']);
        if (name != null) resources.add(name.toLowerCase());
      }
    }

    return InstalledAddon(
      manifestUrl: url,
      name: readString(payload, const ['name']) ?? 'Addon',
      description: readString(payload, const ['description']),
      providesStream: resources.contains('stream'),
    );
  }

  Future<List<Release>> streams(
    InstalledAddon addon,
    String imdbId, {
    required bool isSeries,
    int season = 0,
    int episode = 0,
    CancelToken? cancel,
  }) async {
    final type = isSeries ? 'series' : 'movie';
    final id = isSeries && season > 0 ? '$imdbId:$season:$episode' : imdbId;
    final url = '${addon.baseUrl}/stream/$type/${Uri.encodeComponent(id)}.json';

    final payload = await _fetch(url, cancel);
    if (payload == null) return const [];

    final releases = <Release>[];
    final seen = <String>{};

    for (final entry in readList(payload, const ['streams'])) {
      final release = streamToRelease(
        entry,
        addon.name,
        season: season,
        episode: episode,
      );
      if (release == null) continue;

      final key = release.directUrl ?? '';
      if (key.isEmpty || !seen.add(key)) continue;
      releases.add(release);
    }

    return releases;
  }

  Future<Map<String, dynamic>?> _fetch(String url, CancelToken? cancel) async {
    try {
      final response = await _dio.get<dynamic>(url, cancelToken: cancel);
      final data = response.data;
      return data is Map<String, dynamic> ? data : null;
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) throw const Cancelled();
      return null;
    }
  }
}

Release? streamToRelease(
  Object? source,
  String addonName, {
  int season = 0,
  int episode = 0,
}) {
  if (source is! Map) return null;

  final url = readString(source, const ['url']);
  if (url == null || !url.startsWith('http')) return null;

  final headers = <String, String>{};
  final hints = source['behaviorHints'];
  if (hints is Map) {
    final proxyHeaders = hints['proxyHeaders'];
    if (proxyHeaders is Map) {
      final request = proxyHeaders['request'];
      if (request is Map) {
        for (final entry in request.entries) {
          final name = '${entry.key}'.toLowerCase();
          if (name == 'x-forwarded-for') continue;
          if (!allowedStreamHeaders.contains(name)) continue;
          headers['${entry.key}'] = '${entry.value}';
        }
      }
    }
  }

  final label = readString(source, const ['name', 'title']) ?? addonName;
  final description = readString(source, const ['title', 'description']) ?? '';
  final quality = _qualityFrom('$label $description');

  return Release(
    kind: ProviderKind.addons,
    filename: cleanStreamText(description.isEmpty ? label : description),
    quality: quality,
    language: null,
    season: season == 0 ? null : season,
    episode: episode == 0 ? null : episode,
    mirrors: [
      SourceMirror(
        label: cleanStreamText(label),
        url: url,
        headers: headers,
        directFile: true,
      ),
    ],
  );
}

String? _qualityFrom(String text) {
  final lower = text.toLowerCase();
  for (final candidate in const ['2160', '1440', '1080', '720', '480', '360']) {
    if (lower.contains(candidate)) return '${candidate}p';
  }
  if (lower.contains('4k') || lower.contains('uhd')) return '2160p';
  return null;
}

String cleanStreamText(String input) {
  final buffer = StringBuffer();
  var lastWasSpace = true;

  for (final rune in input.runes) {
    final isEmoji =
        (rune >= 0x1F000 && rune <= 0x1FAFF) ||
        (rune >= 0x2600 && rune <= 0x27BF) ||
        (rune >= 0x2300 && rune <= 0x23FF) ||
        (rune >= 0x2B00 && rune <= 0x2BFF) ||
        (rune >= 0xFE00 && rune <= 0xFE0F) ||
        rune == 0x200D;
    if (isEmoji) continue;

    final char = String.fromCharCode(rune);
    if (char.trim().isEmpty) {
      if (!lastWasSpace && buffer.isNotEmpty) {
        buffer.write(' ');
        lastWasSpace = true;
      }
      continue;
    }

    buffer.write(char);
    lastWasSpace = false;
  }

  return buffer.toString().trim();
}
