import 'package:dio/dio.dart';

import '../core/env.dart';
import '../core/errors.dart';
import '../models/media.dart';
import '../models/provider_kind.dart';
import '../sources/moviebox/adapt.dart';
import 'metadata_source.dart';

const String tmdbApiBase = 'https://api.themoviedb.org/3';
const String tmdbImageBase = 'https://image.tmdb.org/t/p';

abstract final class TmdbImage {
  static String? poster(String? path) => _url(path, 'w500');

  static String? backdrop(String? path) => _url(path, 'w1280');

  static String? logo(String? path) => _url(path, 'w500');

  static String? _url(String? path, String size) {
    if (path == null || path.isEmpty) return null;
    return '$tmdbImageBase/$size$path';
  }
}

class TmdbSource implements MetadataSource {
  TmdbSource({Dio? dio, String? apiKey})
    : _apiKey = apiKey ?? Env.tmdbApiKey,
      _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 15),
              responseType: ResponseType.json,
              validateStatus: (status) => status != null && status < 500,
            ),
          );

  final Dio _dio;
  final String _apiKey;

  bool get isConfigured => _apiKey.trim().isNotEmpty;

  @override
  String get name => 'TMDB';

  @override
  Future<List<CatalogItem>> shelf(CatalogShelf shelf, {CancelToken? cancel}) async {
    if (!isConfigured) return const [];

    final path = switch (shelf) {
      CatalogShelf.trendingMovies => '/trending/movie/week',
      CatalogShelf.trendingSeries => '/trending/tv/week',
      CatalogShelf.newMovies => '/movie/now_playing',
      CatalogShelf.topRated => '/movie/top_rated',
    };

    final payload = await _fetch(path, cancel);
    if (payload == null) return const [];

    final isSeries = shelf == CatalogShelf.trendingSeries;
    final items = <CatalogItem>[];
    for (final entry in readList(payload, const ['results'])) {
      final item = _toCatalogItem(entry, isSeries);
      if (item != null) items.add(item);
    }
    return items;
  }

  @override
  Future<CatalogItem?> enrich(CatalogItem item, {CancelToken? cancel}) async {
    if (!isConfigured) return null;

    final match = await _findByTitle(item.title, item.year, item.isSeries, cancel);
    if (match == null) return null;

    final logo = await _logo(readInt(match, const ['id']), item.isSeries, cancel);

    return item.copyWith(
      posterUrl: item.posterUrl ?? TmdbImage.poster(readString(match, const ['poster_path'])),
      backdropUrl:
          item.backdropUrl ?? TmdbImage.backdrop(readString(match, const ['backdrop_path'])),
      logoUrl: item.logoUrl ?? logo,
      rating: item.rating ?? readDouble(match, const ['vote_average']),
    );
  }

  @override
  Future<MediaDetails?> describe(MediaDetails details, {CancelToken? cancel}) async {
    if (!isConfigured) return null;

    final match = await _findByTitle(details.title, details.year, details.isSeries, cancel);
    if (match == null) return null;

    final logo = await _logo(readInt(match, const ['id']), details.isSeries, cancel);

    return details.copyWith(
      description: details.description ?? readString(match, const ['overview']),
      backdropUrl:
          details.backdropUrl ?? TmdbImage.backdrop(readString(match, const ['backdrop_path'])),
      logoUrl: details.logoUrl ?? logo,
      rating: details.rating ?? readDouble(match, const ['vote_average'])?.toStringAsFixed(1),
    );
  }

  Future<List<CatalogItem>> search(String query, {CancelToken? cancel}) async {
    if (!isConfigured || query.trim().isEmpty) return const [];

    final payload = await _fetch(
      '/search/multi',
      cancel,
      query: {'query': query.trim(), 'include_adult': 'false'},
    );
    if (payload == null) throw const Unavailable();

    final items = <CatalogItem>[];
    for (final entry in readList(payload, const ['results'])) {
      if (entry is! Map) continue;
      final type = entry['media_type'];
      if (type != 'movie' && type != 'tv') continue;
      final item = _toCatalogItem(entry, type == 'tv');
      if (item != null) items.add(item);
    }
    return items;
  }

  Future<String?> imdbIdFor(String tmdbKey, {CancelToken? cancel}) async {
    if (!isConfigured) return null;
    final parts = tmdbKey.split(':');
    if (parts.length != 3 || parts[0] != 'tmdb') return null;

    final payload = await _fetch('/${parts[1]}/${parts[2]}/external_ids', cancel);
    final imdb = readString(payload, const ['imdb_id']);
    return imdb != null && imdb.startsWith('tt') ? imdb : null;
  }

  Future<Map<String, dynamic>?> _findByTitle(
    String title,
    String? year,
    bool isSeries,
    CancelToken? cancel,
  ) async {
    final path = isSeries ? '/search/tv' : '/search/movie';
    final query = <String, dynamic>{'query': title};
    if (year != null && year.isNotEmpty) {
      query[isSeries ? 'first_air_date_year' : 'year'] = year;
    }

    final payload = await _fetch(path, cancel, query: query);
    final results = readList(payload, const ['results']);
    if (results.isEmpty) return null;

    final first = results.first;
    return first is Map<String, dynamic> ? first : null;
  }

  Future<String?> _logo(int? tmdbId, bool isSeries, CancelToken? cancel) async {
    if (tmdbId == null) return null;

    final path = '${isSeries ? '/tv' : '/movie'}/$tmdbId/images';
    final payload = await _fetch(path, cancel, query: {'include_image_language': 'en,null'});
    final logos = readList(payload, const ['logos']);
    if (logos.isEmpty) return null;

    return TmdbImage.logo(readString(logos.first, const ['file_path']));
  }

  CatalogItem? _toCatalogItem(Object? source, bool isSeries) {
    if (source is! Map) return null;

    final id = readInt(source, const ['id']);
    final title = readString(source, const ['title', 'name', 'original_title']);
    if (id == null || title == null) return null;

    return CatalogItem(
      id: MediaId(ProviderKind.addons, 'tmdb:${isSeries ? 'tv' : 'movie'}:$id'),
      title: title,
      mediaType: isSeries ? MediaType.series : MediaType.movie,
      year: extractYear(readString(source, const ['release_date', 'first_air_date'])),
      posterUrl: TmdbImage.poster(readString(source, const ['poster_path'])),
      backdropUrl: TmdbImage.backdrop(readString(source, const ['backdrop_path'])),
      rating: readDouble(source, const ['vote_average']),
    );
  }

  Future<Map<String, dynamic>?> _fetch(
    String path,
    CancelToken? cancel, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        '$tmdbApiBase$path',
        cancelToken: cancel,
        queryParameters: {'api_key': _apiKey, ...?query},
      );
      final data = response.data;
      return data is Map<String, dynamic> ? data : null;
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) throw const Cancelled();
      return null;
    }
  }
}
