import 'provider_kind.dart';

enum MediaType { movie, series }

class MediaId {
  const MediaId(this.kind, this.value);

  final ProviderKind kind;
  final String value;

  @override
  bool operator ==(Object other) => other is MediaId && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);

  @override
  String toString() => '${kind.id}:$value';
}

class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.title,
    required this.mediaType,
    this.year,
    this.posterUrl,
    this.backdropUrl,
    this.logoUrl,
    this.seasonCount,
    this.rating,
  });

  final MediaId id;
  final String title;
  final MediaType mediaType;
  final String? year;
  final String? posterUrl;
  final String? backdropUrl;
  final String? logoUrl;
  final int? seasonCount;
  final double? rating;

  bool get isSeries => mediaType == MediaType.series;

  CatalogItem copyWith({String? posterUrl, String? backdropUrl, String? logoUrl, double? rating}) {
    return CatalogItem(
      id: id,
      title: title,
      mediaType: mediaType,
      year: year,
      posterUrl: posterUrl ?? this.posterUrl,
      backdropUrl: backdropUrl ?? this.backdropUrl,
      logoUrl: logoUrl ?? this.logoUrl,
      seasonCount: seasonCount,
      rating: rating ?? this.rating,
    );
  }
}

class Episode {
  const Episode({
    required this.season,
    required this.number,
    this.title,
    this.overview,
    this.stillUrl,
    this.runtimeMinutes,
  });

  final int season;
  final int number;
  final String? title;
  final String? overview;
  final String? stillUrl;
  final int? runtimeMinutes;

  String get label => 'S${season}E$number';
}

class Season {
  const Season({required this.number, required this.episodes});

  final int number;
  final List<Episode> episodes;
}

class AudioTrackOption {
  const AudioTrackOption({required this.mediaId, required this.language, required this.label});

  final String mediaId;
  final String language;
  final String label;
}

class MediaDetails {
  const MediaDetails({
    required this.id,
    required this.title,
    required this.mediaType,
    this.year,
    this.description,
    this.tagline,
    this.rating,
    this.director,
    this.cast,
    this.posterUrl,
    this.backdropUrl,
    this.logoUrl,
    this.duration,
    this.genres = const [],
    this.seasons = const [],
    this.dubs = const [],
  });

  factory MediaDetails.of(CatalogItem item) => MediaDetails(
    id: item.id,
    title: item.title,
    mediaType: item.mediaType,
    year: item.year,
    posterUrl: item.posterUrl,
    backdropUrl: item.backdropUrl,
    logoUrl: item.logoUrl,
    rating: item.rating?.toStringAsFixed(1),
  );

  final MediaId id;
  final String title;
  final MediaType mediaType;
  final String? year;
  final String? description;
  final String? tagline;
  final String? rating;
  final String? director;
  final String? cast;
  final String? posterUrl;
  final String? backdropUrl;
  final String? logoUrl;
  final String? duration;
  final List<String> genres;
  final List<Season> seasons;
  final List<AudioTrackOption> dubs;

  bool get isSeries => mediaType == MediaType.series || seasons.isNotEmpty;

  bool get hasAlternateAudio => dubs.length > 1;

  MediaDetails copyWith({
    String? backdropUrl,
    String? logoUrl,
    String? description,
    String? rating,
    List<String>? genres,
  }) {
    return MediaDetails(
      id: id,
      title: title,
      mediaType: mediaType,
      year: year,
      description: description ?? this.description,
      tagline: tagline,
      rating: rating ?? this.rating,
      director: director,
      cast: cast,
      posterUrl: posterUrl,
      backdropUrl: backdropUrl ?? this.backdropUrl,
      logoUrl: logoUrl ?? this.logoUrl,
      duration: duration,
      genres: genres ?? this.genres,
      seasons: seasons,
      dubs: dubs,
    );
  }
}

Map<String, dynamic> catalogToJson(CatalogItem item) => {
  'id': item.id.value,
  'kind': item.id.kind.id,
  'title': item.title,
  'mediaType': item.mediaType.name,
  'year': item.year,
  'posterUrl': item.posterUrl,
  'backdropUrl': item.backdropUrl,
  'logoUrl': item.logoUrl,
  'rating': item.rating,
};

CatalogItem? catalogFromJson(Object? source) {
  if (source is! Map) return null;
  final id = source['id'];
  final title = source['title'];
  if (id is! String || id.isEmpty || title is! String) return null;

  return CatalogItem(
    id: MediaId(ProviderKind.byId('${source['kind']}') ?? ProviderKind.addons, id),
    title: title,
    mediaType: source['mediaType'] == 'series' ? MediaType.series : MediaType.movie,
    year: source['year'] as String?,
    posterUrl: source['posterUrl'] as String?,
    backdropUrl: source['backdropUrl'] as String?,
    logoUrl: source['logoUrl'] as String?,
    rating: source['rating'] is num ? (source['rating'] as num).toDouble() : null,
  );
}
