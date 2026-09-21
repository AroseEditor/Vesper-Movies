import 'dart:convert';

class MovieBoxSession {
  const MovieBoxSession({
    required this.token,
    required this.createdAt,
    this.userId,
    this.expiresAt,
  });

  final String token;
  final int createdAt;
  final String? userId;
  final int? expiresAt;

  static const _fallbackLifetimeSeconds = 7 * 24 * 3600;
  static const _clockSkewSeconds = 60;

  factory MovieBoxSession.fromToken(String token, {String? userId, int? now}) {
    final claims = parseJwtClaims(token);
    return MovieBoxSession(
      token: token,
      createdAt: now ?? _nowSeconds(),
      userId: userId ?? claims.userId,
      expiresAt: claims.expiresAt,
    );
  }

  factory MovieBoxSession.fromJson(Map<String, dynamic> json) {
    return MovieBoxSession(
      token: json['token'] as String? ?? '',
      createdAt: json['createdAt'] as int? ?? 0,
      userId: json['userId'] as String?,
      expiresAt: json['expiresAt'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'token': token,
    'createdAt': createdAt,
    'userId': userId,
    'expiresAt': expiresAt,
  };

  bool isValid({int? now}) {
    if (token.trim().isEmpty) return false;
    final current = now ?? _nowSeconds();
    final expiry = expiresAt;
    if (expiry != null) {
      return current + _clockSkewSeconds < expiry;
    }
    return current < createdAt + _fallbackLifetimeSeconds;
  }

  static int _nowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}

class JwtClaims {
  const JwtClaims({this.userId, this.expiresAt});

  final String? userId;
  final int? expiresAt;
}

JwtClaims parseJwtClaims(String token) {
  final parts = token.split('.');
  if (parts.length < 2) return const JwtClaims();

  final payload = _decodeSegment(parts[1]);
  if (payload == null) return const JwtClaims();

  Map<String, dynamic> claims;
  try {
    final decoded = jsonDecode(payload);
    if (decoded is! Map<String, dynamic>) return const JwtClaims();
    claims = decoded;
  } on FormatException {
    return const JwtClaims();
  }

  final rawUser = claims['userId'] ?? claims['uid'] ?? claims['sub'];
  final rawExpiry = claims['exp'];

  return JwtClaims(userId: _asString(rawUser), expiresAt: _asInt(rawExpiry));
}

String? _decodeSegment(String segment) {
  final padded = segment.padRight(segment.length + ((4 - segment.length % 4) % 4), '=');
  final decoders = <List<int> Function(String)>[base64Url.decode, base64.decode];

  for (final candidate in [segment, padded]) {
    for (final decode in decoders) {
      try {
        return utf8.decode(decode(candidate));
      } on Object catch (_) {
        continue;
      }
    }
  }
  return null;
}

String? _asString(Object? value) {
  if (value == null) return null;
  if (value is String) return value.isEmpty ? null : value;
  if (value is num) return value.toInt().toString();
  return null;
}

int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
