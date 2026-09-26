import 'package:dio/dio.dart';
import 'package:html/dom.dart';

import '../../../models/provider_kind.dart';
import '../../../models/release.dart';
import '../link_source.dart';
import '../site_domains.dart';
import '../web.dart';

class MoviesModSource extends LinkSource {
  MoviesModSource(super.web);

  @override
  ProviderKind get kind => ProviderKind.moviesmod;

  String get _base => SiteDomains.of('moviesmod');

  @override
  Future<List<Release>> find(LinkQuery query, {CancelToken? cancel}) async {
    final search = await web.get(
      '$_base/?s=${Uri.encodeQueryComponent(query.title)}',
      cancel: cancel,
    );

    final posts = <String>[];
    for (final anchor in search.document.querySelectorAll('article h2 a')) {
      final href = anchor.attributes['href'] ?? '';
      final label = cleanText(anchor.text);
      if (!href.startsWith('http') || posts.contains(href)) continue;
      if (!strictTitle(query.title, label, year: query.isEpisode ? null : query.year)) continue;
      posts.add(href);
    }

    final releases = <Release>[];
    for (final post in posts.take(3)) {
      try {
        final page = await web.get(post, cancel: cancel);
        final listed = RegExp(r'imdb\.com/title/(tt\d+)').firstMatch(page.body)?.group(1);
        final wanted = query.imdbId;
        if (wanted != null && listed != null && listed != wanted) continue;
        releases.addAll(
          query.isEpisode
              ? await _episodes(page.document, query, cancel)
              : _movie(page.document, query),
        );
      } on Object {
        continue;
      }
    }
    return dedupeReleases(releases);
  }

  Iterable<Element> _buttons(Element heading) sync* {
    Element? node = heading.nextElementSibling;
    for (var steps = 0; steps < 3 && node != null; steps++) {
      final tag = node.localName ?? '';
      if (RegExp(r'^h[1-6]$').hasMatch(tag)) return;
      yield* node.querySelectorAll('a.maxbutton');
      node = node.nextElementSibling;
    }
  }

  List<Release> _movie(Document document, LinkQuery query) {
    final releases = <Release>[];
    for (final heading in document.querySelectorAll('.entry-content h3, .entry-content h4')) {
      final label = cleanText(heading.text);
      if (!RegExp(r'\d{3,4}p|4K', caseSensitive: false).hasMatch(label)) continue;
      for (final button in _buttons(heading)) {
        final href = button.attributes['href'] ?? '';
        if (href.startsWith('http')) {
          releases.add(release(label, href, query: query, referer: '$_base/'));
        }
      }
    }
    return releases;
  }

  Future<List<Release>> _episodes(Document document, LinkQuery query, CancelToken? cancel) async {
    final season = RegExp('Season\\s*0*${query.season}\\b', caseSensitive: false);
    final wanted = RegExp('Episode\\s*0*${query.episode}\\b', caseSensitive: false);
    final server = RegExp(r'G-?Drive|G-?Direct|Episode\s*Links?', caseSensitive: false);
    final jobs = <Future<Release?>>[];

    for (final heading in document.querySelectorAll('.entry-content h3, .entry-content h4')) {
      final label = cleanText(heading.text);
      if (!season.hasMatch(label)) continue;
      for (final button in _buttons(heading)) {
        final name = cleanText(button.text);
        if (!server.hasMatch(name)) continue;
        final href = button.attributes['href'] ?? '';
        if (!href.startsWith('http')) continue;
        jobs.add(_episode(href, label, wanted, query, cancel));
      }
    }

    final found = await Future.wait(jobs);
    return [for (final entry in found) ?entry];
  }

  Future<Release?> _episode(
    String listUrl,
    String label,
    RegExp wanted,
    LinkQuery query,
    CancelToken? cancel,
  ) async {
    try {
      final list = await web.get(listUrl, referer: '$_base/', cancel: cancel);
      for (final anchor in list.document.querySelectorAll('h3 a, h4 a, a')) {
        if (!wanted.hasMatch(anchor.text)) continue;
        final href = anchor.attributes['href'] ?? '';
        if (href.startsWith('http')) {
          return release(label, href, query: query, referer: '$_base/');
        }
      }
    } on Object {
      return null;
    }
    return null;
  }
}
