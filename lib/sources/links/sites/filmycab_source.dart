import 'package:dio/dio.dart';

import '../../../models/provider_kind.dart';
import '../../../models/release.dart';
import '../link_source.dart';
import '../site_domains.dart';
import '../web.dart';

class FilmyCabSource extends LinkSource {
  FilmyCabSource(super.web);

  @override
  ProviderKind get kind => ProviderKind.filmycab;

  String get _base => SiteDomains.of('filmycab');

  @override
  Future<List<Release>> find(LinkQuery query, {CancelToken? cancel}) async {
    if (query.isEpisode) return const [];
    final data = await web.json(
      '$_base/wp-json/wp/v2/search?search=${Uri.encodeQueryComponent(query.title)}&per_page=8',
      cancel: cancel,
    );
    if (data is! List) return const [];

    final releases = <Release>[];
    for (final hit in data) {
      if (hit is! Map) continue;
      final url = '${hit['url'] ?? ''}';
      final title = cleanText('${hit['title'] ?? ''}');
      if (url.isEmpty || !strictTitle(query.title, title, year: query.year)) continue;
      try {
        final page = await web.get(url, referer: '$_base/', cancel: cancel);
        for (final anchor in page.document.querySelectorAll('a')) {
          final href = anchor.attributes['href'] ?? '';
          if (!href.startsWith('http') || !isHostLink(href)) continue;
          final label = '${headingBefore(anchor)} ${cleanText(anchor.text)}'.trim();
          releases.add(release(label, href, query: query, referer: '$_base/', context: title));
        }
      } on Object {
        continue;
      }
      if (releases.length >= 8) break;
    }
    return dedupeReleases(releases);
  }
}
