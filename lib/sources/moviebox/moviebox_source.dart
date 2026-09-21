import 'package:dio/dio.dart';

import '../../core/errors.dart';
import '../../models/media.dart';
import '../../models/provider_kind.dart';
import '../../models/release.dart';
import '../content_source.dart';
import 'adapt.dart';
import 'client.dart';
import 'endpoints.dart';

class MovieBoxSource extends BaseContentSource {
  MovieBoxSource({MovieBoxClient? client})
    : _client = client ?? MovieBoxClient();

  final MovieBoxClient _client;

  @override
  ProviderKind get kind => ProviderKind.moviebox;

  @override
  SourceCapabilities get capabilities => const SourceCapabilities(
    search: true,
    pagination: true,
    series: true,
    subtitles: true,
    catalog: true,
  );

  @override
  Future<List<CatalogItem>> search(
    String query, {
    int page = 1,
    CancelToken? cancel,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final payload = await _client.post(
      MovieBoxEndpoints.search,
      MovieBoxEndpoints.searchBody(trimmed, page),
      cancel: cancel,
    );

    final items = searchJsonToCatalog(payload);
    if (items.isEmpty && page == 1) throw const NotFound();
    return items;
  }

  @override
  Future<MediaDetails> details(String id, {CancelToken? cancel}) async {
    final payload = await _client.get(
      MovieBoxEndpoints.details(id),
      cancel: cancel,
    );

    final isSeries = readInt(payload, const ['subjectType', 'stype']) == 2;
    if (isSeries) {
      try {
        final seasons = await _client.get(
          MovieBoxEndpoints.seasonInfo(id),
          cancel: cancel,
        );
        payload['seasons'] = seasons;
      } on SourceError catch (_) {
        return detailsJsonToMediaDetails(payload, id);
      }
    }

    return detailsJsonToMediaDetails(payload, id);
  }

  Future<List<CatalogItem>> homepage(
    String tabId, {
    int page = 1,
    CancelToken? cancel,
  }) async {
    final payload = await _client.get(
      MovieBoxEndpoints.homepage(tabId, page),
      cancel: cancel,
    );
    return homepageJsonToCatalog(payload);
  }

  @override
  Future<List<Release>> releases(
    String id, {
    int season = 0,
    int episode = 0,
    CancelToken? cancel,
  }) async {
    final results = await Future.wait([
      _playInfoReleases(id, season, episode, cancel),
      _resourceReleases(id, season, episode, cancel),
    ]);

    final combined = <Release>[];
    final seen = <String>{};

    for (final group in results) {
      for (final release in group) {
        final url = release.directUrl;
        if (url == null) continue;
        final base = url.split('?').first;
        if (base.isEmpty || !seen.add(base)) continue;
        combined.add(release);
      }
    }

    if (combined.isEmpty) throw const Unavailable();
    return sortReleases(combined);
  }

  Future<List<Release>> _playInfoReleases(
    String id,
    int season,
    int episode,
    CancelToken? cancel,
  ) async {
    try {
      final payload = await _client.get(
        MovieBoxEndpoints.playInfo(id, season: season, episode: episode),
        cancel: cancel,
      );
      return playInfoJsonToReleases(
        payload,
        season: season,
        episode: episode,
        userAgent: _client.identity.userAgent,
      );
    } on Cancelled {
      rethrow;
    } on SourceError catch (_) {
      return const [];
    }
  }

  Future<List<Release>> _resourceReleases(
    String id,
    int season,
    int episode,
    CancelToken? cancel,
  ) async {
    try {
      final payload = await _client.get(
        MovieBoxEndpoints.resource(
          id,
          season: season,
          episode: episode,
          page: MovieBoxEndpoints.pageForEpisode(episode),
        ),
        cancel: cancel,
      );
      return resourceJsonToReleases(payload, season: season, episode: episode);
    } on Cancelled {
      rethrow;
    } on SourceError catch (_) {
      return const [];
    }
  }

  @override
  Future<List<SubtitleOption>> subtitles(
    String id, {
    String? resourceId,
    int season = 0,
    int episode = 0,
    CancelToken? cancel,
  }) async {
    final collected = <SubtitleOption>[];
    final seenUrls = <String>{};

    void absorb(Iterable<SubtitleOption> options) {
      for (final option in options) {
        if (seenUrls.add(option.url)) collected.add(option);
      }
    }

    Map<String, dynamic>? resourcePage;
    try {
      resourcePage = await _client.get(
        MovieBoxEndpoints.resource(
          id,
          season: season,
          episode: episode,
          page: MovieBoxEndpoints.pageForEpisode(episode),
        ),
        cancel: cancel,
      );
    } on Cancelled {
      rethrow;
    } on SourceError catch (_) {
      resourcePage = null;
    }

    final resourceIds = <String>{};
    if (resourceId != null && resourceId.isNotEmpty) {
      resourceIds.add(resourceId);
    }

    if (resourcePage != null) {
      absorb(
        inlineCaptionsFromResources(
          resourcePage,
          season: season,
          episode: episode,
        ),
      );
      resourceIds.addAll(
        resourceIdsFor(resourcePage, season: season, episode: episode),
      );
    }

    for (final candidate in resourceIds.take(4)) {
      try {
        final payload = await _client.get(
          MovieBoxEndpoints.captions(id, candidate),
          cancel: cancel,
        );
        absorb(captionsJsonToOptions(payload));
      } on Cancelled {
        rethrow;
      } on SourceError catch (_) {
        continue;
      }
    }

    return sortCaptions(collected);
  }

  @override
  Future<PlaybackSource> resolve(Release release, {CancelToken? cancel}) async {
    if (release.mirrors.isEmpty) throw const Unavailable();

    final mirror = release.mirrors.first;
    return PlaybackSource(
      kind: kind,
      url: mirror.url,
      headers: mirror.headers,
      sourceLabel: mirror.label,
    );
  }
}
