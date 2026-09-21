import '../../models/media.dart';
import '../../models/provider_kind.dart';
import '../../models/release.dart';
import 'cloudfront.dart';
import 'crypto.dart';

String? readString(Object? source, List<String> keys) {
  if (source is! Map) return null;
  for (final key in keys) {
    final value = source[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is num) return value.toString();
  }
  return null;
}

int? readInt(Object? source, List<String> keys) {
  if (source is! Map) return null;
  for (final key in keys) {
    final value = source[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
  }
  return null;
}

double? readDouble(Object? source, List<String> keys) {
  if (source is! Map) return null;
  for (final key in keys) {
    final value = source[key];
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
  }
  return null;
}

List<Object?> readList(Object? source, List<String> keys) {
  if (source is! Map) return const [];
  for (final key in keys) {
    final value = source[key];
    if (value is List) return value;
  }
  return const [];
}

String extractYear(String? raw) {
  if (raw == null) return '';
  for (var i = 0; i + 4 <= raw.length; i++) {
    final slice = raw.substring(i, i + 4);
    if ((slice[0] == '1' || slice[0] == '2') && int.tryParse(slice) != null) {
      return slice;
    }
  }
  return '';
}

String? readPoster(Object? source) {
  final direct = readString(source, const ['coverUrl', 'poster', 'pic', 'image', 'cover']);
  if (direct != null && direct.startsWith('http')) return direct;

  if (source is Map) {
    final cover = source['cover'];
    final nested = readString(cover, const ['url', 'src']);
    if (nested != null) return nested;
  }
  return null;
}

MediaType readMediaType(Object? source) {
  final stype = readInt(source, const ['subjectType', 'stype', 'type']);
  if (stype == 2) return MediaType.series;

  final text = readString(source, const ['type', 'subjectTypeName']);
  if (text != null) {
    final lower = text.toLowerCase();
    if (lower.contains('series') || lower.contains('tv') || lower.contains('show')) {
      return MediaType.series;
    }
  }
  return MediaType.movie;
}

CatalogItem? subjectToCatalogItem(Object? source) {
  if (source is! Map) return null;

  final id = readString(source, const ['subjectId', 'id', 'subject_id']);
  final title = readString(source, const ['title', 'name', 'subjectName']);
  if (id == null || title == null) return null;

  final year = extractYear(
    readString(source, const ['releaseDate', 'year', 'releaseInfo', 'releaseTime']),
  );

  return CatalogItem(
    id: MediaId(ProviderKind.moviebox, id),
    title: title,
    mediaType: readMediaType(source),
    year: year.isEmpty ? null : year,
    posterUrl: readPoster(source),
    seasonCount: readInt(source, const ['seasonCount', 'seasons', 'maxSeason']),
    rating: readDouble(source, const ['imdbRatingValue', 'imdbRate', 'imdbRating', 'rating']),
  );
}

List<CatalogItem> searchJsonToCatalog(Map<String, dynamic> payload) {
  final items = <CatalogItem>[];
  final seen = <String>{};

  void absorb(Iterable<Object?> entries) {
    for (final entry in entries) {
      final item = subjectToCatalogItem(entry);
      if (item != null && seen.add(item.id.value)) items.add(item);
    }
  }

  final results = readList(payload, const ['results']);
  for (final group in results) {
    absorb(readList(group, const ['subjects', 'list', 'items']));
  }

  if (items.isEmpty) {
    absorb(readList(payload, const ['list', 'subjects', 'items']));
  }

  return items;
}

List<CatalogItem> homepageJsonToCatalog(Map<String, dynamic> payload) {
  final items = <CatalogItem>[];
  final seen = <String>{};

  void absorb(Object? entry) {
    final item = subjectToCatalogItem(entry);
    if (item != null && seen.add(item.id.value)) items.add(item);
  }

  for (final group in readList(payload, const ['items', 'list', 'tabs'])) {
    if (group is! Map) continue;

    for (final banner in readList(group['banner'], const ['banners'])) {
      if (banner is Map) absorb(banner['subject']);
    }
    for (final custom in readList(group['customData'], const ['items'])) {
      if (custom is Map) absorb(custom['subject'] ?? custom);
    }
    for (final subject in readList(group, const ['subjects'])) {
      absorb(subject);
    }
  }

  if (items.isEmpty) {
    for (final entry in readList(payload, const ['list', 'subjects'])) {
      absorb(entry);
    }
  }

  return items;
}

List<Season> seasonsFromDetails(Object? source) {
  final seasonsNode = source is Map ? source['seasons'] : null;
  final entries = readList(seasonsNode, const ['seasons', 'list']);

  final seasons = <Season>[];
  for (final entry in entries) {
    if (entry is! Map) continue;
    final number = readInt(entry, const ['se', 'season', 'seasonNumber', 'number']) ?? 0;
    if (number <= 0) continue;

    final numbers = readList(entry, const ['episodeNumbers', 'episodes']);
    final episodes = <Episode>[];

    if (numbers.isNotEmpty) {
      for (final raw in numbers) {
        final episodeNumber = raw is Map
            ? readInt(raw, const ['ep', 'episode', 'number'])
            : (raw is num ? raw.toInt() : int.tryParse('$raw'));
        if (episodeNumber == null || episodeNumber <= 0) continue;
        episodes.add(
          Episode(
            season: number,
            number: episodeNumber,
            title: raw is Map ? readString(raw, const ['title', 'name']) : null,
            overview: raw is Map ? readString(raw, const ['description', 'overview']) : null,
          ),
        );
      }
    }

    if (episodes.isEmpty) {
      final maxEp = readInt(entry, const ['maxEp', 'episodeCount', 'total']) ?? 0;
      for (var i = 1; i <= maxEp; i++) {
        episodes.add(Episode(season: number, number: i));
      }
    }

    if (episodes.isNotEmpty) seasons.add(Season(number: number, episodes: episodes));
  }

  seasons.sort((a, b) => a.number.compareTo(b.number));
  return seasons;
}

List<AudioTrackOption> dubsFromDetails(Object? source) {
  final dubs = <AudioTrackOption>[];
  final seen = <String>{};

  for (final entry in readList(source, const ['dubs', 'languages', 'audios'])) {
    if (entry is! Map) continue;
    final id = readString(entry, const ['subjectId', 'id']);
    if (id == null || !seen.add(id)) continue;

    final language = readString(entry, const ['lanName', 'language', 'lan', 'name']) ?? 'Unknown';
    dubs.add(AudioTrackOption(mediaId: id, language: language, label: language));
  }

  return dubs;
}

MediaDetails detailsJsonToMediaDetails(Map<String, dynamic> payload, String fallbackId) {
  final id = readString(payload, const ['subjectId', 'id']) ?? fallbackId;
  final title = readString(payload, const ['title', 'name']) ?? 'Unknown';
  final seasons = seasonsFromDetails(payload);
  final mediaType = seasons.isNotEmpty ? MediaType.series : readMediaType(payload);

  final genres = <String>[];
  for (final genre in readList(payload, const ['genres', 'genre', 'tags'])) {
    if (genre is String && genre.trim().isNotEmpty) {
      genres.add(genre.trim());
    } else if (genre is Map) {
      final name = readString(genre, const ['name', 'title']);
      if (name != null) genres.add(name);
    }
  }

  final year = extractYear(readString(payload, const ['releaseDate', 'year', 'releaseInfo']));

  return MediaDetails(
    id: MediaId(ProviderKind.moviebox, id),
    title: title,
    mediaType: mediaType,
    year: year.isEmpty ? null : year,
    description: readString(payload, const ['description', 'overview', 'introduction', 'desc']),
    tagline: readString(payload, const ['tagline', 'subtitle']),
    rating: readString(payload, const ['imdbRatingValue', 'imdbRate', 'imdbRating']),
    director: readString(payload, const ['director', 'directors']),
    cast: readString(payload, const ['stars', 'actors', 'cast']),
    posterUrl: readPoster(payload),
    duration: readString(payload, const ['duration', 'runtime']),
    genres: genres,
    seasons: seasons,
    dubs: dubsFromDetails(payload),
  );
}

List<SubtitleOption> captionsJsonToOptions(Map<String, dynamic> payload) {
  const junkMarker = 'aa348f2541d13ffe';

  final options = <SubtitleOption>[];
  final seenUrls = <String>{};

  for (final entry in readList(payload, const ['extCaptions', 'captions', 'list'])) {
    if (entry is! Map) continue;

    final url = readString(entry, const ['url', 'link', 'captionUrl']);
    if (url == null || url.isEmpty) continue;
    if (url.contains(junkMarker)) continue;
    if (!seenUrls.add(url)) continue;

    final size = readInt(entry, const ['size', 'fileSize']);
    if (size != null && size >= 1 && size <= 50) continue;

    final name = readString(entry, const ['lanName', 'lan', 'language', 'name']) ?? 'Unknown';
    if (name.toLowerCase() == 'in' && size != null && size <= 100) continue;

    options.add(SubtitleOption(name: name, url: url));
  }

  options.sort((a, b) {
    final aEnglish = a.name.toLowerCase().contains('english');
    final bEnglish = b.name.toLowerCase().contains('english');
    if (aEnglish && !bEnglish) return -1;
    if (bEnglish && !aEnglish) return 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

  return options;
}

List<Release> playInfoJsonToReleases(
  Map<String, dynamic> payload, {
  required int season,
  required int episode,
  required String userAgent,
}) {
  final releases = <Release>[];
  final seen = <String>{};

  for (final entry in readList(payload, const ['streams', 'list', 'playList'])) {
    if (entry is! Map) continue;

    final signCookie = readString(entry, const ['signCookie', 'sign_cookie', 'cookie']);
    final advertised = readString(entry, const ['url', 'playUrl', 'link']);
    final url = resolveStreamUrl(signCookie: signCookie, fallbackUrl: advertised);
    if (url == null) continue;

    final base = url.split('?').first;
    if (base.isEmpty || !seen.add(base)) continue;

    final headers = <String, String>{'Referer': streamReferer, 'User-Agent': userAgent};
    if (signCookie != null && signCookie.isNotEmpty) {
      headers['Cookie'] = normalizeSignCookie(signCookie);
    }

    final resolution = readInt(entry, const ['resolution', 'quality', 'height']);

    releases.add(
      Release(
        kind: ProviderKind.moviebox,
        filename: readString(entry, const ['filename', 'name', 'title']) ?? 'MovieBox stream',
        quality: resolution == null ? null : '${resolution}p',
        codec: readString(entry, const ['codec', 'videoCodec']),
        language: readString(entry, const ['lanName', 'language']),
        sizeBytes: readInt(entry, const ['size', 'fileSize']),
        season: season == 0 ? null : season,
        episode: episode == 0 ? null : episode,
        resourceId: readString(entry, const ['resourceId', 'id']),
        mirrors: [
          SourceMirror(
            label: 'MovieBox',
            url: url,
            headers: headers,
            directFile: !url.endsWith('.mpd'),
          ),
        ],
      ),
    );
  }

  return releases;
}

List<Release> resourceJsonToReleases(
  Map<String, dynamic> payload, {
  required int season,
  required int episode,
}) {
  final releases = <Release>[];
  final seen = <String>{};

  for (final entry in readList(payload, const ['list', 'resources', 'items'])) {
    if (entry is! Map) continue;

    final url = readString(entry, const ['resourceLink', 'url', 'link', 'downloadUrl']);
    if (url == null || url.isEmpty) continue;
    if (isDeprecationNoticeUrl(url)) continue;

    final base = url.split('?').first;
    if (base.isEmpty || !seen.add(base)) continue;

    final entrySeason = readInt(entry, const ['se', 'season']);
    final entryEpisode = readInt(entry, const ['ep', 'episode']);

    final matches =
        (season == 0 && episode == 0) ||
        (entrySeason == season && entryEpisode == episode) ||
        (entrySeason == null && entryEpisode == null);
    if (!matches) continue;

    final resolution = readInt(entry, const ['resolution', 'quality', 'height']);

    releases.add(
      Release(
        kind: ProviderKind.moviebox,
        filename: readString(entry, const ['filename', 'name', 'title']) ?? 'MovieBox file',
        quality: resolution == null ? null : '${resolution}p',
        codec: readString(entry, const ['codec', 'videoCodec']),
        language: readString(entry, const ['lanName', 'language']),
        sizeBytes: readInt(entry, const ['size', 'fileSize']),
        season: entrySeason ?? (season == 0 ? null : season),
        episode: entryEpisode ?? (episode == 0 ? null : episode),
        resourceId: readString(entry, const ['resourceId', 'id']),
        mirrors: [SourceMirror(label: 'MovieBox', url: url, directFile: true)],
      ),
    );
  }

  return releases;
}

List<Release> sortReleases(List<Release> releases) {
  final sorted = [...releases];
  sorted.sort((a, b) {
    final byResolution = b.resolution.compareTo(a.resolution);
    if (byResolution != 0) return byResolution;
    return (b.sizeBytes ?? 0).compareTo(a.sizeBytes ?? 0);
  });
  return sorted;
}
