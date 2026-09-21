import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/errors.dart';
import '../../core/log.dart';
import 'crypto.dart';
import 'session.dart';

const List<String> movieBoxHosts = [
  'https://api6.aoneroom.com',
  'https://api5.aoneroom.com',
  'https://api4.aoneroom.com',
  'https://api4sg.aoneroom.com',
  'https://api3.aoneroom.com',
  'https://api6sg.aoneroom.com',
  'https://api.inmoviebox.com',
];

const Set<int> retryableStatuses = {403, 406, 407, 429, 500, 502, 503, 504};

abstract interface class SessionStore {
  Future<MovieBoxSession?> read();

  Future<void> write(MovieBoxSession session);

  Future<void> clear();
}

class InMemorySessionStore implements SessionStore {
  MovieBoxSession? _session;

  @override
  Future<MovieBoxSession?> read() async => _session;

  @override
  Future<void> write(MovieBoxSession session) async => _session = session;

  @override
  Future<void> clear() async => _session = null;
}

class MovieBoxClient {
  MovieBoxClient({Dio? dio, SessionStore? store, DeviceIdentity? identity})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 20),
              sendTimeout: const Duration(seconds: 20),
              responseType: ResponseType.plain,
              validateStatus: (_) => true,
            ),
          ),
      _store = store ?? InMemorySessionStore(),
      identity = identity ?? DeviceIdentity.generate();

  final Dio _dio;
  final SessionStore _store;
  final DeviceIdentity identity;

  int _hostIndex = 0;
  MovieBoxSession? _session;
  Future<String>? _pendingSession;

  int get hostIndex => _hostIndex;

  Future<String> ensureSession() {
    final current = _session;
    if (current != null && current.isValid()) {
      return Future.value(current.token);
    }
    return _pendingSession ??= _openSession().whenComplete(
      () => _pendingSession = null,
    );
  }

  Future<String> _openSession() async {
    final stored = await _store.read();
    if (stored != null && stored.isValid()) {
      _session = stored;
      return stored.token;
    }

    final payload = await _send(
      method: 'POST',
      path: '/wefeed-mobile-bff/user-api/visitor-login',
      body: '{}',
      authToken: null,
    );

    final token = _readString(payload, const ['token']);
    if (token == null || token.trim().isEmpty) {
      throw const Unavailable();
    }

    final session = MovieBoxSession.fromToken(
      token,
      userId: _readString(payload, const ['uid', 'userId']),
    );
    _session = session;
    await _store.write(session);
    return token;
  }

  Future<void> invalidateSession() async {
    _session = null;
    await _store.clear();
  }

  Future<Map<String, dynamic>> get(String path, {CancelToken? cancel}) =>
      _request(method: 'GET', path: path, cancel: cancel);

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    CancelToken? cancel,
  }) => _request(
    method: 'POST',
    path: path,
    body: jsonEncode(body),
    cancel: cancel,
  );

  Future<Map<String, dynamic>> _request({
    required String method,
    required String path,
    String? body,
    CancelToken? cancel,
  }) async {
    final token = await ensureSession();
    try {
      return await _send(
        method: method,
        path: path,
        body: body,
        authToken: token,
        cancel: cancel,
      );
    } on SourceError catch (error) {
      final retryable =
          (error is Unavailable &&
              (error.status == 401 || error.status == 403)) ||
          (error is Unavailable && error.status == null);
      if (!retryable) rethrow;

      await invalidateSession();
      final fresh = await ensureSession();
      return _send(
        method: method,
        path: path,
        body: body,
        authToken: fresh,
        cancel: cancel,
      );
    }
  }

  Future<Map<String, dynamic>> _send({
    required String method,
    required String path,
    String? body,
    String? authToken,
    CancelToken? cancel,
  }) async {
    final start = _hostIndex;
    var backoffMs = 50;
    SourceError? last;

    for (var attempt = 0; attempt < movieBoxHosts.length; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(milliseconds: backoffMs));
        backoffMs = 50;
      }

      final index = (start + attempt) % movieBoxHosts.length;
      final url = '${movieBoxHosts[index]}$path';
      final headers = buildSignedHeaders(
        method: method,
        url: url,
        identity: identity,
        body: body,
        authToken: authToken,
      );

      Response<dynamic> response;
      try {
        response = await _dio.request<dynamic>(
          url,
          data: body,
          cancelToken: cancel,
          options: Options(method: method, headers: headers),
        );
      } on DioException catch (error) {
        if (CancelToken.isCancel(error)) throw const Cancelled();
        last = NetworkError(
          error.type.name,
          timedOut:
              error.type == DioExceptionType.connectionTimeout ||
              error.type == DioExceptionType.receiveTimeout ||
              error.type == DioExceptionType.sendTimeout,
        );
        log.warn('moviebox host $index unreachable', url: url);
        continue;
      }

      await _absorbUserHeader(response.headers);

      final status = response.statusCode ?? 0;
      if (retryableStatuses.contains(status)) {
        if (status == 429) {
          final retryAfter = int.tryParse(
            response.headers.value('retry-after') ?? '',
          );
          backoffMs = retryAfter == null
              ? 400
              : (retryAfter * 1000).clamp(50, 3000);
          last = RateLimited(retryAfter);
        } else {
          last = Unavailable(status);
        }
        log.warn('moviebox host $index returned $status', url: url);
        continue;
      }

      if (status < 200 || status >= 300) {
        if (status == 404) throw const NotFound();
        throw Unavailable(status);
      }

      final parsed = _parseBody(response.data);
      if (parsed == null) {
        last = const ParseError('moviebox response');
        log.warn('moviebox host $index returned unparseable json', url: url);
        continue;
      }

      _hostIndex = index;
      return parsed;
    }

    throw last ?? const Unavailable();
  }

  Map<String, dynamic>? _parseBody(Object? data) {
    Object? decoded = data;
    if (data is String) {
      if (data.trim().isEmpty) return null;
      try {
        decoded = jsonDecode(data);
      } on FormatException {
        return null;
      }
    }
    if (decoded is! Map<String, dynamic>) return null;

    final inner = decoded['data'];
    if (inner is Map<String, dynamic>) return inner;
    if (inner is List) return {'list': inner};
    return decoded;
  }

  Future<void> _absorbUserHeader(Headers headers) async {
    final raw = headers.value('x-user');
    if (raw == null || raw.isEmpty) return;

    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;

    final token = decoded['token'];
    if (token is! String || token.isEmpty) return;

    final session = MovieBoxSession.fromToken(
      token,
      userId: _readString(decoded, const ['uid', 'userId']),
    );
    _session = session;
    await _store.write(session);
  }

  String? _readString(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value is String && value.isNotEmpty) return value;
      if (value is num) return value.toInt().toString();
    }
    return null;
  }
}
