import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/errors.dart';
import '../../../models/provider_kind.dart';
import '../../../models/release.dart';
import '../../source_matcher.dart';
import '../link_source.dart';
import '../site_domains.dart';
import '../web.dart';

class AniZoneSource extends LinkSource {
  AniZoneSource(super.web);

  @override
  ProviderKind get kind => ProviderKind.anizone;

  String get _base => SiteDomains.of('anizone');

  static final _itemsPattern = RegExp(r"items:\s*JSON\.parse\('((?:[^'\\]|\\.)*)'\)", dotAll: true);

  static final _playerPattern = RegExp(
    r"vidstackPlayer\(JSON\.parse\('((?:[^'\\]|\\.)*)'\)\)",
    dotAll: true,
  );

  static String _unescapeJsString(String input) {
    final buffer = StringBuffer();
    var i = 0;
    while (i < input.length) {
      final char = input[i];
      if (char == '\\' && i + 1 < input.length) {
        final next = input[i + 1];
        if (next == 'u' && i + 5 < input.length) {
          final code = int.tryParse(input.substring(i + 2, i + 6), radix: 16);
          if (code != null) {
            buffer.writeCharCode(code);
            i += 6;
            continue;
          }
        } else if (next == '/' || next == "'" || next == '\\') {
          buffer.write(next);
          i += 2;
          continue;
        } else if (next == 'n') {
          buffer.write('\n');
          i += 2;
          continue;
        }
      }
      buffer.write(char);
      i += 1;
    }
    return buffer.toString();
  }

  Object? _parseEmbedded(String body, RegExp pattern) {
    final match = pattern.firstMatch(body);
    if (match == null) return null;
    final jsonText = _unescapeJsString(match.group(1)!);
    try {
      return jsonDecode(jsonText);
    } on Object {
      return null;
    }
  }

  Set<String> _names(Map item) {
    final names = <String>{};
    final mainTitle = item['main_title'];
    if (mainTitle is String && mainTitle.isNotEmpty) names.add(mainTitle);
    final titleList = item['title_list'];
    if (titleList is Map) {
      for (final value in titleList.values) {
        if (value is String && value.isNotEmpty) names.add(value);
      }
    }
    return names;
  }

  @override
  Future<List<Release>> find(LinkQuery query, {CancelToken? cancel}) async {
    final search = await web.get(
      '$_base/anime?search=${Uri.encodeQueryComponent(query.title)}',
      cancel: cancel,
    );

    final items = _parseEmbedded(search.body, _itemsPattern);
    if (items is! List) return const [];

    final wanted = normaliseTitle(query.title);
    String? slug;
    for (final item in items) {
      if (item is! Map) continue;
      final names = _names(item);
      if (!names.any((name) => normaliseTitle(name) == wanted)) continue;
      final candidate = item['slug'];
      if (candidate is String && candidate.isNotEmpty) {
        slug = candidate;
        break;
      }
    }

    if (slug == null) {
      for (final item in items) {
        if (item is! Map) continue;
        final names = _names(item);
        final matched = names.any(
          (name) => sameTitle(query.title, name, year: query.year, series: query.isEpisode),
        );
        if (!matched) continue;
        final candidate = item['slug'];
        if (candidate is String && candidate.isNotEmpty) {
          slug = candidate;
          break;
        }
      }
    }
    if (slug == null) return const [];

    final episode = query.isEpisode ? query.episode : 1;
    return [
      release(
        '${query.title} Episode $episode',
        '$_base/anime/$slug/$episode',
        query: query,
        referer: '$_base/',
      ),
    ];
  }

  @override
  Future<PlaybackSource> resolve(Release release, {CancelToken? cancel}) async {
    final page = await web.get(release.mirrors.first.url, cancel: cancel);
    final data = _parseEmbedded(page.body, _playerPattern);
    if (data is! Map) throw const Unavailable();

    final src = data['src'];
    if (src is! String || src.isEmpty) throw const Unavailable();

    final subtitles = <SubtitleOption>[];
    final subs = data['subtitles'];
    if (subs is List) {
      for (final entry in subs) {
        if (entry is! Map) continue;
        final file = entry['file'];
        if (file is! String || file.isEmpty) continue;
        subtitles.add(SubtitleOption(name: '${entry['title'] ?? 'Subtitle'}', url: file));
      }
    }

    return PlaybackSource(
      kind: kind,
      url: src,
      headers: {'Referer': '$_base/', 'User-Agent': webUserAgent},
      subtitles: subtitles,
      sourceLabel: kind.label,
    );
  }
}
