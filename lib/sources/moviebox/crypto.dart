import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

const List<int> _secretKey = [
  0xef,
  0xa8,
  0x91,
  0x97,
  0x4e,
  0xec,
  0xd3,
  0x14,
  0x8d,
  0xf6,
  0x3a,
  0xa6,
  0x11,
  0x60,
  0x2d,
  0xef,
  0xd1,
  0x01,
  0x25,
  0x9b,
  0xa5,
  0x21,
  0x02,
  0x2c,
  0x57,
  0xae,
  0x05,
  0x66,
  0xbd,
  0x8e,
];

const int _signatureBodyMaxBytes = 102400;

const String packageName = 'com.community.oneroom';
const String versionName = '4.0.01.0813.03';
const String streamReferer = 'https://sportslive.wine';

String md5Hex(List<int> data) => md5.convert(data).toString();

String generateClientToken(int timestampMs) {
  final text = timestampMs.toString();
  final reversed = String.fromCharCodes(text.codeUnits.reversed);
  return '$text,${md5Hex(utf8.encode(reversed))}';
}

String sortedQueryString(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return '';

  final query = uri.query;
  if (query.isEmpty) return '';

  final grouped = <String, List<String>>{};
  for (final pair in query.split('&')) {
    if (pair.isEmpty) continue;
    final index = pair.indexOf('=');
    final rawKey = index < 0 ? pair : pair.substring(0, index);
    final rawValue = index < 0 ? '' : pair.substring(index + 1);
    final key = Uri.decodeQueryComponent(rawKey);
    final value = Uri.decodeQueryComponent(rawValue);
    grouped.putIfAbsent(key, () => <String>[]).add(value);
  }

  if (grouped.isEmpty) return '';

  final keys = grouped.keys.toList()..sort();
  final parts = <String>[];
  for (final key in keys) {
    for (final value in grouped[key]!) {
      parts.add('$key=$value');
    }
  }
  return parts.join('&');
}

String buildCanonicalString({
  required String method,
  required String url,
  required int timestampMs,
  String? accept,
  String? contentType,
  String? body,
}) {
  final uri = Uri.tryParse(url);
  final String canonicalUrl;
  if (uri == null) {
    canonicalUrl = url;
  } else {
    final query = sortedQueryString(url);
    canonicalUrl = query.isEmpty ? uri.path : '${uri.path}?$query';
  }

  var bodyHash = '';
  var bodyLength = '';
  if (body != null) {
    final bytes = utf8.encode(body);
    bodyLength = bytes.length.toString();
    final truncated = bytes.length > _signatureBodyMaxBytes
        ? bytes.sublist(0, _signatureBodyMaxBytes)
        : bytes;
    bodyHash = md5Hex(truncated);
  }

  return [
    method.toUpperCase(),
    accept ?? '',
    contentType ?? '',
    bodyLength,
    timestampMs.toString(),
    bodyHash,
    canonicalUrl,
  ].join('\n');
}

String generateSignature({
  required String method,
  required String url,
  required int timestampMs,
  String? accept,
  String? contentType,
  String? body,
}) {
  final canonical = buildCanonicalString(
    method: method,
    url: url,
    timestampMs: timestampMs,
    accept: accept,
    contentType: contentType,
    body: body,
  );
  final digest = Hmac(md5, _secretKey).convert(utf8.encode(canonical));
  return '$timestampMs|2|${base64.encode(digest.bytes)}';
}

class DeviceIdentity {
  const DeviceIdentity({
    required this.userAgent,
    required this.clientInfo,
    required this.forwardedFor,
  });

  final String userAgent;
  final String clientInfo;
  final String forwardedFor;

  static const _androidBuilds = [
    ['9', 'PQ3A.190605.03081104'],
    ['10', 'QKQ1.191014.012'],
    ['11', 'RKQ1.200826.002'],
    ['12', 'SKQ1.211006.001'],
    ['13', 'TQ2A.230405.003'],
  ];

  static const _models = [
    'Redmi Note 8 Pro',
    'Redmi Note 9 Pro',
    'Redmi Note 10',
    'Redmi Note 11',
    'Redmi 9A',
    'Redmi K20',
    'Redmi Note 12',
  ];

  static const _timezones = [
    'Asia/Kolkata',
    'Asia/Dhaka',
    'Asia/Karachi',
    'Asia/Jakarta',
    'Asia/Manila',
  ];

  static const _ipPrefixes = [
    '103.241',
    '49.36',
    '117.195',
    '106.198',
    '122.162',
    '157.32',
    '182.70',
    '103.58',
    '27.60',
    '59.90',
  ];

  static DeviceIdentity generate([Random? source]) {
    final random = source ?? Random.secure();

    final build = _androidBuilds[random.nextInt(_androidBuilds.length)];
    final model = _models[random.nextInt(_models.length)];
    final versionCode = 50020117 + random.nextInt(5);
    final network = random.nextBool() ? 'NETWORK_WIFI' : 'NETWORK_MOBILE';
    final timezone = _timezones[random.nextInt(_timezones.length)];

    final userAgent =
        '$packageName/$versionCode (Linux; U; Android ${build[0]}; en_US; '
        '$model; Build/${build[1]}; Cronet/135.0.7012.3)';

    final clientInfo = jsonEncode({
      'package_name': packageName,
      'version_name': versionName,
      'version_code': versionCode,
      'os': 'Android',
      'os_version': build[0],
      'device_id': _randomHex(random, 32),
      'gaid': _randomUuid(random),
      'brand': 'Redmi',
      'model': model,
      'net': network,
      'timezone': timezone,
      'install_ch': 'googleplay',
      'install_store': 'googleplay',
      'region': 'US',
      'sp_code': '40401',
      'X-Play-Mode': '2',
    });

    final prefix = _ipPrefixes[random.nextInt(_ipPrefixes.length)];
    final forwardedFor = '$prefix.${1 + random.nextInt(253)}.${1 + random.nextInt(253)}';

    return DeviceIdentity(userAgent: userAgent, clientInfo: clientInfo, forwardedFor: forwardedFor);
  }

  static String _randomHex(Random random, int length) {
    const alphabet = '0123456789abcdef';
    return List.generate(length, (_) => alphabet[random.nextInt(16)]).join();
  }

  static String _randomUuid(Random random) {
    String block(int n) => _randomHex(random, n);
    return '${block(8)}-${block(4)}-${block(4)}-${block(4)}-${block(12)}';
  }
}

Map<String, String> buildSignedHeaders({
  required String method,
  required String url,
  required DeviceIdentity identity,
  String? body,
  String? authToken,
  int? timestampMs,
}) {
  final ts = timestampMs ?? DateTime.now().millisecondsSinceEpoch;
  const accept = 'application/json';
  const contentType = 'application/json';

  final headers = <String, String>{
    'User-Agent': identity.userAgent,
    'Accept': accept,
    'Content-Type': contentType,
    'Connection': 'keep-alive',
    'x-client-token': generateClientToken(ts),
    'x-tr-signature': generateSignature(
      method: method,
      url: url,
      timestampMs: ts,
      accept: accept,
      contentType: contentType,
      body: body,
    ),
    'x-client-info': identity.clientInfo,
    'x-client-status': '0',
    'x-forwarded-for': identity.forwardedFor,
  };

  if (authToken != null && authToken.isNotEmpty) {
    headers['Authorization'] = 'Bearer $authToken';
  }

  return headers;
}
