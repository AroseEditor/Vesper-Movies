import 'package:dio/dio.dart';
import 'package:html/dom.dart';

import '../../../models/provider_kind.dart';
import '../../../models/release.dart';
import '../link_source.dart';
import '../site_domains.dart';
import '../web.dart';

class TopMoviesSource extends LinkSource {
  TopMoviesSource(super.web);

  @override
  ProviderKind get kind => ProviderKind.topmovies;

  String get _base => SiteDomains.of('topmovies');

  static final _quality = RegExp(r'480p|720p|1080p|2160p|4K', caseSensitive: false);

  @override
  Future<List<Release>> find(LinkQuery query, {CancelToken? cancel}) async {
    final imdb = query.imdbId;
    if (imdb == null) return const [];

    final search = await web.get('$_base/search/$imdb', cancel: cancel);
    final posts = [
      for (final anchor in search.document.querySelectorAll('#content_box article > a'))
        if ((anchor.attributes['href'] ?? '').startsWith('http')) anchor.attributes['href']!,
    ];

    final releases = <Release>[];
    for (final post in posts.take(2)) {
      try {
        final page = await web.get(post, cancel: cancel);
        releases.addAll(
          query.isEpisode
              ? await _episode(page.document, query, cancel)
              : _movie(page.document, query),
        );
      } on Object {
        continue;
      }
    }
    return dedupeReleases(releases);
  }

  List<Release> _movie(Document document, LinkQuery query) {
    final releases = <Release>[];
    for (final heading in document.querySelectorAll('h3')) {
      final text = cleanText(heading.text);
      if (!_quality.hasMatch(text) || text.contains('Batch/Zip') || text.contains('Info:')) {
        continue;
      }
      final next = heading.nextElementSibling;
      if (next == null) continue;
      for (final anchor in next.querySelectorAll('a')) {
        final href = anchor.attributes['href'] ?? '';
        if (!href.startsWith('http') || !anchor.text.contains('Download')) continue;
        releases.add(release(text, href, query: query, referer: '$_base/'));
      }
    }
    return releases.reversed.toList();
  }

  Future<List<Release>> _episode(Document document, LinkQuery query, CancelToken? cancel) async {
    final season = RegExp('Season\\s*0*${query.season}\\b', caseSensitive: false);
    final episode = RegExp('Episode\\s*0*${query.episode}\\b', caseSensitive: false);
    final releases = <Release>[];
    for (final heading in document.querySelectorAll('div.single_post h3, h3')) {
      final text = cleanText(heading.text);
      if (!_quality.hasMatch(text) || !season.hasMatch(text) || text.contains('Batch/Zip')) {
        continue;
      }
      final source = heading.nextElementSibling
          ?.querySelectorAll('a')
          .firstWhere((a) => a.text.contains('G-Drive'), orElse: () => Element.tag('a'))
          .attributes['href'];
      if (source == null || !source.startsWith('http')) continue;
      try {
        final list = await web.get(source, cancel: cancel);
        for (final anchor in list.document.querySelectorAll('h3 a, a')) {
          if (!episode.hasMatch(anchor.text)) continue;
          final href = anchor.attributes['href'] ?? '';
          if (href.startsWith('http')) {
            releases.add(release(text, href, query: query, referer: '$_base/'));
            break;
          }
        }
      } on Object {
        continue;
      }
    }
    return releases;
  }
}
