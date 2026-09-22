import 'package:dio/dio.dart';
import 'package:html/dom.dart';

import '../../../models/provider_kind.dart';
import '../../../models/release.dart';
import '../link_source.dart';
import '../site_domains.dart';
import '../web.dart';

class HdHub4uSource extends LinkSource {
  HdHub4uSource(super.web);

  @override
  ProviderKind get kind => ProviderKind.hdhub4u;

  String get _base => SiteDomains.of('hdhub4u');

  static final _qualityText = RegExp(r'\d{3,4}p|4k', caseSensitive: false);

  @override
  Future<List<Release>> find(LinkQuery query, {CancelToken? cancel}) async {
    final term = query.imdbId ?? query.title;
    final api = Uri.https('search.pingora.fyi', '/collections/post/documents/search', {
      'q': term,
      'query_by': 'post_title,category,stars,director,imdb_id',
      'query_by_weights': '4,2,2,2,4',
      'sort_by': 'sort_by_date:desc',
      'limit': '15',
      'highlight_fields': 'none',
      'use_cache': 'true',
      'page': '1',
    });
    final data = await web.json(api.toString(), referer: '$_base/', cancel: cancel);
    final hits = data is Map ? data['hits'] : null;
    if (hits is! List) return const [];

    final pages = <String>[];
    for (final hit in hits) {
      if (hit is! Map) continue;
      final document = hit['document'];
      if (document is! Map) continue;
      final permalink = '${document['permalink'] ?? ''}';
      final title = '${document['post_title'] ?? ''}';
      final imdb = '${document['imdb_id'] ?? ''}';
      if (permalink.isEmpty) continue;

      final matches = query.imdbId != null
          ? imdb == query.imdbId
          : sameTitle(query.title, title, year: query.year, series: query.isEpisode);
      if (!matches) continue;
      if (query.isEpisode && !_hasSeason(title, query.season)) continue;

      final path = Uri.parse(permalink).path;
      pages.add('$_base$path');
    }

    final results = await Future.wait(pages.take(3).map((url) => _page(url, query, cancel)));
    return dedupeReleases(results.expand((e) => e));
  }

  static bool _hasSeason(String text, int season) =>
      RegExp('(?:Season\\s*0*|S0*)$season\\b', caseSensitive: false).hasMatch(text);

  Future<List<Release>> _page(String url, LinkQuery query, CancelToken? cancel) async {
    try {
      final page = await web.get(url, cancel: cancel);
      final document = page.document;
      final title = cleanText(
        '${document.querySelector('title')?.text ?? ''} '
        '${document.querySelector('h1.page-title, h2.kno-ecr-pt')?.text ?? ''}',
      );

      final anchors = query.isEpisode
          ? _episodeAnchors(document, query.episode)
          : _movieAnchors(document);
      final releases = <Release>[];
      for (final anchor in anchors) {
        final href = anchor.attributes['href'] ?? '';
        if (!href.startsWith('http') || !isHostLink(href)) continue;
        final label = cleanText(anchor.text);
        if (!query.isEpisode && !_qualityText.hasMatch(label)) continue;
        releases.add(release(label, href, query: query, referer: '$_base/', context: title));
      }
      return releases;
    } on Object {
      return const [];
    }
  }

  List<Element> _movieAnchors(Document document) {
    return document.querySelectorAll('a[data-wpel-link="external"]');
  }

  List<Element> _episodeAnchors(Document document, int episode) {
    final target = RegExp('\\bEPiSODE\\s*0*$episode\\b', caseSensitive: false);
    final anyEpisode = RegExp(r'\bEPiSODE\s*\d+\b', caseSensitive: false);

    Element? header;
    for (final element in document.querySelectorAll('h3, h4, h5, p')) {
      if (target.hasMatch(element.text)) {
        header = element;
        break;
      }
    }
    if (header == null) return const [];
    while (header!.parent != null &&
        const {'h3', 'h4', 'h5', 'p'}.contains(header.parent!.localName)) {
      header = header.parent;
    }

    final anchors = <Element>[...header.querySelectorAll('a[data-wpel-link="external"]')];
    var sibling = header.nextElementSibling;
    while (sibling != null) {
      if (sibling.localName == 'hr' || anyEpisode.hasMatch(sibling.text)) break;
      anchors.addAll(sibling.querySelectorAll('a[data-wpel-link="external"]'));
      sibling = sibling.nextElementSibling;
    }
    return anchors;
  }
}
