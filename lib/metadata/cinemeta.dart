import 'package:dio/dio.dart';

import '../core/errors.dart';
import '../core/memo_cache.dart';
import '../models/media.dart';
import '../models/provider_kind.dart';
import '../sources/moviebox/adapt.dart';
import 'metadata_source.dart';

const String cinemetaBase = 'https://v3-cinemeta.strem.io';

class CinemetaSource implements MetadataSource {
  CinemetaSource({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 20),
              responseType: ResponseType.json,
              followRedirects: true,
              maxRedirects: 5,
              validateStatus: (status) => status != null && status < 500,
            ),
          );

  final Dio _dio;

  static final _shelfCache = MemoCache<String, List<CatalogItem>>(
    ttl: const Duration(hours: 6),
    name: 'shelves',
    encode: (items) => items.map(catalogToJson).toList(),
    decode: (raw) => [
      if (raw is List)
        for (final entry in raw) ?catalogFromJson(entry),
    ],
  );

  static final _metaCache = MemoCache<String, Map<String, dynamic>>(
    ttl: const Duration(days: 7),
    maxEntries: 1024,
    name: 'meta',
    encode: (meta) => meta,
    decode: (raw) =>
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{},
  );

  @override
  String get name => 'Cinemeta';

  @override
  Future<List<CatalogItem>> shelf(CatalogShelf shelf, {CancelToken? cancel}) {
    final key = '${shelf.type}/${shelf.sort}';
    return _shelfCache.resolve(key, () async {
      final url = '$cinemetaBase/catalog/${shelf.type}/${shelf.sort}.json';
      final payload = await _fetch(url, cancel);
      if (payload == null) return const <CatalogItem>[];

      final items = <CatalogItem>[];
      for (final entry in readList(payload, const ['metas'])) {
        final item = metaToCatalogItem(entry, shelf.type);
        if (item != null) items.add(item);
      }
      return items;
    });
  }

  @override
  Future<CatalogItem?> enrich(CatalogItem item, {CancelToken? cancel}) async {
    final meta = await rawMeta(
      item.id.value,
      item.isSeries ? 'series' : 'movie',
      cancel,
    );
    if (meta == null) return null;

    return item.copyWith(
      posterUrl: item.posterUrl ?? readString(meta, const ['poster']),
      backdropUrl: item.backdropUrl ?? readString(meta, const ['background']),
      logoUrl: item.logoUrl ?? readString(meta, const ['logo']),
      rating: item.rating ?? readDouble(meta, const ['imdbRating']),
    );
  }

  @override
  Future<MediaDetails?> describe(
    MediaDetails details, {
    CancelToken? cancel,
  }) async {
    final meta = await rawMeta(
      details.id.value,
      details.isSeries ? 'series' : 'movie',
      cancel,
    );
    if (meta == null) return null;

    return details.copyWith(
      description:
          details.description ?? readString(meta, const ['description']),
      backdropUrl:
          details.backdropUrl ?? readString(meta, const ['background']),
      logoUrl: details.logoUrl ?? readString(meta, const ['logo']),
      rating: details.rating ?? readString(meta, const ['imdbRating']),
      genres: details.genres.isEmpty ? _genres(meta) : details.genres,
    );
  }

  Future<MediaDetails?> fullDetails(
    CatalogItem item, {
    CancelToken? cancel,
  }) async {
    final primary = item.isSeries ? 'series' : 'movie';
    var meta = await rawMeta(item.id.value, primary, cancel);

    meta ??= await rawMeta(
      item.id.value,
      item.isSeries ? 'movie' : 'series',
      cancel,
    );
    if (meta == null) return null;

    final seasons = seasonsFromVideos(meta);
    final declaredSeries =
        (readString(meta, const ['type']) ?? '').toLowerCase() == 'series' ||
        seasons.isNotEmpty;

    return MediaDetails(
      id: item.id,
      title: readString(meta, const ['name', 'title']) ?? item.title,
      mediaType: declaredSeries ? MediaType.series : MediaType.movie,
      year: extractYear(readString(meta, const ['year', 'releaseInfo'])),
      description: readString(meta, const ['description']),
      rating: readString(meta, const ['imdbRating']),
      director: _joinList(meta, const ['director']),
      cast: _joinList(meta, const ['cast']),
      posterUrl: readString(meta, const ['poster']) ?? item.posterUrl,
      backdropUrl: readString(meta, const ['background']) ?? item.backdropUrl,
      logoUrl: readString(meta, const ['logo']) ?? item.logoUrl,
      duration: readString(meta, const ['runtime']),
      genres: _genres(meta),
      seasons: seasons,
    );
  }

  Future<Map<String, dynamic>?> rawMeta(
    String id,
    String type,
    CancelToken? cancel,
  ) async {
    if (!id.startsWith('tt')) return null;

    final cached = _metaCache.peek('$type/$id');
    if (cached != null) return cached;

    final payload = await _fetch('$cinemetaBase/meta/$type/$id.json', cancel);
    final meta = payload?['meta'];
    if (meta is! Map<String, dynamic>) return null;

    _metaCache.put('$type/$id', meta);
    return meta;
  }

  List<String> _genres(Map<String, dynamic> meta) {
    final genres = <String>[];
    for (final genre in readList(meta, const ['genres', 'genre'])) {
      if (genre is String && genre.trim().isNotEmpty) genres.add(genre.trim());
    }
    return genres;
  }

  String? _joinList(Map<String, dynamic> meta, List<String> keys) {
    final values = <String>[];
    for (final entry in readList(meta, keys)) {
      if (entry is String && entry.trim().isNotEmpty) values.add(entry.trim());
    }
    return values.isEmpty ? null : values.take(4).join(', ');
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

List<Season> seasonsFromVideos(Map<String, dynamic> meta) {
  final grouped = <int, List<Episode>>{};

  for (final entry in readList(meta, const ['videos'])) {
    if (entry is! Map) continue;

    final season = readInt(entry, const ['season']);
    final number = readInt(entry, const ['episode', 'number']);
    if (season == null || number == null || season <= 0 || number <= 0)
      continue;

    grouped
        .putIfAbsent(season, () => <Episode>[])
        .add(
          Episode(
            season: season,
            number: number,
            title: readString(entry, const ['name', 'title']),
            overview: readString(entry, const ['overview', 'description']),
            stillUrl: readString(entry, const ['thumbnail']),
          ),
        );
  }

  final seasons = grouped.entries.map((entry) {
    final episodes = [...entry.value]
      ..sort((a, b) => a.number.compareTo(b.number));
    return Season(number: entry.key, episodes: episodes);
  }).toList()..sort((a, b) => a.number.compareTo(b.number));

  return seasons;
}

CatalogItem? metaToCatalogItem(Object? source, String fallbackType) {
  if (source is! Map) return null;

  final id = readString(source, const ['id', 'imdb_id']);
  final title = readString(source, const ['name', 'title']);
  if (id == null || title == null) return null;

  final type = readString(source, const ['type']) ?? fallbackType;
  final isSeries = type.toLowerCase() == 'series' || type.toLowerCase() == 'tv';

  return CatalogItem(
    id: MediaId(ProviderKind.addons, id),
    title: title,
    mediaType: isSeries ? MediaType.series : MediaType.movie,
    year: extractYear(
      readString(source, const ['year', 'releaseInfo', 'released']),
    ),
    posterUrl: readString(source, const ['poster']),
    backdropUrl: readString(source, const ['background']),
    logoUrl: readString(source, const ['logo']),
    rating: readDouble(source, const ['imdbRating']),
  );
}
