import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/memo_cache.dart';
import '../../metadata/cinemeta.dart';
import '../../models/media.dart';
import '../../models/provider_kind.dart';
import '../../models/release.dart';
import '../../player/player_controller.dart';
import '../../sources/addons/addon_client.dart';
import '../../sources/addons/addons_store.dart';
import '../../sources/content_source.dart';
import '../../sources/moviebox/adapt.dart';
import '../../sources/registry.dart';
import '../../sources/source_matcher.dart';
import '../home/home_controller.dart';

final cinemetaProvider = Provider<CinemetaSource>((ref) => CinemetaSource());

class TitleDetails {
  const TitleDetails({
    required this.item,
    required this.details,
    this.matches = const [],
    this.addonCount = 0,
    this.matchesPending = false,
  });

  final CatalogItem item;
  final MediaDetails details;
  final List<SourceMatch> matches;
  final int addonCount;
  final bool matchesPending;

  bool get hasAddons => addonCount > 0 && item.id.value.startsWith('tt');

  bool get isPlayable => matches.isNotEmpty || hasAddons;

  SourceMatch? get bestMatch => matches.isEmpty ? null : matches.first;

  TitleDetails withMatches(List<SourceMatch> matches, {required bool pending}) {
    return TitleDetails(
      item: item,
      details: details,
      matches: matches,
      addonCount: addonCount,
      matchesPending: pending,
    );
  }

  String get sourceLabel {
    final names = <String>[
      for (final match in matches) match.kind.label,
      if (hasAddons) addonCount == 1 ? '1 addon' : '$addonCount addons',
    ];
    if (names.isEmpty) return matchesPending ? 'Finding sources' : 'No source found';
    final label = names.length <= 2
        ? names.join(' and ')
        : '${names.first} and ${names.length - 1} more';
    return matchesPending ? '$label, finding more' : label;
  }
}

final _detailsCache = MemoCache<String, MediaDetails>(ttl: const Duration(hours: 6));
final _matchesCache = MemoCache<String, List<SourceMatch>>(ttl: const Duration(hours: 1));

final _imdbIds = MemoCache<String, String>(
  ttl: const Duration(days: 90),
  maxEntries: 2048,
  name: 'imdb-ids',
  encode: (value) => value,
  decode: (raw) => '$raw',
);

Future<CatalogItem> _canonical(Ref ref, CatalogItem item, CancelToken cancel) async {
  final raw = item.id.value;
  if (raw.startsWith('tt')) return item;

  final key = '${item.id.kind.id}:$raw';
  var imdb = _imdbIds.peek(key);

  if (imdb == null && raw.startsWith('tmdb:')) {
    imdb = await ref
        .read(metadataServiceProvider)
        .imdbIdFor(raw, cancel: cancel)
        .timeout(const Duration(seconds: 10), onTimeout: () => null);
  }

  imdb ??= await ref
      .read(cinemetaProvider)
      .findImdbId(item, cancel: cancel)
      .timeout(const Duration(seconds: 10), onTimeout: () => null);

  if (imdb == null) return item;
  _imdbIds.put(key, imdb);

  return item.copyWith(id: MediaId(ProviderKind.addons, imdb));
}

final titleDetailsProvider = FutureProvider.autoDispose.family<TitleDetails, CatalogItem>((
  ref,
  original,
) async {
  final addonCount = ref.read(enabledAddonsProvider).length;
  final cancel = CancelToken();
  ref.onDispose(cancel.cancel);

  final item = await _canonical(ref, original, cancel);
  final key = item.id.toString();

  final cached = _detailsCache.peek(key);
  if (cached != null) {
    return TitleDetails(item: item, details: cached, addonCount: addonCount);
  }

  final meta = await ref
      .read(cinemetaProvider)
      .fullDetails(item, cancel: cancel)
      .timeout(const Duration(seconds: 15), onTimeout: () => null);

  final details = meta ?? MediaDetails.of(item);
  if (meta != null) _detailsCache.put(key, details);

  return TitleDetails(item: item, details: details, addonCount: addonCount);
});

final sourceMatchesProvider = FutureProvider.autoDispose.family<List<SourceMatch>, CatalogItem>((
  ref,
  item,
) async {
  final key = item.id.toString();
  final cached = _matchesCache.peek(key);
  if (cached != null) return cached;

  final cancel = CancelToken();
  ref.onDispose(cancel.cancel);

  final matches = await SourceMatcher(ref.read(sourceRegistryProvider))
      .findAll(item, cancel: cancel)
      .timeout(const Duration(seconds: 20), onTimeout: () => const []);

  _matchesCache.put(key, matches);
  return matches;
});

final matchSeasonsProvider = FutureProvider.autoDispose.family<List<Season>, SourceMatch>((
  ref,
  match,
) async {
  final source = ref.read(sourceRegistryProvider)[match.kind];
  if (source == null) return const [];

  final cancel = CancelToken();
  ref.onDispose(cancel.cancel);

  try {
    final details = await source
        .details(match.id, cancel: cancel)
        .timeout(const Duration(seconds: 15));
    return details.seasons;
  } on Object {
    return const [];
  }
});

