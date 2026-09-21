import 'package:dio/dio.dart';

import '../../core/errors.dart';
import '../../models/media.dart';
import '../../models/provider_kind.dart';
import '../../models/release.dart';
import '../bdix/circleftp_source.dart';
import '../content_source.dart';
import '../moviebox/adapt.dart';

const String dramachiApi = 'https://api.nodeobjects.com/';
const String dramachiThumbnails = 'https://static.nodeobjects.com/thumbnail/';

class DramachiSource extends BaseContentSource {
  DramachiSource({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 20),
              followRedirects: true,
              validateStatus: (status) => status != null && status < 500,
            ),
          );

  final Dio _dio;

  @override
  ProviderKind get kind => ProviderKind.dramachi;

  @override
  SourceCapabilities get capabilities =>
      const SourceCapabilities(pagination: true, subtitles: false);

  @override
  Future<List<CatalogItem>> search(String query, {int page = 1, CancelToken? cancel}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final payload = await _get({
      'interface': 'search',
      'keyword': trimmed,
      'page': '$page',
    }, cancel);
    if (payload == null) throw const Unavailable();

    final items = <CatalogItem>[];
    for (final entry in readList(payload, const ['list', 'data', 'results'])) {
      final item = _toCatalogItem(entry);
      if (item != null) items.add(item);
    }
    return items;
  }

  @override
  Future<MediaDetails> details(String id, {CancelToken? cancel}) async {
    final titleId = id.split('::').first;

    final payload = await _get({'interface': 'title_v2', 'id': titleId}, cancel);
    if (payload == null) throw const NotFound();

    final seasons = <Season>[];
    final episodes = await _get({'interface': 'eplist', 'id': titleId}, cancel);
    if (episodes != null) {
      final list = <Episode>[];
      for (final entry in readList(episodes, const ['list', 'data'])) {
        final number = readInt(entry, const ['ep', 'episode', 'number']) ?? list.length + 1;
        list.add(
          Episode(season: 1, number: number, title: readString(entry, const ['title', 'name'])),
        );
      }
      if (list.isNotEmpty) seasons.add(Season(number: 1, episodes: list));
    }

    return MediaDetails(
      id: MediaId(kind, id),
      title: readString(payload, const ['title', 'name']) ?? 'Unknown',
      mediaType: seasons.isEmpty ? MediaType.movie : MediaType.series,
      year: extractYear(readString(payload, const ['year', 'releaseDate'])),
      description: readString(payload, const ['description', 'summary']),
      posterUrl: _poster(readString(payload, const ['cover', 'thumbnail', 'poster'])),
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
    final titleId = id.split('::').first;

    final episodes = await _get({'interface': 'eplist', 'id': titleId}, cancel);
    if (episodes == null) throw const Unavailable();

    String? fileId;
    var title = 'Dramachi';

    for (final entry in readList(episodes, const ['list', 'data'])) {
      final number = readInt(entry, const ['ep', 'episode', 'number']);
      if (episode > 0 && number != episode) continue;

      fileId = readString(entry, const ['fid', 'fileId', 'id']);
      title = readString(entry, const ['title', 'name']) ?? title;
      break;
    }

    if (fileId == null) throw const Unavailable();

    final file = await _get({'interface': 'getFile', 'fid': fileId}, cancel);
    if (file == null) throw const Unavailable();

    final hostInfo = file['hostInfo'];
    final host = readString(hostInfo, const ['host']);
    final files = readList(file, const ['fileInfo']);
    if (host == null || files.isEmpty) throw const Unavailable();

    final path = readString(files.first, const ['url', 'path']);
    if (path == null) throw const Unavailable();

    final url = 'https://$host/cdn/${path.startsWith('/') ? path.substring(1) : path}';

    return [
      Release(
        kind: kind,
        filename: title,
        quality: qualityFromFilename(path),
        codec: codecFromFilename(path),
        season: season == 0 ? null : season,
        episode: episode == 0 ? null : episode,
        mirrors: [SourceMirror(label: 'Dramachi', url: url, directFile: true)],
      ),
    ];
  }

  CatalogItem? _toCatalogItem(Object? source) {
    if (source is! Map) return null;

    final id = readString(source, const ['id', 'titleId']);
    final title = readString(source, const ['title', 'name']);
    if (id == null || title == null) return null;

    return CatalogItem(
      id: MediaId(kind, id),
      title: title,
      mediaType: MediaType.series,
      year: extractYear(readString(source, const ['year', 'releaseDate'])),
      posterUrl: _poster(readString(source, const ['cover', 'thumbnail', 'poster'])),
    );
  }

  String? _poster(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http')) return path;
    return '$dramachiThumbnails${path.startsWith('/') ? path.substring(1) : path}';
  }

  Future<Map<String, dynamic>?> _get(Map<String, dynamic> query, CancelToken? cancel) async {
    try {
      final response = await _dio.get<dynamic>(
        dramachiApi,
        cancelToken: cancel,
        queryParameters: query,
      );
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
