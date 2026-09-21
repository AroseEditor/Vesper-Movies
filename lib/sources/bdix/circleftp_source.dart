import 'package:dio/dio.dart';

import '../../core/errors.dart';
import '../../models/media.dart';
import '../../models/provider_kind.dart';
import '../../models/release.dart';
import '../content_source.dart';
import '../moviebox/adapt.dart';

const String circleFtpBase = 'http://new.circleftp.net:5000';

class CircleFtpSource extends BaseContentSource {
  CircleFtpSource({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 15),
              followRedirects: true,
              validateStatus: (status) => status != null && status < 500,
            ),
          );

  final Dio _dio;

  @override
  ProviderKind get kind => ProviderKind.circleftp;

  @override
  SourceCapabilities get capabilities =>
      const SourceCapabilities(pagination: false, subtitles: false);

  @override
  Future<List<CatalogItem>> search(String query, {int page = 1, CancelToken? cancel}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final payload = await _get(
      '$circleFtpBase/api/posts',
      cancel,
      query: {'searchTerm': trimmed, 'order': 'desc'},
    );
    if (payload == null) throw const Unavailable();

    final items = <CatalogItem>[];
    for (final entry in readList(payload, const ['posts', 'list', 'data'])) {
      final item = _toCatalogItem(entry);
      if (item != null) items.add(item);
    }
    return items;
  }

  @override
  Future<MediaDetails> details(String id, {CancelToken? cancel}) async {
    final payload = await _get('$circleFtpBase/api/posts/$id', cancel);
    if (payload == null) throw const NotFound();

    final seasons = <Season>[];
    final content = payload['content'];
    if (content is List) {
      for (var index = 0; index < content.length; index++) {
        final entry = content[index];
        final episodes = <Episode>[];
        for (final raw in readList(entry, const ['episodes'])) {
          final number =
              readInt(raw, const ['episodeNo', 'episode', 'number']) ?? episodes.length + 1;
          episodes.add(
            Episode(
              season: index + 1,
              number: number,
              title: readString(raw, const ['title', 'name']),
            ),
          );
        }
        if (episodes.isNotEmpty) {
          seasons.add(Season(number: index + 1, episodes: episodes));
        }
      }
    }

    return MediaDetails(
      id: MediaId(kind, id),
      title: readString(payload, const ['title', 'name']) ?? 'Unknown',
      mediaType: seasons.isEmpty ? MediaType.movie : MediaType.series,
      year: extractYear(readString(payload, const ['releaseDate', 'year'])),
      description: readString(payload, const ['description', 'metaData']),
      posterUrl: _image(readString(payload, const ['image', 'thumbnail'])),
      seasons: seasons,
    );
  }

  @override
  Future<List<Release>> releases(
    String id, {
    int season = 0,
    int episode = 0,
    CancelToken? cancel,
  }) async {
    final payload = await _get('$circleFtpBase/api/posts/$id', cancel);
    if (payload == null) throw const NotFound();

    final title = readString(payload, const ['title', 'name']) ?? 'CircleFTP';
    final content = payload['content'];
    final releases = <Release>[];

    if (content is String && content.startsWith('http')) {
      releases.add(_release(title, content, season: season, episode: episode));
    } else if (content is List) {
      if (season > 0) {
        final index = season - 1;
        if (index < 0 || index >= content.length) return const [];

        for (final raw in readList(content[index], const ['episodes'])) {
          final number = readInt(raw, const ['episodeNo', 'episode', 'number']);
          if (number != null && episode > 0 && number != episode) continue;

          final link = readString(raw, const ['link', 'url']);
          if (link == null) continue;
          releases.add(
            _release(
              readString(raw, const ['title', 'name']) ?? title,
              link,
              season: season,
              episode: number ?? episode,
            ),
          );
        }
      } else {
        for (final entry in content) {
          final link = entry is String ? entry : readString(entry, const ['link', 'url']);
          if (link == null || !link.startsWith('http')) continue;
          releases.add(_release(title, link));
        }
      }
    }

    if (releases.isEmpty) throw const Unavailable();
    return sortReleases(releases);
  }

  Release _release(String title, String url, {int season = 0, int episode = 0}) {
    return Release(
      kind: kind,
      filename: title,
      quality: qualityFromFilename(url),
      codec: codecFromFilename(url),
      season: season == 0 ? null : season,
      episode: episode == 0 ? null : episode,
      mirrors: [SourceMirror(label: 'CircleFTP', url: url, directFile: true)],
    );
  }

  CatalogItem? _toCatalogItem(Object? source) {
    if (source is! Map) return null;

    final id = readString(source, const ['id', '_id']);
    final title = readString(source, const ['title', 'name']);
    if (id == null || title == null) return null;

    final type = readString(source, const ['type', 'contentType']) ?? '';
    final isSeries = type.toLowerCase().contains('series') || type.toLowerCase().contains('tv');

    return CatalogItem(
      id: MediaId(kind, id),
      title: title,
      mediaType: isSeries ? MediaType.series : MediaType.movie,
      year: extractYear(readString(source, const ['releaseDate', 'year'])),
      posterUrl: _image(readString(source, const ['image', 'thumbnail'])),
    );
  }

  String? _image(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http')) return path;
    return '$circleFtpBase/${path.startsWith('/') ? path.substring(1) : path}';
  }

  Future<Map<String, dynamic>?> _get(
    String url,
    CancelToken? cancel, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final response = await _dio.get<dynamic>(url, cancelToken: cancel, queryParameters: query);
      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      if (data is List) return {'list': data};
      return null;
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) throw const Cancelled();
      throw NetworkError(
        error.type.name,
        timedOut: error.type == DioExceptionType.connectionTimeout,
      );
    }
  }
}

String? qualityFromFilename(String name) {
  final lower = name.toLowerCase();
  for (final candidate in const ['2160', '1440', '1080', '720', '480', '360']) {
    if (lower.contains(candidate)) return '${candidate}p';
  }
  if (lower.contains('4k') || lower.contains('uhd')) return '2160p';
  return null;
}

String? codecFromFilename(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('x265') || lower.contains('hevc') || lower.contains('h265')) {
    return 'hevc';
  }
  if (lower.contains('x264') || lower.contains('h264') || lower.contains('avc')) {
    return 'h264';
  }
  if (lower.contains('av1')) return 'av1';
  return null;
}
