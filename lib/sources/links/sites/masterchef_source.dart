import 'package:dio/dio.dart';

import '../../../core/errors.dart';
import '../../../models/provider_kind.dart';
import '../../../models/release.dart';
import '../../cloudflare/cloudflare_gate.dart';
import '../link_source.dart';
import '../web.dart';

const _cfDomains = ['a.111477.xyz', 'p.111477.xyz'];

class MasterChefSource extends LinkSource {
  MasterChefSource(super.web);

  @override
  ProviderKind get kind => ProviderKind.masterchef;

  static const _base = 'https://a.111477.xyz';

  @override
  Future<List<Release>> find(LinkQuery query, {CancelToken? cancel}) async {
    if (!cloudflareGateAvailable) return const [];
    if (!query.title.toLowerCase().contains('masterchef')) return const [];
    if (!query.isEpisode) return const [];

    final show = Uri.encodeComponent(query.title);
    final seasonLabel = 'Season ${query.season}';
    final seasonUrl = '$_base/tvs/$show/${Uri.encodeComponent(seasonLabel)}/';

    try {
      final page = await web.get(seasonUrl, cancel: cancel);
      final episodeTag = RegExp('S0*${query.season}E0*${query.episode}\\b', caseSensitive: false);

      for (final anchor in page.document.querySelectorAll('a[href]')) {
        final href = anchor.attributes['href'] ?? '';
        final label = cleanText(anchor.text.isEmpty ? href : anchor.text);
        if (!episodeTag.hasMatch(href) && !episodeTag.hasMatch(label)) continue;
        if (href.endsWith('/')) continue;

        final url = absoluteUrl(href, seasonUrl);
        return [release(label.isEmpty ? url : label, url, query: query)];
      }
      return const [];
    } on Object {
      return const [];
    }
  }

  @override
  Future<PlaybackSource> resolve(Release release, {CancelToken? cancel}) async {
    final url = release.mirrors.first.url;

    for (final domain in _cfDomains) {
      final cached = await cachedClearanceCookie(domain);
      if (cached == null) continue;
      final playable = await _probe(url, cached, cancel);
      if (playable != null) {
        return PlaybackSource(
          kind: kind,
          url: playable,
          headers: {'User-Agent': webUserAgent, 'Cookie': cached},
          sourceLabel: release.filename,
        );
      }
    }

    final challengeUrl = await _challengeUrl(url, cancel);
    final cookie = await solveCloudflareChallenge(
      url: challengeUrl ?? url,
      cookieDomains: _cfDomains,
    );
    if (cookie == null) throw const Unavailable();

    final playable = await _probe(url, cookie, cancel);
    if (playable == null) throw const Unavailable();

    return PlaybackSource(
      kind: kind,
      url: playable,
      headers: {'User-Agent': webUserAgent, 'Cookie': cookie},
      sourceLabel: release.filename,
    );
  }

  Future<String?> _challengeUrl(String url, CancelToken? cancel) async {
    try {
      final response = await web.raw(
        url,
        follow: false,
        headers: {'User-Agent': webUserAgent},
        cancel: cancel,
      );
      final location = response.headers.value('location');
      if (location == null) return null;
      return Uri.parse(url).resolve(location).toString();
    } on Object {
      return null;
    }
  }

  Future<String?> _probe(String url, String cookie, CancelToken? cancel) async {
    try {
      final headers = {'User-Agent': webUserAgent, 'Cookie': cookie};
      final direct = await web.raw(url, follow: false, headers: headers, cancel: cancel);
      final status = direct.statusCode ?? 0;
      if (status == 200 || status == 206) return url;
      if (status < 300 || status >= 400) return null;

      final location = direct.headers.value('location');
      if (location == null) return null;
      final proxied = Uri.parse(url).resolve(location).toString();

      final proxiedResponse = await web.raw(
        proxied,
        follow: false,
        headers: headers,
        cancel: cancel,
      );
      final proxiedStatus = proxiedResponse.statusCode ?? 0;
      final contentType = proxiedResponse.headers.value('content-type') ?? '';
      if ((proxiedStatus == 200 || proxiedStatus == 206) && contentType.contains('video')) {
        return proxied;
      }
      return null;
    } on Object {
      return null;
    }
  }
}
