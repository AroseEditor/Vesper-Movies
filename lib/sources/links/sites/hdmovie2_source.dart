import 'package:dio/dio.dart';

import '../../../models/provider_kind.dart';
import '../../../models/release.dart';
import '../link_source.dart';
import '../site_domains.dart';
import '../web.dart';

class HdMovie2Source extends LinkSource {
  HdMovie2Source(super.web);

  @override
  ProviderKind get kind => ProviderKind.hdmovie2;

  String get _base => SiteDomains.of('hdmovie2');

  @override
  Future<List<Release>> find(LinkQuery query, {CancelToken? cancel}) async {
    final search = await web.get(
      '$_base/?s=${Uri.encodeQueryComponent(query.title)}',
      cancel: cancel,
    );

    final pages = <String>{};
    for (final anchor in search.document.querySelectorAll('a')) {
      final href = anchor.attributes['href'] ?? '';
      if (!href.contains('/movies/')) continue;
      final slug = Uri.parse(href).pathSegments.where((s) => s.isNotEmpty).last;
      final readable = slug.replaceFirst(RegExp(r'^\d+-'), '').replaceAll('-', ' ');
      final isSeason = RegExp(r'\bseason\b').hasMatch(readable);
      if (query.isEpisode != isSeason) continue;
      if (query.isEpisode && !RegExp('season ${query.season}\\b').hasMatch(readable)) continue;
      final year = query.isEpisode ? null : query.year;
      if (!strictTitle(query.title, readable, year: year)) continue;
      pages.add(href);
    }

    final releases = <Release>[];
    for (final url in pages.take(3)) {
      try {
        final page = await web.get(url, referer: '$_base/', cancel: cancel);
        final title = cleanText(page.document.querySelector('h1')?.text ?? '');
        for (final option in page.document.querySelectorAll('[data-source]')) {
          final source = option.attributes['data-source'] ?? '';
          if (!source.startsWith('http') || source.contains('youtube')) continue;
          final label = cleanText(option.text);
          if (query.isEpisode) {
            final episode = RegExp(
              r'EP\s*0*(\d+)',
              caseSensitive: false,
            ).firstMatch(label)?.group(1);
            if (episode == null || int.parse(episode) != query.episode) continue;
          }
          releases.add(release('$title $label'.trim(), source, query: query, referer: '$_base/'));
        }
      } on Object {
        continue;
      }
    }
    return dedupeReleases(releases);
  }
}
