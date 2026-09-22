import 'package:dio/dio.dart';

import '../../../models/provider_kind.dart';
import '../../../models/release.dart';
import '../link_source.dart';
import '../site_domains.dart';
import '../web.dart';

class UhdMoviesSource extends LinkSource {
  UhdMoviesSource(super.web);

  @override
  ProviderKind get kind => ProviderKind.uhdmovies;

  String get _base => SiteDomains.of('uhdmovies');

  @override
  Future<List<Release>> find(LinkQuery query, {CancelToken? cancel}) async {
    final search = await web.get(
      '$_base/search/${Uri.encodeComponent(query.titleYear)}',
      cancel: cancel,
    );

    final posts = <String>[];
    for (final anchor in search.document.querySelectorAll(
      'article div.entry-image a, article h2 a',
    )) {
      final href = anchor.attributes['href'] ?? '';
      final label = anchor.attributes['title'] ?? cleanText(anchor.text);
      if (!href.startsWith('http') || posts.contains(href)) continue;
      final slug = Uri.parse(href).pathSegments
          .where((s) => s.isNotEmpty)
          .last
          .replaceAll('-', ' ');
      if (!strictTitle(
        query.title,
        label.isEmpty ? slug : label,
        year: query.isEpisode ? null : query.year,
      )) {
        continue;
      }
      posts.add(href);
    }

    final releases = <Release>[];
    for (final post in posts.take(2)) {
      try {
        final page = await web.get(post, cancel: cancel);
        final season = RegExp(
          'S0?${query.season}\\b|Season 0?${query.season}\\b',
          caseSensitive: false,
        );
        final linkText = query.isEpisode
            ? RegExp('Episode\\s*0*${query.episode}\\b', caseSensitive: false)
            : RegExp('Download', caseSensitive: false);

        for (final paragraph in page.document.querySelectorAll('div.entry-content p')) {
          final text = cleanText(paragraph.text);
          if (text.isEmpty) continue;
          if (query.isEpisode
              ? !season.hasMatch(text)
              : (query.year != null && !text.contains(query.year!))) {
            continue;
          }
          final next = paragraph.nextElementSibling;
          if (next == null) continue;
          for (final anchor in next.querySelectorAll('a')) {
            if (!linkText.hasMatch(anchor.text)) continue;
            final href = anchor.attributes['href'] ?? '';
            if (href.startsWith('http')) {
              releases.add(release(text, href, query: query, referer: '$_base/'));
            }
          }
        }
      } on Object {
        continue;
      }
    }
    return dedupeReleases(releases);
  }
}
