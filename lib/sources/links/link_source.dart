import 'package:dio/dio.dart';
import 'package:html/dom.dart';

import '../../core/errors.dart';
import '../../models/media.dart';
import '../../models/provider_kind.dart';
import '../../models/release.dart';
import '../source_matcher.dart';
import 'hosts.dart';
import 'release_tags.dart';
import 'web.dart';

class LinkQuery {
  const LinkQuery({required this.title, this.imdbId, this.year, this.season = 0, this.episode = 0});

  final String title;
  final String? imdbId;
  final String? year;
  final int season;
  final int episode;

  bool get isEpisode => season > 0;

  String get titleYear => year == null || year!.isEmpty ? title : '$title $year';
}

abstract class LinkSource {
  LinkSource(this.web) : hosts = HostResolver(web);

  final Web web;
  final HostResolver hosts;

  ProviderKind get kind;

  Future<List<Release>> find(LinkQuery query, {CancelToken? cancel});

  Future<PlaybackSource> resolve(Release release, {CancelToken? cancel}) async {
    final mirror = release.mirrors.first;
    if (mirror.directFile) {
      return PlaybackSource(
        kind: kind,
        url: mirror.url,
        headers: mirror.headers,
        sourceLabel: mirror.label,
      );
    }
    final files = await hosts.resolve(
      mirror.url,
      referer: mirror.headers['Referer'],
      cancel: cancel,
    );
    if (files.isEmpty) throw const Unavailable();
    final file = files.first;
    return PlaybackSource(
      kind: kind,
      url: file.url,
      headers: {'User-Agent': webUserAgent, ...file.headers},
      sourceLabel: '${kind.label} ${file.server}',
    );
  }

  Release release(
    String label,
    String url, {
    LinkQuery? query,
    String? referer,
    bool direct = false,
    String context = '',
  }) {
    final tags = parseReleaseTags(context.isEmpty ? label : '$label $context');
    return Release(
      kind: kind,
      filename: label.isEmpty ? kind.label : label,
      quality: tags.quality,
      codec: tags.codec,
      language: tags.language,
      rip: tags.rip,
      sizeBytes: tags.sizeBytes,
      season: query != null && query.isEpisode ? query.season : null,
      episode: query != null && query.isEpisode ? query.episode : null,
      mirrors: [
        SourceMirror(
          label: hostLabel(url),
          url: url,
          headers: {'Referer': ?referer},
          directFile: direct,
        ),
      ],
    );
  }
}

String hostLabel(String url) {
  final host = Uri.tryParse(url)?.host ?? '';
  final parts = host.split('.');
  if (parts.length < 2) return host;
  final name = parts[parts.length - 2];
  return name.isEmpty ? host : '${name[0].toUpperCase()}${name.substring(1)}';
}

bool isHostLink(String href) {
  final lower = href.toLowerCase();
  const hosts = [
    'hubcloud',
    'vcloud',
    'hubdrive',
    'hubcdn',
    'hblinks',
    'greenmotors',
    'gadgetsweb',
    'gdflix',
    'gdlink',
    'fastdlserver',
    'pixeldrain',
    'driveleech',
    'driveseed',
    'm4ulinks',
    'filescab',
    'nexdrive',
    'leechpro',
    'molop',
    'm4uplay',
    'hdstream4u',
    '/play?v=',
    '?sid=',
  ];
  return hosts.any(lower.contains);
}

String headingBefore(Element element) {
  Element? node = element;
  for (var depth = 0; depth < 4 && node != null; depth++) {
    var sibling = node.previousElementSibling;
    for (var steps = 0; steps < 6 && sibling != null; steps++) {
      final tag = sibling.localName ?? '';
      final text = cleanText(sibling.text);
      final isHeading = RegExp(r'^h[1-6]$').hasMatch(tag) || tag == 'strong' || tag == 'b';
      final short = text.length <= 140;
      if (text.isNotEmpty &&
          short &&
          (isHeading || RegExp(r'\d{3,4}p|4k', caseSensitive: false).hasMatch(text))) {
        return text;
      }
      sibling = sibling.previousElementSibling;
    }
    node = node.parent;
  }
  return '';
}

bool sameTitle(String wanted, String found, {String? year, bool series = false}) {
  return scoreCandidate(
        wantedTitle: wanted,
        wantedYear: year,
        wantedSeries: series,
        candidate: candidateFor(found, series),
      ) >=
      SourceMatcher.minimumScore;
}

bool strictTitle(String wanted, String found, {String? year}) {
  final a = normaliseTitle(wanted);
  final full = normaliseTitle(
    found.replaceFirst(RegExp(r'^\s*Download\s+', caseSensitive: false), ''),
  );
  if (a.isEmpty || !(full == a || full.startsWith('$a '))) return false;

  final rest = full.substring(a.length).trim();
  final next = rest.split(' ').first;
  final boundary = RegExp(
    r'^((19|20)\d{2}|s\d+|season|\d{3,4}p|4k|hindi|dual|multi|english|tamil|telugu|malayalam|kannada|web|hd|hq|org|full|movie|complete|uncut|extended|bluray|camrip|hdtc|hdts|predvd|nf|amzn)$',
  );
  if (rest.isNotEmpty && !boundary.hasMatch(next)) return false;

  final wantedYear = int.tryParse(year ?? '');
  final foundYear = int.tryParse(RegExp(r'\b(19|20)\d{2}\b').firstMatch(rest)?.group(0) ?? '');
  if (wantedYear == null || foundYear == null) return true;
  return (wantedYear - foundYear).abs() <= 1;
}

CatalogItem candidateFor(String raw, bool series) {
  final year = RegExp(r'\b(19|20)\d{2}\b').firstMatch(raw)?.group(0);
  final title = raw
      .split(RegExp(r'\(|\[|\b(19|20)\d{2}\b|\bS\d{1,2}\b|\bSeason\b', caseSensitive: false))
      .first
      .replaceAll(RegExp(r'^\s*Download\s+', caseSensitive: false), '')
      .trim();
  return CatalogItem(
    id: const MediaId(ProviderKind.addons, ''),
    title: title.isEmpty ? raw : title,
    mediaType: series ? MediaType.series : MediaType.movie,
    year: year,
  );
}

String episodeSlug(int value) => value.toString().padLeft(2, '0');

List<Release> dedupeReleases(Iterable<Release> releases) {
  final seen = <String>{};
  return [
    for (final release in releases)
      if (seen.add(release.mirrors.first.url)) release,
  ];
}
