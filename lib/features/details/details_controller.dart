import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../metadata/cinemeta.dart';
import '../../models/media.dart';
import '../../models/provider_kind.dart';
import '../../models/release.dart';
import '../../player/player_controller.dart';
import '../../sources/content_source.dart';
import '../../sources/registry.dart';
import '../../sources/source_matcher.dart';

final cinemetaProvider = Provider<CinemetaSource>((ref) => CinemetaSource());

class TitleDetails {
  const TitleDetails({required this.item, required this.details, this.matches = const []});

  final CatalogItem item;
  final MediaDetails details;
  final List<SourceMatch> matches;

  bool get isPlayable => matches.isNotEmpty;

  SourceMatch? get bestMatch => matches.isEmpty ? null : matches.first;
}

final titleDetailsProvider = FutureProvider.autoDispose.family<TitleDetails, CatalogItem>((
  ref,
  item,
) async {
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

  return TitleDetails(item: item, details: meta ?? _fallbackDetails(item), matches: matches);
});

MediaDetails _fallbackDetails(CatalogItem item) {
  return MediaDetails(
    id: item.id,
    title: item.title,
    mediaType: item.mediaType,
    year: item.year,
    posterUrl: item.posterUrl,
    backdropUrl: item.backdropUrl,
    logoUrl: item.logoUrl,
    rating: item.rating?.toStringAsFixed(1),
  );
}

class EpisodeRef {
  const EpisodeRef(this.match, {this.season = 0, this.episode = 0});

  final SourceMatch match;
  final int season;
  final int episode;

  @override
  bool operator ==(Object other) =>
      other is EpisodeRef &&
      other.match.kind == match.kind &&
      other.match.id == match.id &&
      other.season == season &&
      other.episode == episode;

  @override
  int get hashCode => Object.hash(match.kind, match.id, season, episode);
}

final releasesProvider = FutureProvider.autoDispose.family<List<Release>, EpisodeRef>((
  ref,
  target,
) async {
  final cancel = CancelToken();
  ref.onDispose(cancel.cancel);

  final source = ref.read(sourceRegistryProvider)[target.match.kind];
  if (source == null) throw const Unavailable();

  return source.releases(
    target.match.id,
    season: target.season,
    episode: target.episode,
    cancel: cancel,
  );
});

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
  final SourceMatch match;
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
  final source = sources[request.match.kind];
  if (source == null) throw const Unavailable();

  final playback = await source.resolve(request.release, cancel: cancel);

  final subtitles = await source.subtitles(
    request.match.id,
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
    mediaId: request.match.id,
  );
}
