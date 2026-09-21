import 'dart:convert';

const List<String> _deprecationNoticeFiles = [
  '1c7de0bd3393702d9191801f15f88f8d',
  '9a0461bc39da389663bf3dbb17091d3f',
  'b164fbfb4347792950bdfbfb563d39d9',
];

bool isDeprecationNoticeUrl(String url) {
  final lower = url.toLowerCase();
  for (final file in _deprecationNoticeFiles) {
    if (lower.contains(file)) return true;
  }
  if (lower.contains('/notice.mp4') || lower.contains('notice')) return true;
  return lower.contains('macdn.aoneroom.com') && lower.contains('/other/');
}

Map<String, String> parseSignCookie(String raw) {
  final result = <String, String>{};
  for (final part in raw.split(RegExp(r'[;\n]'))) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    final index = trimmed.indexOf('=');
    if (index <= 0) continue;
    result[trimmed.substring(0, index).trim()] = trimmed.substring(index + 1).trim();
  }
  return result;
}

String normalizeSignCookie(String raw) {
  final parsed = parseSignCookie(raw);
  if (parsed.isEmpty) return raw.trim();
  return parsed.entries.map((e) => '${e.key}=${e.value}').join('; ');
}

String? decodeCloudFrontPolicy(String policyValue) {
  final normalized = policyValue.replaceAll('-', '+').replaceAll('_', '=').replaceAll('~', '/');
  final padded = normalized.padRight(normalized.length + ((4 - normalized.length % 4) % 4), '=');
  try {
    return utf8.decode(base64.decode(padded));
  } on Object catch (_) {
    return null;
  }
}

String? resolveDashManifestFromPolicy(String signCookie) {
  final cookie = parseSignCookie(signCookie);
  final policy = cookie['CloudFront-Policy'];
  if (policy == null || policy.isEmpty) return null;

  final decoded = decodeCloudFrontPolicy(policy);
  if (decoded == null) return null;

  Object? parsed;
  try {
    parsed = jsonDecode(decoded);
  } on FormatException {
    return null;
  }
  if (parsed is! Map<String, dynamic>) return null;

  final statements = parsed['Statement'];
  if (statements is! List || statements.isEmpty) return null;

  final first = statements.first;
  if (first is! Map<String, dynamic>) return null;

  final resource = first['Resource'];
  if (resource is! String || resource.isEmpty) return null;

  var base = resource;
  while (base.endsWith('*')) {
    base = base.substring(0, base.length - 1);
  }
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  if (base.isEmpty) return null;
  if (!base.startsWith('http://') && !base.startsWith('https://')) return null;

  return '$base/index.mpd';
}

String? resolveEdgeCacheManifest(String signCookie) {
  final cookie = parseSignCookie(signCookie);
  final value = cookie['Edge-Cache-Cookie'];
  if (value == null || value.isEmpty) return null;

  for (final part in value.split(':')) {
    final trimmed = part.trim();
    if (!trimmed.startsWith('urlprefix=')) continue;

    final encoded = trimmed.substring('urlprefix='.length);
    if (encoded.isEmpty) return null;

    final padded = encoded.padRight(encoded.length + ((4 - encoded.length % 4) % 4), '=');
    String decoded;
    try {
      decoded = utf8.decode(base64Url.decode(padded));
    } on Object catch (_) {
      return null;
    }

    var base = decoded.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (base.isEmpty) return null;
    if (!base.startsWith('http://') && !base.startsWith('https://')) return null;

    return '$base/index.mpd';
  }

  return null;
}

String? resolveSignedManifest(String signCookie) {
  return resolveDashManifestFromPolicy(signCookie) ?? resolveEdgeCacheManifest(signCookie);
}

String? resolveStreamUrl({required String? signCookie, required String? fallbackUrl}) {
  if (signCookie != null && signCookie.isNotEmpty) {
    final manifest = resolveSignedManifest(signCookie);
    if (manifest != null) return manifest;
  }
  if (fallbackUrl == null || fallbackUrl.isEmpty) return null;
  if (isDeprecationNoticeUrl(fallbackUrl)) return null;
  return fallbackUrl;
}
