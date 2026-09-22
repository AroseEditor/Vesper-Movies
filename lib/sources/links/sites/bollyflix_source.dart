import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../models/provider_kind.dart';
import '../../../models/release.dart';
import '../link_source.dart';
import '../site_domains.dart';
import '../web.dart';

class BollyflixSource extends LinkSource {
  BollyflixSource(super.web);

  @override
  ProviderKind get kind => ProviderKind.bollyflix;

  String get _base => SiteDomains.of('bollyflix');

  @override
  Future<List<Release>> find(LinkQuery query, {CancelToken? cancel}) async {
    final imdb = query.imdbId;
    if (imdb == null) return const [];

    final search = await web.get('$_base/search/$imdb', cancel: cancel);
    final posts = [
      for (final anchor in search.document.querySelectorAll('div > article > a'))
        if ((anchor.attributes['href'] ?? '').startsWith('http')) anchor.attributes['href']!,
    ];

    final releases = <Release>[];
    for (final post in posts.take(3)) {
      if (post.contains('adult')) continue;
      try {
        final page = await web.get(post, cancel: cancel);
        final heading = query.isEpisode ? 'h4' : 'h5';
        final quality = RegExp(r'480p|720p|1080p|2160p', caseSensitive: false);
        final season = RegExp('Season\\s*0*${query.season}\\b', caseSensitive: false);

        for (final entry in page.document.querySelectorAll('div.thecontent $heading')) {
          final text = cleanText(entry.text);
          if (!quality.hasMatch(text) || text.toLowerCase().contains('download')) continue;
          if (query.isEpisode && !season.hasMatch(text)) continue;
          var href = entry.nextElementSibling?.querySelector('a')?.attributes['href'];
          if (href == null || !href.startsWith('http')) continue;
          href = await _unwrap(href, cancel);
          if (href == null) continue;

          if (query.isEpisode) {
            final episodes = await web.get(href, cancel: cancel);
            final wanted = 'Episode ${episodeSlug(query.episode)}';
            for (final link in episodes.document.querySelectorAll('article h3 a')) {
              if (!link.text.contains(wanted)) continue;
              final target = link.attributes['href'] ?? '';
              if (target.startsWith('http')) {
                releases.add(release(text, target, query: query, referer: '$_base/'));
              }
            }
          } else {
            releases.add(release(text, href, query: query, referer: '$_base/'));
          }
        }
      } on Object {
        continue;
      }
    }
    return dedupeReleases(releases);
  }

  Future<String?> _unwrap(String href, CancelToken? cancel) async {
    if (href.contains('fastdlserver') || !href.contains('?id=')) return href;
    try {
      final token = href.split('id=').last;
      final page = await web.get('https://web.sidexfee.com/?id=$token', cancel: cancel);
      final encoded = page.body.split('link":"').last.split('"};').first;
      final decoded = utf8.decode(base64.decode(base64.normalize(encoded)));
      return decoded.startsWith('http') ? decoded : null;
    } on Object {
      return null;
    }
  }
}