void invalidateDetailsCache() {
  _detailsCache.clear();
  _matchesCache.clear();
}

class EpisodeRef {
  const EpisodeRef(this.matches, this.item, {this.season = 0, this.episode = 0});

  final List<SourceMatch> matches;
  final CatalogItem item;
  final int season;
  final int episode;

  String get _key => matches.map((e) => '${e.kind.id}:${e.id}').join('|');

  @override
  bool operator ==(Object other) =>
      other is EpisodeRef &&
      other._key == _key &&
      other.item.id == item.id &&
      other.season == season &&
      other.episode == episode;

  @override
  int get hashCode => Object.hash(_key, item.id, season, episode);
}

final _releasesCache = MemoCache<String, List<Release>>(ttl: const Duration(minutes: 20));

final releasesProvider = FutureProvider.autoDispose.family<List<Release>, EpisodeRef>((
  ref,
  target,
) async {
  final cacheKey = '${target.item.id}:${target.season}:${target.episode}';
  final cached = _releasesCache.peek(cacheKey);
  if (cached != null) return cached;

  final cancel = CancelToken();
  ref.onDispose(cancel.cancel);

  final registry = ref.read(sourceRegistryProvider);
  final addons = ref.read(enabledAddonsProvider);
  final addonClient = ref.read(addonClientProvider);

  final jobs = <Future<List<Release>>>[
    for (final match in target.matches)
      _safeReleases(
        registry[match.kind],
        match.id,
        season: target.season,
        episode: target.episode,
        cancel: cancel,
      ),
    if (target.item.id.value.startsWith('tt'))
      for (final addon in addons)
        _safeAddonStreams(
          addonClient,
          addon,
          target.item.id.value,
          isSeries: target.item.isSeries,
          season: target.season,
          episode: target.episode,
          cancel: cancel,
        ),
  ];

  final results = await Future.wait(jobs);

  final combined = <Release>[];
  final seen = <String>{};
  for (final group in results) {
    for (final release in group) {
      final url = release.directUrl;
      if (url == null || url.isEmpty) continue;
      if (!seen.add(url.split('?').first)) continue;
      combined.add(release);
    }
  }

  if (combined.isEmpty) throw const Unavailable();

  final sorted = sortReleases(combined);
  _releasesCache.put(cacheKey, sorted);
  return sorted;
});

Future<List<Release>> _safeReleases(
  ContentSource? source,
  String id, {
  required int season,
  required int episode,
  CancelToken? cancel,
}) async {
  if (source == null) return const [];
  try {
    return await source.releases(id, season: season, episode: episode, cancel: cancel);
  } on Cancelled {
    rethrow;
  } on Object catch (_) {
    return const [];
  }
}

Future<List<Release>> _safeAddonStreams(
  AddonClient client,
  InstalledAddon addon,
  String imdbId, {
  required bool isSeries,
  required int season,
  required int episode,
  CancelToken? cancel,
}) async {
  try {
    return await client.streams(
      addon,
      imdbId,
      isSeries: isSeries,
      season: season,
      episode: episode,
      cancel: cancel,
    );
  } on Cancelled {
    rethrow;
  } on Object catch (_) {
    return const [];
  }
}

class PlaybackRequest {
  const PlaybackRequest({
    required this.release,
    required this.match,
    required this.title,
    this.subtitle,
    this.season = 0,
    this.episode = 0,
  });

  final Release release;
  final SourceMatch? match;
  final String title;
  final String? subtitle;
  final int season;
  final int episode;
}

Future<PlaybackTarget> resolvePlayback(
  Map<ProviderKind, ContentSource> sources,
  PlaybackRequest request, {
  CancelToken? cancel,
}) async {
  final source = sources[request.release.kind];

  final playback = source == null
      ? PlaybackSource(
          kind: request.release.kind,
          url: request.release.mirrors.first.url,
          headers: request.release.mirrors.first.headers,
          sourceLabel: request.release.sourceLabel,
        )
      : await source.resolve(request.release, cancel: cancel);

  final match = request.match;
  final subtitles = source == null || match == null
      ? const <SubtitleOption>[]
      : await source.subtitles(
          match.id,
          resourceId: request.release.resourceId,
          season: request.season,
          episode: request.episode,
          cancel: cancel,
        );

  return PlaybackTarget(
    source: PlaybackSource(
      kind: playback.kind,
      url: playback.url,
      headers: playback.headers,
      subtitle: playback.subtitle,
      subtitles: subtitles,
      sourceLabel: playback.sourceLabel,
    ),
    title: request.title,
    subtitle: request.subtitle,
    season: request.season == 0 ? null : request.season,
    episode: request.episode == 0 ? null : request.episode,
    mediaId: request.match?.id ?? request.release.resourceId ?? '',
  );
}
