import 'package:dio/dio.dart';

import '../../core/errors.dart';
import '../../models/media.dart';
import '../../models/provider_kind.dart';
import '../../models/release.dart';
import '../content_source.dart';
import '../moviebox/adapt.dart';
import 'circleftp_source.dart';

const List<String> dhakaFlixHosts = [
  'http://172.16.50.7',
  'http://172.16.50.14',
  'http://172.16.50.12',
  'http://172.16.50.9',
];

const Set<String> videoExtensions = {'mkv', 'mp4', 'avi', 'webm', 'm4v', 'mov'};

class DhakaFlixSource extends BaseContentSource {
  DhakaFlixSource({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 4),
              receiveTimeout: const Duration(seconds: 15),
              validateStatus: (status) => status != null && status < 500,
            ),
          );

  final Dio _dio;
  final Map<String, DateTime> _deadHosts = {};

  @override
  ProviderKind get kind => ProviderKind.dhakaflix;

  @override
  SourceCapabilities get capabilities => const SourceCapabilities(
    pagination: false,
    subtitles: false,
    series: false,
  );

  bool _isDead(String host) {
    final since = _deadHosts[host];
    if (since == null) return false;
    if (DateTime.now().difference(since).inSeconds > 60) {
      _deadHosts.remove(host);
      return false;
    }
    return true;
  }

  @override
  Future<List<CatalogItem>> search(
    String query, {
    int page = 1,
    CancelToken? cancel,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final items = <CatalogItem>[];
    final seen = <String>{};
    var reachedAny = false;

    for (final host in dhakaFlixHosts) {
      if (_isDead(host)) continue;

      try {
        final response = await _dio.post<dynamic>(
          '$host/$_searchPath',
          cancelToken: cancel,
          data: {
            'action': 'get',
            'search': {'href': '/', 'pattern': trimmed, 'ignorecase': true},
          },
        );
        reachedAny = true;

        final data = response.data;
        if (data is! Map) continue;

        for (final entry in readList(data, const ['search', 'items'])) {
          final item = _toCatalogItem(entry, host);
          if (item == null) continue;
          if (!seen.add(item.id.value)) continue;
          items.add(item);
        }
      } on DioException catch (error) {
        if (CancelToken.isCancel(error)) throw const Cancelled();
        _deadHosts[host] = DateTime.now();
        continue;
      }
    }

    if (!reachedAny) {
      throw const NetworkError('bdix_unreachable');
    }
    return items;
  }

  static const String _searchPath = '';

  @override
  Future<MediaDetails> details(String id, {CancelToken? cancel}) async {
    final parts = _split(id);
    final name = Uri.decodeComponent(parts.path.split('/').last);

    return MediaDetails(
      id: MediaId(kind, id),
      title: _cleanName(name),
      mediaType: MediaType.movie,
      year: extractYear(name),
    );
  }

  @override
  Future<List<Release>> releases(
    String id, {
    int season = 0,
    int episode = 0,
    CancelToken? cancel,
  }) async {
    final parts = _split(id);
    final url = '${parts.host}${Uri.encodeFull(parts.path)}';
    final name = Uri.decodeComponent(parts.path.split('/').last);

    return [
      Release(
        kind: kind,
        filename: name,
        quality: qualityFromFilename(name),
        codec: codecFromFilename(name),
        season: season == 0 ? null : season,
        episode: episode == 0 ? null : episode,
        mirrors: [SourceMirror(label: 'DhakaFlix', url: url, directFile: true)],
      ),
    ];
  }

  CatalogItem? _toCatalogItem(Object? source, String host) {
    if (source is! Map) return null;

    final href = readString(source, const ['href', 'path']);
    if (href == null || href.isEmpty) return null;

    final name = Uri.decodeComponent(href.split('/').last);
    final dot = name.lastIndexOf('.');
    if (dot < 0) return null;

    final extension = name.substring(dot + 1).toLowerCase();
    if (!videoExtensions.contains(extension)) return null;

    return CatalogItem(
      id: MediaId(kind, '$host:$href'),
      title: _cleanName(name),
      mediaType: MediaType.movie,
      year: extractYear(name),
    );
  }

  ({String host, String path}) _split(String id) {
    final index = id.indexOf(':/');
    if (index < 0) return (host: dhakaFlixHosts.first, path: id);
    return (host: id.substring(0, index), path: id.substring(index + 1));
  }

  String _cleanName(String raw) {
    final dot = raw.lastIndexOf('.');
    var name = dot > 0 ? raw.substring(0, dot) : raw;
    name = name.replaceAll(RegExp(r'[._]+'), ' ');
    return name.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
