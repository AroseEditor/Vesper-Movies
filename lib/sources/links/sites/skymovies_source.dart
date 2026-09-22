import 'package:dio/dio.dart';

import '../../../models/provider_kind.dart';
import '../../../models/release.dart';
import '../link_source.dart';
import '../site_domains.dart';
import '../web.dart';

class SkyMoviesSource extends LinkSource {
  SkyMoviesSource(super.web);

  @override
  ProviderKind get kind => ProviderKind.skymovies;

  String get _base => SiteDomains.of('skymovies');

  @override
  Future<List<Release>> find(LinkQuery query, {CancelToken? cancel}) async {
    final wanted = query.year == null ? query.title : '${query.title} (${query.year})';
    final search = await web.get(
      '$_base/search.php?search=${Uri.encodeQueryComponent(wanted)}&cat=All',
      cancel: cancel,
    );

    final releases = <Release>[];
    for (final anchor in search.document.querySelectorAll('div.L a')) {
      final text = cleanText(anchor.text);
      if (!text.toLowerCase().startsWith(wanted.toLowerCase())) continue;
      final episodeEntry = RegExp(r'S\d{2}E\d{2}', caseSensitive: false).hasMatch(text);
      if (query.isEpisode &&
          episodeEntry &&
          !RegExp('E${episodeSlug(query.episode)}', caseSensitive: false).hasMatch(text)) {
        continue;
      }
      final href = anchor.attributes['href'];
      if (href == null) continue;
      try {
        final page = await web.get(absoluteUrl(href, _base), referer: '$_base/', cancel: cancel);
        for (final link in page.document.querySelectorAll('div.Bolly > a')) {
          final target = link.attributes['href'] ?? '';
          final label = cleanText(link.text);
          if (!target.startsWith('http')) continue;
          if (query.isEpisode && !episodeEntry && label.contains('Episode')) {
            if (!label.contains('Episode ${episodeSlug(query.episode)}')) continue;
          }
          releases.add(release(label, target, query: query, referer: '$_base/', context: text));
        }
      } on Object {
        continue;
      }
      if (releases.length >= 10) break;
    }
    return dedupeReleases(releases);
  }
}
