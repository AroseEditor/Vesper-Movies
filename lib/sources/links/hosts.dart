import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart';

import 'site_domains.dart';
import 'web.dart';

class HostFile {
  const HostFile({
    required this.url,
    required this.server,
    this.name,
    this.size,
    this.headers = const {},
    this.isHls = false,
  });

  final String url;
  final String server;
  final String? name;
  final String? size;
  final Map<String, String> headers;
  final bool isHls;
}

const _serverRank = [
  'FSLv2',
  'FSL',
  'Direct',
  'Cloud',
  'Instant',
  'ResumeCloud',
  'Download',
  'Pixeldrain',
  '10Gbps',
  'Buzz',
  'HLS',
];

int _rankOf(HostFile file) {
  final index = _serverRank.indexOf(file.server);
  return index < 0 ? _serverRank.length : index;
}

String _b64(String value) {
  final cleaned = value.trim().replaceAll('-', '+').replaceAll('_', '/');
  final padded = cleaned.padRight(cleaned.length + (4 - cleaned.length % 4) % 4, '=');
  return utf8.decode(base64.decode(padded), allowMalformed: true);
}

String _rot13(String value) {
  return String.fromCharCodes(
    value.codeUnits.map((c) {
      if (c >= 65 && c <= 90) return (c - 65 + 13) % 26 + 65;
      if (c >= 97 && c <= 122) return (c - 97 + 13) % 26 + 97;
      return c;
    }),
  );
}

String? unpackJs(String source) {
  final match = RegExp(
    r"\}\s*\(\s*'(.*?)'\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*'(.*?)'\.split\('\|'\)",
    dotAll: true,
  ).firstMatch(source);
  if (match == null) return null;

  final payload = match.group(1)!.replaceAll(r"\'", "'");
  final radix = int.parse(match.group(2)!);
  final count = int.parse(match.group(3)!);
  final words = match.group(4)!.split('|');

  String encode(int value) {
    const alphabet = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
    if (value == 0) return '0';
    final buffer = StringBuffer();
    var n = value;
    while (n > 0) {
      buffer.write(alphabet[n % radix]);
      n ~/= radix;
    }
    return buffer.toString().split('').reversed.join();
  }

  final dictionary = <String, String>{};
  for (var i = count - 1; i >= 0; i--) {
    final key = encode(i);
    dictionary[key] = i < words.length && words[i].isNotEmpty ? words[i] : key;
  }

  return payload.replaceAllMapped(RegExp(r'\b\w+\b'), (m) => dictionary[m[0]!] ?? m[0]!);
}

class HostResolver {
  HostResolver(this.web);

  final Web web;

  static const _maxDepth = 5;

  Future<List<HostFile>> resolve(String url, {String? referer, CancelToken? cancel}) async {
    final files = await _resolve(url, referer: referer, cancel: cancel, depth: 0);
    final seen = <String>{};
    final unique = [
      for (final file in files)
        if (seen.add(file.url)) file,
    ]..sort((a, b) => _rankOf(a).compareTo(_rankOf(b)));
    return unique;
  }

  Future<List<HostFile>> _resolve(
    String url, {
    String? referer,
    CancelToken? cancel,
    required int depth,
  }) async {
    if (depth > _maxDepth || url.isEmpty) return const [];
    final lower = url.toLowerCase();

    try {
      if (_isDirectFile(lower)) {
        return [HostFile(url: url, server: 'Direct', isHls: lower.contains('.m3u8'))];
      }
      if (lower.contains('pixeldrain')) return [_pixeldrain(url)];
      if (lower.contains('greenmotors') ||
          lower.contains('gadgetsweb') ||
          lower.contains('greenmount')) {
        final target = await _decodeRedirect(url, cancel);
        return target == null ? const [] : await _resolve(target, cancel: cancel, depth: depth + 1);
      }
      if (lower.contains('hubcdn.')) return await _hubcdn(url, cancel, depth);
      if (lower.contains('hblinks')) {
        return await _linkPage(url, cancel, depth, 'div#primary a, .entry-content a');
      }
      if (lower.contains('hubdrive')) return await _hubdrive(url, cancel, depth);
      if (lower.contains('hubcloud') || lower.contains('vcloud')) {
        return await _hubcloud(url, cancel);
      }
      if (lower.contains('gdflix') || lower.contains('gdlink')) return await _gdflix(url, cancel);
      if (lower.contains('fastdlserver')) {
        final target = await web.location(url, cancel: cancel);
        return target == null ? const [] : await _resolve(target, cancel: cancel, depth: depth + 1);
      }
      if (lower.contains('driveleech') || lower.contains('driveseed')) {
        return await _driveleech(url, cancel);
      }
      if (lower.contains('?sid=')) {
        final target = await _gate(url, cancel);
        return target == null ? const [] : await _resolve(target, cancel: cancel, depth: depth + 1);
      }
      if (lower.contains('m4ulinks') || lower.contains('filescab') || lower.contains('linksmod')) {
        return await _linkPage(url, cancel, depth, 'a');
      }
      if (lower.contains('molop') || lower.contains('/watch?v=')) {
        return await _molop(url, referer, cancel);
      }
      return await _packedEmbed(url, referer, cancel);
    } on Object catch (error) {
      debugPrint('host resolve failed for ${originOf(url)}: ${error.runtimeType}');
      return const [];
    }
  }

