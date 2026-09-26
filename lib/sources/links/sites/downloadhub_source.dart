import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/dom.dart';

import '../../../models/provider_kind.dart';
import '../../../models/release.dart';
import '../link_source.dart';
import '../site_domains.dart';
import '../web.dart';

class DownloadHubSource extends LinkSource {
  DownloadHubSource(super.web);

  @override
  ProviderKind get kind => ProviderKind.downloadhub;

  String get _base => SiteDomains.of('downloadhub');

  @override
  Future<List<Release>> find(LinkQuery query, {CancelToken? cancel}) async {
    if (query.isEpisode) return const [];

    final search = await web.get(
      '$_base/?s=${Uri.encodeQueryComponent(query.title)}',
      cancel: cancel,
    );

    final posts = <String>[];
    for (final anchor in search.document.querySelectorAll('a')) {
      final href = anchor.attributes['href'] ?? '';
      final label = cleanText(anchor.text);
      if (!href.startsWith(_base) || label.length < 8 || posts.contains(href)) continue;
      if (!strictTitle(query.title, label, year: query.year)) continue;
      posts.add(href);
    }

    final releases = <Release>[];
    for (final post in posts.take(3)) {
      try {
        final page = await web.get(post, cancel: cancel);
        final title = cleanText(page.document.querySelector('h1')?.text ?? '');
        releases.addAll(await _movie(page.document, title, query, post, cancel));
      } on Object {
        continue;
      }
    }
    return dedupeReleases(releases);
  }

  Future<List<Release>> _movie(
    Document document,
    String title,
    LinkQuery query,
    String post,
    CancelToken? cancel,
  ) async {
    final jobs = <Future<Release?>>[];
    for (final heading in document.querySelectorAll('h3')) {
      final quality = RegExp(r'(\d{3,4})p', caseSensitive: false).firstMatch(heading.text);
      if (quality == null) continue;
      final label = '${quality.group(1)}p $title';
      Element? node = heading.nextElementSibling;
      for (var steps = 0; steps < 2 && node != null; steps++) {
        for (final anchor in node.querySelectorAll('a[data-linkid]')) {
          final kindClass = anchor.className;
          if (!kindClass.contains('watch') && !kindClass.contains('red')) continue;
          jobs.add(_open(anchor.attributes['data-linkid'] ?? '', label, query, post, cancel));
        }
        node = node.nextElementSibling;
        if (node != null && (node.localName ?? '') == 'h3') break;
      }
    }
    final found = await Future.wait(jobs);
    return [for (final entry in found) ?entry];
  }

  Future<Release?> _open(
    String linkId,
    String label,
    LinkQuery query,
    String post,
    CancelToken? cancel,
  ) async {
    if (linkId.isEmpty) return null;
    try {
      final response = await web.raw(
        '$_base/wp-admin/admin-ajax.php',
        method: 'POST',
        form: {'action': 'dh_open_link', 'linkid': linkId},
        headers: {'Referer': post},
        follow: false,
        cancel: cancel,
      );
      final location = response.headers.value('location');
      final encoded = location == null ? null : Uri.tryParse(location)?.queryParameters['u'];
      if (encoded == null) return null;
      final padded = encoded.padRight(encoded.length + (4 - encoded.length % 4) % 4, '=');
      final target = utf8.decode(base64.decode(padded), allowMalformed: true);
      if (!target.startsWith('http')) return null;
      return release(label, target, query: query, referer: '$_base/');
    } on Object {
      return null;
    }
  }
}
