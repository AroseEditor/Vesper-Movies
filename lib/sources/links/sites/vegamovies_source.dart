import 'package:dio/dio.dart';
import 'package:html/dom.dart';

import '../../../models/provider_kind.dart';
import '../../../models/release.dart';
import '../link_source.dart';
import '../site_domains.dart';
import '../web.dart';

class VegaMoviesSource extends LinkSource {
  VegaMoviesSource(super.web);

  @override
  ProviderKind get kind => ProviderKind.vegamovies;

  String get _base => SiteDomains.of('vegamovies');

  @override
  Future<List<Release>> find(LinkQuery query, {CancelToken? cancel}) async {
    final imdb = query.imdbId;
    var hits = imdb == null
        ? const []
        : [
            for (final hit in await _search(imdb, cancel))
              if (hit is Map &&
                  hit['document'] is Map &&
                  (hit['document'] as Map)['imdb_id'] == imdb)
                hit,
          ];
    if (hits.isEmpty) {
      hits = [
        for (final hit in await _search(query.title, cancel))
          if (hit is Map &&
              hit['document'] is Map &&
              strictTitle(
                query.title,
                cleanText('${(hit['document'] as Map)['post_title'] ?? ''}'),
                year: query.isEpisode ? null : query.year,
              ))
            hit,
      ];
    }

    final releases = <Release>[];
    for (final hit in hits.take(4)) {
      if (hit is! Map || hit['document'] is! Map) continue;
      final document = hit['document'] as Map;
      final permalink = '${document['permalink'] ?? ''}';
      final listed = '${document['imdb_id'] ?? ''}';
      if (permalink.isEmpty || (imdb != null && listed.isNotEmpty && listed != imdb)) continue;
      try {
        final page = await web.get(absoluteUrl(permalink, _base), cancel: cancel);
        final onPage = RegExp(r'imdb\.com/title/(tt\d+)').firstMatch(page.body)?.group(1);
        if (imdb != null && onPage != null && onPage != imdb) continue;
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

  Future<List<dynamic>> _search(String term, CancelToken? cancel) async {
    final data = await web.json(
      '$_base/search.php?q=${Uri.encodeQueryComponent(term)}&page=1',
      cancel: cancel,
    );
    final hits = data is Map ? data['hits'] : null;
    return hits is List ? hits : const [];
  }

  List<Release> _movie(Document document, LinkQuery query) {
    final releases = <Release>[];
    for (final button in document.querySelectorAll('button.dwd-button')) {
      final href = button.parent?.attributes['href'];
      if (href == null || !href.startsWith('http')) continue;
      final label = headingBefore(button.parent!);
      releases.add(release(label, href, query: query, referer: '$_base/'));
    }
    return releases;
  }

  Future<List<Release>> _episode(Document document, LinkQuery query, CancelToken? cancel) async {
    final seasonTag = RegExp('Season\\s*0*${query.season}\\b', caseSensitive: false);
    final releases = <Release>[];
    for (final heading in document.querySelectorAll('h3, h4, h5')) {
      final label = cleanText(heading.text);
      if (!seasonTag.hasMatch(label)) continue;
      final anchors = heading.nextElementSibling?.querySelectorAll('a') ?? const <Element>[];
      for (final anchor in anchors) {
        final text = anchor.text;
        final labelled = RegExp(
          'V-Cloud|Single|Episode|G-Direct',
          caseSensitive: false,
        ).hasMatch(text);
        if (!labelled && anchor.querySelector('button.dwd-button') == null) continue;
        final href = anchor.attributes['href'];
        if (href == null || !href.startsWith('http')) continue;
        try {
          final list = await web.get(href, cancel: cancel);
          for (final entry in list.document.querySelectorAll('h4')) {
            final entryText = entry.text;
            if (!entryText.contains('Episode') ||
                !RegExp('\\b0*${query.episode}\\b').hasMatch(entryText)) {
              continue;
            }
            for (final link
                in entry.nextElementSibling?.querySelectorAll('a') ?? const <Element>[]) {
              final target = link.attributes['href'] ?? '';
              if (target.startsWith('http') && isHostLink(target)) {
                releases.add(release(label, target, query: query, referer: '$_base/'));
              }
            }
          }
        } on Object {
          continue;
        }
      }
    }
    return releases;
  }
}
