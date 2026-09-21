import 'package:dio/dio.dart';

import '../models/media.dart';

enum CatalogShelf {
  trendingMovies('Trending Now', 'movie', 'top'),
  trendingSeries('Popular Series', 'series', 'top'),
  newMovies('New Releases', 'movie', 'year'),
  topRated('Top Rated', 'movie', 'imdbRating');

  const CatalogShelf(this.title, this.type, this.sort);

  final String title;
  final String type;
  final String sort;
}

abstract interface class MetadataSource {
  String get name;

  Future<List<CatalogItem>> shelf(CatalogShelf shelf, {CancelToken? cancel});

  Future<CatalogItem?> enrich(CatalogItem item, {CancelToken? cancel});

  Future<MediaDetails?> describe(MediaDetails details, {CancelToken? cancel});
}