  static bool _isDirectFile(String lower) {
    final path = lower.split('?').first;
    return path.endsWith('.mkv') ||
        path.endsWith('.mp4') ||
        path.endsWith('.m3u8') ||
        path.endsWith('.webm') ||
        lower.contains('.r2.dev/') ||
        lower.contains('r2.cloudflarestorage.com') ||
        lower.contains('googleusercontent.com');
  }

  HostFile _pixeldrain(String url) {
    final origin = originOf(url);
    final id = url.split('?').first.split('/').last;
    final direct = url.contains('/api/file/') ? url : '$origin/api/file/$id?download';
    return HostFile(url: direct, server: 'Pixeldrain');
  }

  Future<String?> _decodeRedirect(String url, CancelToken? cancel) async {
    final page = await web.get(url, cancel: cancel);
    final parts = RegExp(r"s\('o','([A-Za-z0-9+/=]+)'|ck\('_wp_http_\d+','([^']+)'")
        .allMatches(page.body)
        .map((m) => m.group(1) ?? m.group(2) ?? '')
        .join();
    if (parts.isEmpty) return null;

    final decoded = jsonDecode(_b64(_rot13(_b64(_b64(parts)))));
    if (decoded is! Map) return null;

    final o = '${decoded['o'] ?? ''}';
    if (o.isNotEmpty) return _b64(o).trim();

    final blog = '${decoded['blog_url'] ?? ''}';
    final data = '${decoded['data'] ?? ''}';
    if (blog.isEmpty || data.isEmpty) return null;
    final next = await web.get('$blog?re=${base64.encode(utf8.encode(data))}', cancel: cancel);
    final text = cleanText(next.document.body?.text ?? '');
    return text.startsWith('http') ? text : null;
  }

  Future<List<HostFile>> _hubcdn(String url, CancelToken? cancel, int depth) async {
    final page = await web.get(url, cancel: cancel);
    final reurl = RegExp(r'reurl\s*=\s*"([^"]+)"').firstMatch(page.body)?.group(1);
    if (reurl != null) {
      final encoded = Uri.parse(reurl).queryParameters['r'];
      if (encoded != null) {
        final inner = _b64(encoded);
        final link = Uri.tryParse(inner)?.queryParameters['link'] ?? inner;
        if (link.startsWith('http')) {
          return _resolve(link, cancel: cancel, depth: depth + 1);
        }
      }
    }
    final target = await _decodeRedirect(url, cancel);
    return target == null ? const [] : _resolve(target, cancel: cancel, depth: depth + 1);
  }

  static bool _isHostLink(String href) {
    final lower = href.toLowerCase();
    return lower.contains('hubcloud') ||
        lower.contains('vcloud') ||
        lower.contains('hubdrive') ||
        lower.contains('gdflix') ||
        lower.contains('gdlink') ||
        lower.contains('pixeldrain') ||
        lower.contains('fastdlserver') ||
        lower.contains('hubcdn');
  }

