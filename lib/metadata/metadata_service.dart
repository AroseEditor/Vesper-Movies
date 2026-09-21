import 'package:dio/dio.dart';

import '../core/errors.dart';
import '../models/media.dart';
import 'cinemeta.dart';
import 'metadata_source.dart';
import 'tmdb.dart';

class MetadataService {
  MetadataService({TmdbSource? tmdb, CinemetaSource? cinemeta})
    : _tmdb = tmdb ?? TmdbSource(),
      _cinemeta = cinemeta ?? CinemetaSource();

  final TmdbSource _tmdb;
  final CinemetaSource _cinemeta;

  String get activeName => _tmdb.isConfigured ? _tmdb.name : _cinemeta.name;

  List<MetadataSource> get _chain => _tmdb.isConfigured ? [_tmdb, _cinemeta] : [_cinemeta];

  Future<List<CatalogItem>> search(String query, {CancelToken? cancel}) async {
    if (_tmdb.isConfigured) {
      try {
        final items = await _tmdb.search(query, cancel: cancel);
        if (items.isNotEmpty) return items;
      } on Cancelled {
        rethrow;
      } on Object catch (_) {}
    }
    return _cinemeta.search(query, cancel: cancel);
  }

  Future<String?> imdbIdFor(String tmdbKey, {CancelToken? cancel}) =>
      _tmdb.imdbIdFor(tmdbKey, cancel: cancel);

  Future<List<CatalogItem>> shelf(CatalogShelf shelf, {CancelToken? cancel}) async {
    for (final source in _chain) {
      try {
        final items = await source.shelf(shelf, cancel: cancel);
        if (items.isNotEmpty) return items;
      } on Cancelled {
        rethrow;
      } on Object catch (_) {
        continue;
      }
    }
    return const [];
  }

  Future<CatalogItem> enrich(CatalogItem item, {CancelToken? cancel}) async {
    if (item.backdropUrl != null && item.logoUrl != null && item.posterUrl != null) {
      return item;
    }

    var current = item;
    for (final source in _chain) {
      try {
        final enriched = await source.enrich(current, cancel: cancel);
        if (enriched != null) current = enriched;
        if (current.backdropUrl != null && current.logoUrl != null) break;
      } on Cancelled {
        rethrow;
      } on Object catch (_) {
        continue;
      }
    }
    return current;
  }

  Future<MediaDetails> describe(MediaDetails details, {CancelToken? cancel}) async {
    var current = details;
    for (final source in _chain) {
      try {
        final described = await source.describe(current, cancel: cancel);
        if (described != null) current = described;
        if (current.backdropUrl != null && current.description != null) break;
      } on Cancelled {
        rethrow;
      } on Object catch (_) {
        continue;
      }
    }
    return current;
  }
}
