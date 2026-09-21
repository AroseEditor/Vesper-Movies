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

final cinemetaProvider = Provider<CinemetaSource>((ref) => CinemetaSource());

class TitleDetails {
  const TitleDetails({
    required this.item,
    required this.details,
    this.matches = const [],
    this.addonCount = 0,
  });

  final CatalogItem item;
  final MediaDetails details;
  final List<SourceMatch> matches;
  final int addonCount;

  bool get hasAddons => addonCount > 0 && item.id.value.startsWith('tt');

  bool get isPlayable => matches.isNotEmpty || hasAddons;

  SourceMatch? get bestMatch => matches.isEmpty ? null : matches.first;

  String get sourceLabel {
    final names = <String>[
      for (final match in matches) match.kind.label,
      if (hasAddons) addonCount == 1 ? '1 addon' : '$addonCount addons',
    ];
    if (names.isEmpty) return 'No source found';
    if (names.length <= 2) return names.join(' and ');
    return '${names.first} and ${names.length - 1} more';
  }
}

final _detailsCache = MemoCache<String, TitleDetails>(
  ttl: const Duration(hours: 6),
);

final titleDetailsProvider = FutureProvider.autoDispose
    .family<TitleDetails, CatalogItem>((ref, item) async {
      final cached = _detailsCache.peek(item.id.toString());
      if (cached != null) return cached;

      final cancel = CancelToken();
      ref.onDispose(cancel.cancel);

      final cinemeta = ref.read(cinemetaProvider);
      final registry = ref.read(sourceRegistryProvider);

      final results = await Future.wait([
        cinemeta.fullDetails(item, cancel: cancel),
        SourceMatcher(registry).findAll(item, cancel: cancel),
      ]);

      final meta = results[0] as MediaDetails?;
      final matches = results[1] as List<SourceMatch>;

      final resolved = TitleDetails(
        item: item,
        details: meta ?? MediaDetails.of(item),
        matches: matches,
        addonCount: ref.read(enabledAddonsProvider).length,
      );

      _detailsCache.put(item.id.toString(), resolved);
      return resolved;
    });

void invalidateDetailsCache() => _detailsCache.clear();

class EpisodeRef {
  const EpisodeRef(
    this.matches,
    this.item, {
    this.season = 0,
    this.episode = 0,
  });

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

final _releasesCache = MemoCache<String, List<Release>>(
  ttl: const Duration(minutes: 20),
);

final releasesProvider = FutureProvider.autoDispose
    .family<List<Release>, EpisodeRef>((ref, target) async {
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
    return await source.releases(
      id,
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