  Future<List<HostFile>> _linkPage(
    String url,
    CancelToken? cancel,
    int depth,
    String selector,
  ) async {
    final page = await web.get(url, cancel: cancel);
    final links = <String>[];
    for (final anchor in page.document.querySelectorAll(selector)) {
      final href = anchor.attributes['href'];
      if (href == null || !href.startsWith('http') || !_isHostLink(href)) continue;
      if (!links.contains(href)) links.add(href);
    }
    links.sort(
      (a, b) => (a.contains('hubcloud') ? 0 : 1).compareTo(b.contains('hubcloud') ? 0 : 1),
    );
    final results = <HostFile>[];
    for (final link in links.take(3)) {
      results.addAll(await _resolve(link, cancel: cancel, depth: depth + 1));
      if (results.isNotEmpty) break;
    }
    return results;
  }

  Future<List<HostFile>> _hubdrive(String url, CancelToken? cancel, int depth) async {
    final page = await web.get(url, cancel: cancel);
    final button = page.document.querySelector('.btn.btn-primary.btn-user.btn-success1.m-1');
    var href = button?.attributes['href'];
    href ??= RegExp(r'href="(https?://[^"]*(?:hubcloud|vcloud)[^"]*)"')
        .firstMatch(page.body)
        ?.group(1);
    if (href == null) return const [];
    return _resolve(href, cancel: cancel, depth: depth + 1);
  }

  String _latest(String url, String key) {
    final latest = SiteDomains.of(key);
    final origin = originOf(url);
    if (latest.isEmpty || origin == latest) return url;
    final host = Uri.tryParse(origin)?.host ?? '';
    if (!host.contains(key)) return url;
    return url.replaceFirst(origin, latest);
  }

  Future<List<HostFile>> _hubcloud(String url, CancelToken? cancel) async {
    final key = url.contains('vcloud') ? 'vcloud' : 'hubcloud';
    var target = _latest(url, key);
    WebPage page;
    try {
      page = await web.get(target, cancel: cancel);
    } on Object {
      target = url;
      page = await web.get(target, cancel: cancel);
    }
    final origin = page.origin;

    String link;
    if (target.contains('/video/')) {
      link = page.document.querySelector('div.vd > center > a')?.attributes['href'] ?? '';
    } else {
      final doubleAtob = RegExp(r'''var\s+url\s*=\s*atob\s*\(\s*atob\s*\(\s*['"]([^'"]+)['"]''')
          .firstMatch(page.body);
      if (doubleAtob != null) {
        link = _b64(_b64(doubleAtob.group(1)!));
      } else {
        link = RegExp(r"var url = '([^']*)'").firstMatch(page.body)?.group(1) ?? '';
      }
    }
    if (link.isEmpty) return const [];
    if (!link.startsWith('http')) link = origin + link;

    final files = await web.get(link, referer: target, cancel: cancel);
    final document = files.document;
    final name = cleanText(document.querySelector('div.card-header')?.text ?? '');
    final size = cleanText(document.querySelector('i#size')?.text ?? '');
    final pxl = RegExp(r'''var\s+pxl\s*=\s*["']([^"']+)["']''').firstMatch(files.body)?.group(1);

    final results = <HostFile>[];
    HostFile file(String href, String server) =>
        HostFile(url: href, server: server, name: name.isEmpty ? null : name, size: size);

    for (final anchor in document.querySelectorAll('h2 a.btn, a.btn')) {
      final href = anchor.attributes['href'] ?? '';
      final text = cleanText(anchor.text);
      if (!href.startsWith('http')) continue;
      if (text.contains('FSLv2')) {
        results.add(file(href, 'FSLv2'));
      } else if (text.contains('FSL')) {
        results.add(file(href, 'FSL'));
      } else if (text.contains('Download File')) {
        results.add(file(href, 'Download'));
      } else if (href.contains('pixeldra')) {
        final source = pxl ?? href;
        results.add(file(_pixeldrain(source).url, 'Pixeldrain'));
      } else if (text.contains('10Gbps')) {
        try {
          var redirect = await web.location(href, cancel: cancel);
          if (redirect != null && redirect.contains('link=')) {
            redirect = Uri.decodeFull(redirect.split('link=').last);
          }
          if (redirect != null && redirect.startsWith('http')) {
            results.add(file(redirect, '10Gbps'));
          }
        } on Object {
          continue;
        }
      }
    }
    return results;
  }

