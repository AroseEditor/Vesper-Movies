import 'package:dio/dio.dart';
import 'package:html/dom.dart';

import '../../../models/provider_kind.dart';
import '../../../models/release.dart';
import '../link_source.dart';
import '../site_domains.dart';
import '../web.dart';

class MoviesDriveSource extends LinkSource {
  MoviesDriveSource(super.web);

  @override
  ProviderKind get kind => ProviderKind.moviesdrive;

  String get _base => SiteDomains.of('moviesdrive');

  @override
  Future<List<Release>> find(LinkQuery query, {CancelToken? cancel}) async {
    final imdb = query.imdbId;
    if (imdb == null) return const [];

    final data = await web.json('$_base/search.php?q=$imdb', cancel: cancel);
    final hits = data is Map ? data['hits'] : null;
    if (hits is! List) return const [];

    final releases = <Release>[];
    for (final hit in hits) {
      if (hit is! Map || hit['document'] is! Map) continue;
      final document = hit['document'] as Map;
      if ('${document['imdb_id']}' != imdb) continue;
      final url = '$_base${document['permalink']}';
      try {
        final page = await web.get(url, cancel: cancel);
        releases.addAll(
          query.isEpisode ? await _episode(page, query, cancel) : _movie(page.document, query),
        );
      } on Object {
        continue;
      }
    }
    return dedupeReleases(releases);
  }

  List<Release> _movie(Document document, LinkQuery query) {
    final releases = <Release>[];
    var context = '';
    for (final heading in document.querySelectorAll('h5')) {
      final text = cleanText(heading.text);
      final anchor = heading.querySelector('a');
      if (anchor == null) {
        if (text.isNotEmpty) context = text;
        continue;
      }
      final href = anchor.attributes['href'] ?? '';
      if (!href.startsWith('http')) continue;
      releases.add(release(text, href, query: query, referer: '$_base/', context: context));
    }
    return releases;
  }

  Future<List<Release>> _episode(WebPage page, LinkQuery query, CancelToken? cancel) async {
    final seasonTag = RegExp(
      'Season\\s*${query.season}\\b|S${episodeSlug(query.season)}\\b',
      caseSensitive: false,
    );
    final episodeTag = RegExp(
      'Ep\\s*0*${query.episode}\\b|Episode\\s*0*${query.episode}\\b',
      caseSensitive: false,
    );

    final releases = <Release>[];
    for (final heading in page.document.querySelectorAll('h5')) {
      final text = cleanText(heading.text);
      if (!seasonTag.hasMatch(text)) continue;
      final pack = heading.nextElementSibling?.querySelector('a')?.attributes['href'];
      if (pack == null || !pack.startsWith('http')) continue;
      try {
        final episodes = await web.get(pack, cancel: cancel);
        for (final entry in episodes.document.querySelectorAll('h5')) {
          if (!episodeTag.hasMatch(entry.text)) continue;
          var sibling = entry.nextElementSibling;
          for (var i = 0; i < 3 && sibling != null; i++) {
            final href = sibling.querySelector('a')?.attributes['href'];
            if (href != null && href.startsWith('http') && isHostLink(href)) {
              releases.add(release(text, href, query: query, referer: '$_base/'));
            }
            sibling = sibling.nextElementSibling;
          }
        }
      } on Object {
        continue;
      }
    }
    return releases;
  }
}
