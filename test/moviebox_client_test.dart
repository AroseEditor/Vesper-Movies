import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_movies/core/errors.dart';
import 'package:vesper_movies/core/log.dart';
import 'package:vesper_movies/sources/moviebox/client.dart';
import 'package:vesper_movies/sources/moviebox/session.dart';

class _FakeReply {
  const _FakeReply(this.status, this.body, {this.headers = const {}});

  final int status;
  final String body;
  final Map<String, List<String>> headers;
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.handler);

  final _FakeReply Function(RequestOptions options, int callIndex) handler;
  final List<RequestOptions> calls = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final index = calls.length;
    calls.add(options);
    final reply = handler(options, index);
    return ResponseBody.fromString(
      reply.body,
      reply.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        ...reply.headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

MovieBoxClient _client(_RecordingAdapter adapter, {SessionStore? store}) {
  final dio = Dio(BaseOptions(responseType: ResponseType.plain, validateStatus: (_) => true))
    ..httpClientAdapter = adapter;
  return MovieBoxClient(dio: dio, store: store ?? InMemorySessionStore());
}

String _loginBody() => jsonEncode({
  'data': {'token': 'header.eyJ1c2VySWQiOiI5OSIsImV4cCI6NDEwMjQ0NDgwMH0.sig', 'uid': '99'},
});

void main() {
  group('session', () {
    test('reads user and expiry out of the jwt payload', () {
      final payload = base64Url
          .encode(utf8.encode('{"userId":"123456789","exp":1893456000}'))
          .replaceAll('=', '');
      final claims = parseJwtClaims('header.$payload.signature');

      expect(claims.userId, '123456789');
      expect(claims.expiresAt, 1893456000);
    });

    test('treats an expired or empty token as invalid', () {
      expect(MovieBoxSession.fromToken('a.b.c', now: 1000).isValid(now: 1000), isTrue);
      expect(
        const MovieBoxSession(token: 'x', createdAt: 0, expiresAt: 100).isValid(now: 500),
        isFalse,
      );
      expect(const MovieBoxSession(token: '  ', createdAt: 0).isValid(), isFalse);
    });

    test('falls back to a seven day life when the token carries no expiry', () {
      const session = MovieBoxSession(token: 'x', createdAt: 0);
      expect(session.isValid(now: 6 * 24 * 3600), isTrue);
      expect(session.isValid(now: 8 * 24 * 3600), isFalse);
    });

    test('survives a round trip through json', () {
      final original = MovieBoxSession.fromToken('a.b.c', userId: '7', now: 42);
      final restored = MovieBoxSession.fromJson(original.toJson());

      expect(restored.token, original.token);
      expect(restored.userId, '7');
      expect(restored.createdAt, 42);
    });
  });

  group('client', () {
    test('logs in once and reuses the session for later calls', () async {
      final adapter = _RecordingAdapter((options, index) {
        if (options.path.contains('visitor-login')) {
          return _FakeReply(200, _loginBody());
        }
        return _FakeReply(
          200,
          jsonEncode({
            'data': {'title': 'ok'},
          }),
        );
      });

      final client = _client(adapter);
      await client.get('/first');
      await client.get('/second');

      final logins = adapter.calls.where((c) => c.path.contains('visitor-login')).length;
      expect(logins, 1);
    });

    test('unwraps the data envelope', () async {
      final adapter = _RecordingAdapter((options, index) {
        if (options.path.contains('visitor-login')) return _FakeReply(200, _loginBody());
        return _FakeReply(
          200,
          jsonEncode({
            'data': {'title': 'Dune'},
          }),
        );
      });

      final result = await _client(adapter).get('/subject');
      expect(result['title'], 'Dune');
    });

    test('rotates to the next host on a retryable status and pins the winner', () async {
      final adapter = _RecordingAdapter((options, index) {
        if (options.path.contains('visitor-login')) return _FakeReply(200, _loginBody());
        if (options.uri.host == 'api6.aoneroom.com') return const _FakeReply(503, '');
        if (options.uri.host == 'api5.aoneroom.com') return const _FakeReply(502, '');
        return _FakeReply(
          200,
          jsonEncode({
            'data': {'title': 'third'},
          }),
        );
      });

      final client = _client(adapter);
      final result = await client.get('/subject');

      expect(result['title'], 'third');
      expect(client.hostIndex, 2);
    });

    test('gives up with the last error once every host is exhausted', () async {
      final adapter = _RecordingAdapter((options, index) {
        if (options.path.contains('visitor-login')) return _FakeReply(200, _loginBody());
        return const _FakeReply(503, '');
      });

      await expectLater(
        _client(adapter).get('/subject'),
        throwsA(isA<Unavailable>().having((e) => e.status, 'status', 503)),
      );
    });

    test('adopts a replacement session handed back in the x-user header', () async {
      final replacement =
          'header.${base64Url.encode(utf8.encode('{"userId":"777","exp":4102444800}')).replaceAll('=', '')}.sig';

      final adapter = _RecordingAdapter((options, index) {
        if (options.path.contains('visitor-login')) return _FakeReply(200, _loginBody());
        return _FakeReply(
          200,
          jsonEncode({
            'data': {'ok': true},
          }),
          headers: {
            'x-user': [
              jsonEncode({'token': replacement, 'uid': '777'}),
            ],
          },
        );
      });

      final store = InMemorySessionStore();
      await _client(adapter, store: store).get('/subject');

      final saved = await store.read();
      expect(saved?.token, replacement);
      expect(saved?.userId, '777');
    });

    test('signs every attempt for the host it is actually sent to', () async {
      final adapter = _RecordingAdapter((options, index) {
        if (options.path.contains('visitor-login')) return _FakeReply(200, _loginBody());
        if (options.uri.host == 'api6.aoneroom.com') return const _FakeReply(503, '');
        return _FakeReply(
          200,
          jsonEncode({
            'data': {'ok': true},
          }),
        );
      });

      final client = _client(adapter);
      await client.get('/subject');

      final attempts = adapter.calls.where((c) => c.path.contains('/subject')).toList();
      expect(attempts.length, greaterThanOrEqualTo(2));
      expect(
        attempts.first.headers['x-tr-signature'],
        isNot(attempts.last.headers['x-tr-signature']),
      );
    });

    test('sends the spoofed forwarded-for and client info on every request', () async {
      final adapter = _RecordingAdapter((options, index) {
        if (options.path.contains('visitor-login')) return _FakeReply(200, _loginBody());
        return _FakeReply(
          200,
          jsonEncode({
            'data': {'ok': true},
          }),
        );
      });

      final client = _client(adapter);
      await client.get('/subject');

      for (final call in adapter.calls) {
        expect(call.headers['x-forwarded-for'], client.identity.forwardedFor);
        expect(call.headers['x-client-info'], client.identity.clientInfo);
      }
    });
  });

  group('log redaction', () {
    test('strips any url out of a thrown cause before it reaches a log', () {
      const raw =
          'DioException: connection failed for url (https://api6.aoneroom.com/search?q=secret)';
      final described = describeCause(raw);

      expect(described, contains('https://api6.aoneroom.com'));
      expect(described, isNot(contains('secret')));
      expect(described, isNot(contains('/search')));
    });
  });
}
