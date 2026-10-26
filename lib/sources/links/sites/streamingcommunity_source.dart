import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/errors.dart';
import '../../../models/media.dart';
import '../../../models/provider_kind.dart';
import '../../../models/release.dart';
import '../../source_matcher.dart';
import '../link_source.dart';
import '../site_domains.dart';
import '../web.dart';

class StreamingCommunitySource extends LinkSource {
  StreamingCommunitySource(super.web);

  @override
  ProviderKind get kind => ProviderKind.streamingcommunity;

  String get _base => SiteDomains.of('streamingcommunity');

  static final _pagePattern = RegExp(r'data-page="(.*?)"\s*>', dotAll: true);
  static final _iframeSrcPattern = RegExp('<iframe[^>]*src="([^"]+)"');
  static final _tokenPattern = RegExp(r"'token':\s*'([^']*)'");
  static final _expiresPattern = RegExp(r"'expires':\s*'([^']*)'");
  static final _playlistUrlPattern = RegExp(r"url:\s*'([^']*)'");

  static String _unescape(String raw) => raw
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');

  Map<String, dynamic>? _props(String body) {
    final match = _pagePattern.firstMatch(body);
    if (match == null) return null;
    try {
      final decoded = jsonDecode(_unescape(match.group(1)!));
      final props = decoded is Map ? decoded['props'] : null;
      return props is Map<String, dynamic> ? props : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<List<Release>> find(LinkQuery query, {CancelToken? cancel}) async {
    try {
      final search = await web.get(
        '$_base/it/search?q=${Uri.encodeQueryComponent(query.title)}',
        cancel: cancel,
      );
      final titles = _props(search.body)?['titles'];
      if (titles is! List) return const [];

      Map? bestEntry;
      var bestScore = 0;
      for (final entry in titles) {
        if (entry is! Map) continue;
        final name = entry['name'];
        final type = entry['type'];
        if (name is! String || type is! String) continue;
        final airDate = entry['last_air_date'];
        final year = airDate is String && airDate.length >= 4 ? airDate.substring(0, 4) : null;
        final score = scoreCandidate(
          wantedTitle: query.title,
          wantedYear: query.year,
          wantedSeries: query.isEpisode,
          candidate: CatalogItem(
            id: const MediaId(ProviderKind.addons, ''),
            title: name,
            mediaType: type == 'movie' ? MediaType.movie : MediaType.series,
            year: year,
          ),
        );
        if (score < SourceMatcher.minimumScore || score <= bestScore) continue;
        bestScore = score;
        bestEntry = entry;
      }
      if (bestEntry == null) return const [];

      final id = bestEntry['id'];
      final slug = bestEntry['slug'];
      if (id == null || slug is! String || slug.isEmpty) return const [];
      final path = '$id-$slug';

      if (query.isEpisode) {
        final seasonPage = await web.get(
          '$_base/it/titles/$path/season-${query.season}',
          cancel: cancel,
        );
        final loaded = _props(seasonPage.body)?['loadedSeason'];
        final episodes = loaded is Map ? loaded['episodes'] : null;
        if (episodes is! List) return const [];
        final episode = episodes.firstWhere(
          (e) => e is Map && e['number'] == query.episode,
          orElse: () => null,
        );
        if (episode is! Map) return const [];
        final episodeId = episode['id'];
        if (episodeId == null) return const [];
        final url = '$_base/it/iframe/$path?episode_id=$episodeId&next_episode=1';
        return [
          release(
            '${query.title} S${query.season}E${query.episode}',
            url,
            query: query,
            referer: '$_base/',
          ),
        ];
      }

      final url = '$_base/it/iframe/$path';
      return [release(query.title, url, query: query, referer: '$_base/')];
    } on Object {
      return const [];
    }
  }

  @override
  Future<PlaybackSource> resolve(Release release, {CancelToken? cancel}) async {
    final wrapper = await web.get(release.mirrors.first.url, referer: '$_base/', cancel: cancel);
    final embedMatch = _iframeSrcPattern.firstMatch(wrapper.body);
    if (embedMatch == null) throw const Unavailable();
    final embedUrl = _unescape(embedMatch.group(1)!);

    final embed = await web.get(embedUrl, referer: '$_base/', cancel: cancel);
    final token = _tokenPattern.firstMatch(embed.body)?.group(1);
    final expires = _expiresPattern.firstMatch(embed.body)?.group(1);
    final playlist = _playlistUrlPattern.firstMatch(embed.body)?.group(1);
    if (token == null || expires == null || playlist == null) throw const Unavailable();

    return PlaybackSource(
      kind: kind,
      url: '$playlist?token=$token&expires=$expires&h=1#.m3u8',
      headers: {'User-Agent': webUserAgent, 'Referer': 'https://vixcloud.cc/'},
      sourceLabel: release.filename,
    );
  }
}