  Future<List<HostFile>> _gdflix(String url, CancelToken? cancel) async {
    final target = _latest(url, 'gdflix');
    final page = await web.get(target, cancel: cancel);
    final origin = page.origin;
    final document = page.document;
    final name = _listValue(document, 'Name');
    final size = _listValue(document, 'Size');

    HostFile file(String href, String server) =>
        HostFile(url: href, server: server, name: name, size: size);

    final results = <HostFile>[];
    for (final anchor in document.querySelectorAll('div.text-center a')) {
      final href = anchor.attributes['href'] ?? '';
      final text = cleanText(anchor.text);
      if (href.isEmpty) continue;
      try {
        if (text.contains('FSL V2')) {
          results.add(file(href, 'FSLv2'));
        } else if (text.contains('DIRECT DL') || text.contains('DIRECT SERVER')) {
          results.add(file(href, 'Direct'));
        } else if (text.contains('CLOUD DOWNLOAD')) {
          results.add(file(href, 'Cloud'));
        } else if (href.contains('pixeldra')) {
          results.add(file(_pixeldrain(href).url, 'Pixeldrain'));
        } else if (text.contains('Instant DL')) {
          final location = await web.location(href, cancel: cancel);
          final direct = location?.split('url=').last;
          if (direct != null && direct.startsWith('http')) results.add(file(direct, 'Instant'));
        } else if (text.contains('FAST CLOUD')) {
          final sub = await web.get(absoluteUrl(href, origin), cancel: cancel);
          final direct = sub.document.querySelector('div.card-body a')?.attributes['href'];
          if (direct != null && direct.startsWith('http')) results.add(file(direct, 'Cloud'));
        }
      } on Object {
        continue;
      }
    }
    return results;
  }

  static String? _listValue(Document document, String label) {
    for (final item in document.querySelectorAll('ul > li.list-group-item')) {
      final text = cleanText(item.text);
      if (text.startsWith(label)) {
        final value = text.split(':').skip(1).join(':').trim();
        return value.isEmpty ? null : value;
      }
    }
    return null;
  }

  Future<List<HostFile>> _driveleech(String url, CancelToken? cancel) async {
    var page = await web.get(url, cancel: cancel);
    final origin = page.origin;
    final replace = RegExp(r'replace\("([^"]+)"\)').firstMatch(page.body)?.group(1);
    if (replace != null && !page.url.contains('/file/')) {
      page = await web.get(absoluteUrl(replace, origin), cancel: cancel);
    }
    final document = page.document;
    final name = _listValue(document, 'Name');
    final size = _listValue(document, 'Size');

    HostFile file(String href, String server) =>
        HostFile(url: href, server: server, name: name, size: size);

    final results = <HostFile>[];
    for (final anchor in document.querySelectorAll('div.text-center > a, a.btn')) {
      final href = anchor.attributes['href'] ?? '';
      final text = cleanText(anchor.text);
      if (href.isEmpty) continue;
      try {
        if (text.contains('Instant Download')) {
          final location = await web.location(absoluteUrl(href, origin), cancel: cancel);
          final direct = location == null
              ? null
              : (location.contains('url=')
                    ? Uri.decodeFull(location.split('url=').last)
                    : location);
          if (direct != null && direct.startsWith('http')) results.add(file(direct, 'Instant'));
        } else if (text.contains('Resume Cloud')) {
          final sub = await web.get(absoluteUrl(href, origin), cancel: cancel);
          final direct = sub.document.querySelector('a.btn-success')?.attributes['href'];
          if (direct != null && direct.startsWith('http')) results.add(file(direct, 'ResumeCloud'));
        } else if (text.contains('Cloud Download')) {
          results.add(file(absoluteUrl(href, origin), 'Cloud'));
        } else if (text.contains('Direct Links')) {
          for (final type in const ['1', '2']) {
            final sub = await web.get('${absoluteUrl(href, origin)}?type=$type', cancel: cancel);
            for (final a in sub.document.querySelectorAll('a.btn-success')) {
              final direct = a.attributes['href'];
              if (direct != null && direct.startsWith('http')) results.add(file(direct, 'Direct'));
            }
          }
        }
      } on Object {
        continue;
      }
    }
    return results;
  }

