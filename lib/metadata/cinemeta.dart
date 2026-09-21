import 'package:dio/dio.dart';

import '../core/errors.dart';
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
              receiveTimeout: const Duration(seconds: 15),
              responseType: ResponseType.json,
              validateStatus: (status) => status != null && status < 500,
            ),
          );

  final Dio _dio;

  @override
  String get name => 'Cinemeta';

  @override
  Future<List<CatalogItem>> shelf(CatalogShelf shelf, {CancelToken? cancel}) async {
    final url = '$cinemetaBase/catalog/${shelf.type}/${shelf.sort}.json';
    final payload = await _fetch(url, cancel);
    if (payload == null) return const [];

    final items = <CatalogItem>[];
    for (final entry in readList(payload, const ['metas'])) {
      final item = metaToCatalogItem(entry, shelf.type);
      if (item != null) items.add(item);
    }
    return items;
  }

  @override
  Future<CatalogItem?> enrich(CatalogItem item, {CancelToken? cancel}) async {
    final meta = await _meta(item.id.value, item.isSeries ? 'series' : 'movie', cancel);
    if (meta == null) return null;

    return item.copyWith(
      posterUrl: item.posterUrl ?? readString(meta, const ['poster']),
      backdropUrl: item.backdropUrl ?? readString(meta, const ['background']),
      logoUrl: item.logoUrl ?? readString(meta, const ['logo']),
      rating: item.rating ?? readDouble(meta, const ['imdbRating']),
    );
  }

  @override
  Future<MediaDetails?> describe(MediaDetails details, {CancelToken? cancel}) async {
    final meta = await _meta(details.id.value, details.isSeries ? 'series' : 'movie', cancel);
    if (meta == null) return null;

    final genres = <String>[];
    for (final genre in readList(meta, const ['genres', 'genre'])) {
      if (genre is String && genre.trim().isNotEmpty) genres.add(genre.trim());
    }

    return details.copyWith(
      description: details.description ?? readString(meta, const ['description']),
      backdropUrl: details.backdropUrl ?? readString(meta, const ['background']),
      logoUrl: details.logoUrl ?? readString(meta, const ['logo']),
      rating: details.rating ?? readString(meta, const ['imdbRating']),
      genres: details.genres.isEmpty ? genres : details.genres,
    );
  }

  Future<Map<String, dynamic>?> _meta(String id, String type, CancelToken? cancel) async {
    if (!id.startsWith('tt')) return null;
    final payload = await _fetch('$cinemetaBase/meta/$type/$id.json', cancel);
    final meta = payload?['meta'];
    return meta is Map<String, dynamic> ? meta : null;
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
    year: extractYear(readString(source, const ['year', 'releaseInfo', 'released'])),
    posterUrl: readString(source, const ['poster']),
    backdropUrl: readString(source, const ['background']),
    logoUrl: readString(source, const ['logo']),
    rating: readDouble(source, const ['imdbRating']),
  );
}
