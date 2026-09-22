import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/errors.dart';
import '../../../models/provider_kind.dart';
import '../../../models/release.dart';
import '../link_source.dart';
import '../web.dart';

const _main = 'https://net52.cc';

const _apiDomains = [
  'https://mobiledetects.com',
  'https://mobiledetect.app',
  'https://mobidetect.art',
  'https://mobidetect.cc',
  'https://mobidetect.click',
  'https://mobidetect.ink',
  'https://mobidetect.live',
  'https://mobidetect.pro',
];

const _tvHeaders = {
  'Cache-Control': 'no-cache, no-store, must-revalidate',
  'X-Requested-With': 'NetmirrorNewTV v1.0',
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:136.0) Gecko/20100101 Firefox/136.0 /OS.GatuNewTV v1.0',
  'Accept': 'application/json, text/plain, */*',
};

const _otts = {'nf': 'Netflix', 'pv': 'Prime Video', 'hs': 'Hotstar'};

const _languageNames = {
  'hin': 'Hindi',
  'eng': 'English',
  'tam': 'Tamil',
  'tel': 'Telugu',
  'mal': 'Malayalam',
  'kan': 'Kannada',
  'ben': 'Bengali',
  'mar': 'Marathi',
  'kor': 'Korean',
  'jpn': 'Japanese',
  'spa': 'Spanish',
};

String _languages(String codes) {
  final names = [
    for (final code in codes.toLowerCase().split(RegExp(r'[^a-z]+')))
      if (_languageNames[code] != null) _languageNames[code]!,
  ];
  return names.toSet().join(' ');
}

class NfMirrorSource extends LinkSource {
  NfMirrorSource(super.web);

  @override
  ProviderKind get kind => ProviderKind.nfmirror;

  String? _cookie;
  DateTime? _cookieAt;
  String? _apiBase;

  int get _now => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  Future<String> _session(CancelToken? cancel) async {
    final at = _cookieAt;
    if (_cookie != null &&
        at != null &&
        DateTime.now().difference(at) < const Duration(hours: 12)) {
      return _cookie!;
    }
    final response = await web.raw(
      '$_main/verify.php',
      method: 'POST',
      form: {'g-recaptcha-response': '${DateTime.now().microsecondsSinceEpoch}'},
      follow: false,
      headers: const {
        'Origin': 'https://net77.cc',
        'Referer': 'https://net77.cc/verify2',
        'User-Agent': webUserAgent,
      },
      cancel: cancel,
    );
    final cookies = response.headers['set-cookie'] ?? const <String>[];
    for (final cookie in cookies) {
      if (cookie.startsWith('t_hash_t=')) {
        _cookie = cookie.split(';').first.split('=').skip(1).join('=');
        _cookieAt = DateTime.now();
        return _cookie!;
      }
    }
    throw const Unavailable();
  }

  Future<Map<dynamic, dynamic>?> _api(String ott, String path, CancelToken? cancel) async {
    final session = await _session(cancel);
    final data = await web.json(
      '$_main/mobile/${ott == 'nf' ? '' : '$ott/'}$path',
      referer: '$_main/home',
      cookies: {'t_hash_t': session, 'hd': 'on', 'ott': ott},
      cancel: cancel,
    );
    if (data is Map) return data;
    if (data is String && data.trim().startsWith('{')) return jsonDecode(data) as Map;
    return null;
  }

  @override
  Future<List<Release>> find(LinkQuery query, {CancelToken? cancel}) async {
    final results = await Future.wait(
      _otts.keys.map((ott) => _findIn(ott, query, cancel).catchError((Object _) => <Release>[])),
    );
    return dedupeReleases(results.expand((e) => e));
  }