  Future<String?> _gate(String url, CancelToken? cancel) async {
    final host = originOf(url);
    var page = await web.get(url, cancel: cancel);
    var current = page.url;
    var fields = <String, String>{};

    for (var hop = 0; hop < 8; hop++) {
      final body = page.body;
      final oldToken = RegExp(r'''\?go=([^"'&<>\s]+)''').firstMatch(body)?.group(1);
      if (oldToken != null) {
        final cookie = fields.entries
            .firstWhere((e) => e.key.endsWith('http2'), orElse: () => const MapEntry('', ''))
            .value;
        final next = await web.get(
          '$host?go=$oldToken',
          referer: current,
          cookies: {oldToken: cookie},
          cancel: cancel,
        );
        return _refreshTarget(next.body);
      }

      final lpToken = RegExp(r'lp_go=([A-Za-z0-9-]+)').firstMatch(body)?.group(1);
      final lpCookie = RegExp(r'sc\("([^"]+)","([^"]+)"').firstMatch(body);
      if (lpToken != null && lpCookie != null) {
        final next = await web.get(
          '$host/?lp_go=$lpToken',
          referer: current,
          cookies: {lpCookie.group(1)!: lpCookie.group(2)!.replaceAll(r'\/', '/')},
          cancel: cancel,
        );
        final target = _refreshTarget(next.body);
        if (target == null || target.contains('/4k-movies') || !_looksLikeDrive(target)) {
          return null;
        }
        return target;
      }

      Element? form;
      for (final candidate in page.document.querySelectorAll('form')) {
        final method = (candidate.attributes['method'] ?? '').toLowerCase();
        final id = candidate.attributes['id'] ?? '';
        if (method == 'post' && (id == 'landing' || id.startsWith('lp-'))) form = candidate;
      }
      final action = form?.attributes['action'];
      if (form == null || action == null) return null;

      fields = {
        for (final input in form.querySelectorAll('input'))
          if (input.attributes['name'] != null)
            input.attributes['name']!: input.attributes['value'] ?? '',
      };
      page = await web.post(absoluteUrl(action, current), fields, referer: current, cancel: cancel);
      current = page.url;
    }
    return null;
  }

  static bool _looksLikeDrive(String url) =>
      url.contains('driveleech') || url.contains('driveseed') || url.contains('/r?key=');

  static String? _refreshTarget(String body) {
    final meta = RegExp(
      r'''http-equiv=["']?refresh["']?[^>]*url=([^"'>]+)''',
      caseSensitive: false,
    ).firstMatch(body)?.group(1);
    if (meta != null) return meta.trim();
    final replace = RegExp(r'location\.replace\("([^"]+)"\)').firstMatch(body)?.group(1);
    return replace?.replaceAll(r'\/', '/');
  }

  Future<List<HostFile>> _molop(String url, String? referer, CancelToken? cancel) async {
    final page = await web.get(url, referer: referer, cancel: cancel);
    final sniff = RegExp(r'sniff\("([^"]+)","([^"]+)","([^"]+)"').firstMatch(page.body);
    if (sniff == null) return const [];
    final origin = page.origin;
    return [
      HostFile(
        url: '$origin/m3u8/${sniff.group(2)}/${sniff.group(3)}/master.m3u8',
        server: 'HLS',
        isHls: true,
        headers: {'Referer': '$origin/', 'Origin': origin, 'User-Agent': webUserAgent},
      ),
    ];
  }

  Future<List<HostFile>> _packedEmbed(String url, String? referer, CancelToken? cancel) async {
    final page = await web.get(url, referer: referer, cancel: cancel);
    var body = page.body;
    final packed = RegExp(
      r'eval\(function\(p,a,c,k,e,d\).*?\.split\(.\|.\)[^)]*\)\)',
      dotAll: true,
    ).firstMatch(body);
    if (packed != null) body = unpackJs(packed.group(0)!) ?? body;

    final hls =
        RegExp(r'''["'](https?://[^"']+\.m3u8[^"']*)["']''').firstMatch(body)?.group(1) ??
        RegExp(r'''file\s*:\s*["']([^"']+\.m3u8[^"']*)["']''').firstMatch(body)?.group(1);
    if (hls == null) return const [];
    final origin = page.origin;
    return [
      HostFile(
        url: absoluteUrl(hls, page.url),
        server: 'HLS',
        isHls: true,
        headers: {'Referer': '$origin/', 'Origin': origin, 'User-Agent': webUserAgent},
      ),
    ];
  }
}
