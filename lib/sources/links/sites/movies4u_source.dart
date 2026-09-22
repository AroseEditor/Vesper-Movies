import 'package:dio/dio.dart';
import 'package:html/dom.dart';

import '../../../models/provider_kind.dart';
import '../../../models/release.dart';
import '../link_source.dart';
import '../site_domains.dart';
import '../web.dart';

class Movies4uSource extends LinkSource {
  Movies4uSource(super.web);

  @override
  ProviderKind get kind => ProviderKind.movies4u;

  String get _base => SiteDomains.of('movies4u');

  static const _cookies = {'xla': 's4t'};

  @override
  Future<List<Release>> find(LinkQuery query, {CancelToken? cancel}) async {
    final term = query.isEpisode ? '${query.title} season ${query.season}' : query.title;
    final data = await web.json(
      '$_base/wp-json/wp/v2/search?search=${Uri.encodeQueryComponent(term)}&per_page=10',
      cookies: _cookies,
      cancel: cancel,
    );
    if (data is! List) return const [];

    final releases = <Release>[];
    for (final hit in data.take(4)) {
      if (hit is! Map) continue;
      final url = '${hit['url'] ?? ''}';
      final title = '${hit['title'] ?? ''}';
      if (url.isEmpty ||
          !strictTitle(query.title, title, year: query.isEpisode ? null : query.year)) {
        continue;
      }
      try {
        final page = await web.get(url, cookies: _cookies, referer: '$_base/', cancel: cancel);
        final imdb = RegExp(r'imdb\.com/title/(tt\d+)').firstMatch(page.body)?.group(1);
        if (query.imdbId != null && imdb != null && imdb != query.imdbId) continue;
        final context = cleanText(page.document.querySelector('h1')?.text ?? title);
        releases.addAll(
          query.isEpisode
              ? await _episode(page.document, query, cancel)
              : _movie(page.document, query, context),
        );
      } on Object {
        continue;
      }
    }
    return dedupeReleases(releases);
  }

  List<Release> _movie(Document document, LinkQuery query, String context) {
    final releases = <Release>[];
    for (final anchor in document.querySelectorAll('a.btn')) {
      final href = anchor.attributes['href'] ?? '';
      if (!href.startsWith('http') || !isHostLink(href)) continue;
      final label = '${headingBefore(anchor)} ${cleanText(anchor.text)}'.trim();
      releases.add(release(label, href, query: query, referer: '$_base/', context: context));
    }
    return releases;
  }

  Future<List<Release>> _episode(Document document, LinkQuery query, CancelToken? cancel) async {
    final releases = <Release>[];
    for (final block in document.querySelectorAll('div.downloads-btns-div')) {
      final header = cleanText(block.previousElementSibling?.text ?? '');
      if (!RegExp('Season\\s*0*${query.season}\\b', caseSensitive: false).hasMatch(header)) {
        continue;
      }
      final seasonLink = block.querySelector('a.btn')?.attributes['href'];
      if (seasonLink == null || !seasonLink.startsWith('http')) continue;
      try {
        final page = await web.get(seasonLink, cookies: _cookies, cancel: cancel);
        final blocks = page.document.querySelectorAll('div.downloads-btns-div');
        if (query.episode < 1 || query.episode > blocks.length) continue;
        for (final anchor in blocks[query.episode - 1].querySelectorAll('a.btn')) {
          final href = anchor.attributes['href'] ?? '';
          if (href.startsWith('http')) {
            releases.add(release(header, href, query: query, referer: '$_base/'));
          }
        }
      } on Object {
        continue;
      }
    }
    return releases;
  }
}