  Future<List<Release>> _findIn(String ott, LinkQuery query, CancelToken? cancel) async {
    final search = await _api(
      ott,
      'search.php?s=${Uri.encodeQueryComponent(query.title)}&t=$_now',
      cancel,
    );
    final hits = search?['searchResult'];
    if (hits is! List) return const [];

    final releases = <Release>[];
    for (final hit in hits.take(4)) {
      if (hit is! Map) continue;
      final id = '${hit['id'] ?? ''}';
      final title = '${hit['t'] ?? ''}';
      if (id.isEmpty || !strictTitle(query.title, title)) continue;

      final post = await _api(ott, 'post.php?id=$id&t=$_now', cancel);
      if (post == null) continue;
      final year = '${post['year'] ?? ''}';
      if (!query.isEpisode && query.year != null && year.isNotEmpty) {
        final gap = (int.tryParse(year) ?? 0) - (int.tryParse(query.year!) ?? 0);
        if (gap.abs() > 1) continue;
      }

      final target = query.isEpisode ? await _episodeId(ott, id, post, query, cancel) : id;
      if (target == null) continue;
      final label = '${_otts[ott]} 1080p WEB-DL ${_languages('${post['d_lang'] ?? ''}')}'.trim();
      releases.add(release(label, 'nfmirror://$ott/$target', query: query));
      break;
    }
    return releases;
  }

  Future<String?> _episodeId(
    String ott,
    String id,
    Map<dynamic, dynamic> post,
    LinkQuery query,
    CancelToken? cancel,
  ) async {
    String? match(Object? episodes) {
      if (episodes is! List) return null;
      for (final episode in episodes) {
        if (episode is! Map) continue;
        final s = int.tryParse('${episode['s']}'.replaceAll(RegExp(r'\D'), ''));
        final e = int.tryParse('${episode['ep']}'.replaceAll(RegExp(r'\D'), ''));
        if (s == query.season && e == query.episode) return '${episode['id']}';
      }
      return null;
    }

    final direct = match(post['episodes']);
    if (direct != null) return direct;

    final seasons = post['season'];
    if (seasons is! List) return null;
    String? seasonId;
    for (final season in seasons) {
      if (season is Map && '${season['s']}' == '${query.season}') seasonId = '${season['id']}';
    }
    if (seasonId == null) return null;

    for (var page = 1; page <= 6; page++) {
      final data = await _api(
        ott,
        'episodes.php?s=$seasonId&series=$id&t=$_now&page=$page',
        cancel,
      );
      final found = match(data?['episodes']);
      if (found != null) return found;
      if (data == null || data['nextPageShow'] == 0 || data['nextPage'] == null) break;
    }
    return null;
  }

  Future<String> _api2(CancelToken? cancel) async {
    final cached = _apiBase;
    if (cached != null) return cached;
    for (final domain in _apiDomains) {
      try {
        final data = await web.json('$domain/checknewtv.php', headers: _tvHeaders, cancel: cancel);
        final token = data is Map ? '${data['token_hash'] ?? ''}' : '';
        if (token.isEmpty) continue;
        final decoded = utf8
            .decode(base64.decode(base64.normalize(token)))
            .replaceAll(RegExp(r'/+$'), '');
        return _apiBase = decoded;
      } on Object {
        continue;
      }
    }
    throw const Unavailable();
  }

  @override
  Future<PlaybackSource> resolve(Release release, {CancelToken? cancel}) async {
    final uri = Uri.parse(release.mirrors.first.url);
    final ott = uri.host;
    final id = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
    final base = await _api2(cancel);
    final data = await web.json(
      '$base/newtv/player.php?id=$id',
      headers: {..._tvHeaders, 'Ott': ott},
      cancel: cancel,
    );
    final link = data is Map ? '${data['video_link'] ?? ''}' : '';
    if (!link.startsWith('http')) throw const Unavailable();
    final referer = data is Map ? '${data['referer'] ?? _main}' : _main;
    final headers = {'Referer': '$referer/', 'User-Agent': _tvHeaders['User-Agent']!};

    final master = await web.raw(link, headers: headers, cancel: cancel);
    final body = master.data ?? '';
    var url = link;
    if (body.contains('https:///')) {
      final host = RegExp(r'https://([^/\s]+)/')
          .firstMatch(body.replaceAll('https:///', ''))
          ?.group(1);
      if (host != null) {
        final fixed = body.replaceAll('https:///', 'https://$host/');
        url = 'data:application/vnd.apple.mpegurl;base64,${base64.encode(utf8.encode(fixed))}';
      }
    }
    return PlaybackSource(
      kind: kind,
      url: url,
      headers: headers,
      sourceLabel: '${_otts[ott]} mirror',
    );
  }
}
