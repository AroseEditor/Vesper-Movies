import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

const _dohEndpoints = [
  'https://1.1.1.1/dns-query',
  'https://8.8.8.8/resolve',
  'https://1.0.0.1/dns-query',
  'https://8.8.4.4/resolve',
];

const _maxCacheTtl = Duration(minutes: 30);
const _minCacheTtl = Duration(minutes: 2);
const _failureTtl = Duration(seconds: 45);
const _connectTimeout = Duration(seconds: 15);
const _dohBudget = Duration(milliseconds: 2500);
const _dohTimeout = Duration(seconds: 6);

class _Cached {
  _Cached(this.addresses, this.expiresAt);

  final List<InternetAddress> addresses;
  final DateTime expiresAt;
}

bool _isLiteral(String host) =>
    InternetAddress.tryParse(host) != null || host == 'localhost' || host.endsWith('.local');

class SecureDns {
  SecureDns._();

  static final SecureDns instance = SecureDns._();

  final Map<String, _Cached> _cache = {};
  final Map<String, Future<List<InternetAddress>>> _pending = {};

  HttpClient? _client;

  HttpClient get _http => _client ??= HttpClient()
    ..connectionTimeout = const Duration(seconds: 4)
    ..idleTimeout = const Duration(seconds: 30);

  Future<List<InternetAddress>> resolve(String host) {
    if (_isLiteral(host)) {
      final literal = InternetAddress.tryParse(host);
      return Future.value(literal == null ? const [] : [literal]);
    }

    final key = host.toLowerCase();
    final cached = _cache[key];
    if (cached != null && DateTime.now().isBefore(cached.expiresAt)) {
      return Future.value(cached.addresses);
    }

    return _pending[key] ??= _lookup(key).whenComplete(() {
      _pending.remove(key);
    });
  }

  Future<List<InternetAddress>> _lookup(String host) async {
    final doh = Completer<List<InternetAddress>?>();
    var remaining = _dohEndpoints.length;
    for (final endpoint in _dohEndpoints) {
      unawaited(
        _query(endpoint, host)
            .timeout(_dohTimeout)
            .then<void>((result) {
              if (result != null && !doh.isCompleted) {
                _cache[host] = _Cached(result.$1, DateTime.now().add(result.$2));
                doh.complete(result.$1);
              }
            })
            .catchError((Object _) {})
            .whenComplete(() {
              remaining--;
              if (remaining == 0 && !doh.isCompleted) doh.complete(null);
            }),
      );
    }

    final system = InternetAddress.lookup(
      host,
      type: InternetAddressType.IPv4,
    ).timeout(_dohTimeout).then<List<InternetAddress>?>((v) => v).catchError((Object _) => null);

    final fast = await doh.future.timeout(_dohBudget, onTimeout: () => null);
    if (fast != null && fast.isNotEmpty) return fast;

    final systemResult = await system;
    if (systemResult != null && systemResult.isNotEmpty) {
      if (!doh.isCompleted) {
        unawaited(doh.future.catchError((Object _) => null));
      }
      return systemResult;
    }

    final late = await doh.future;
    if (late != null && late.isNotEmpty) return late;

    _cache[host] = _Cached(const [], DateTime.now().add(_failureTtl));
    return const [];
  }

  Future<(List<InternetAddress>, Duration)?> _query(String endpoint, String host) async {
    final uri = Uri.parse(endpoint).replace(queryParameters: {'name': host, 'type': 'A'});
    final request = await _http.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');
    final response = await request.close();
    if (response.statusCode != 200) {
      await response.drain<void>();
      return null;
    }

    final body = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(body);
    if (decoded is! Map || decoded['Status'] != 0) return null;

    final answers = decoded['Answer'];
    if (answers is! List) return null;

    final addresses = <InternetAddress>[];
    var ttl = _maxCacheTtl;
    for (final answer in answers) {
      if (answer is! Map || answer['type'] != 1) continue;
      final address = InternetAddress.tryParse('${answer['data']}');
      if (address == null || address.type != InternetAddressType.IPv4) continue;
      addresses.add(address);
      final seconds = answer['TTL'];
      if (seconds is int && Duration(seconds: seconds) < ttl) ttl = Duration(seconds: seconds);
    }
    if (addresses.isEmpty) return null;
    if (ttl < _minCacheTtl) ttl = _minCacheTtl;
    return (addresses, ttl);
  }

  Future<Socket> connect(String host, int port) async {
    Object? lastError;
    for (final address in await resolve(host)) {
      try {
        return await Socket.connect(address, port, timeout: _connectTimeout);
      } on Object catch (error) {
        lastError = error;
      }
    }
    try {
      return await Socket.connect(host, port, timeout: _connectTimeout);
    } on Object catch (error) {
      throw lastError ?? error;
    }
  }
}

class SecureDnsHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      if (proxyHost != null && proxyPort != null) {
        return Socket.startConnect(proxyHost, proxyPort);
      }

      final host = uri.host;
      final secure = uri.isScheme('https');
      final port = uri.hasPort ? uri.port : (secure ? 443 : 80);

      Future<Socket> open() async {
        final raw = await SecureDns.instance.connect(host, port);
        if (!secure) return raw;
        try {
          return await SecureSocket.secure(raw, host: host, context: context);
        } on Object {
          raw.destroy();
          rethrow;
        }
      }

      return ConnectionTask.fromSocket(open(), () {});
    };
    return client;
  }
}

class StreamTunnel {
  StreamTunnel._(this.port);

  static StreamTunnel? _instance;

  final int port;

  String get proxyUrl => 'http://127.0.0.1:$port';

  static Future<StreamTunnel?> start() async {
    final existing = _instance;
    if (existing != null) return existing;

    try {
      final ready = ReceivePort();
      await Isolate.spawn(_serve, ready.sendPort, debugName: 'stream-tunnel');
      final port = await ready.first.timeout(const Duration(seconds: 5));
      ready.close();
      if (port is int && port > 0) return _instance = StreamTunnel._(port);
    } on Object {
      final port = await _bind();
      if (port != null) return _instance = StreamTunnel._(port);
    }
    return null;
  }

  static Future<void> _serve(SendPort ready) async {
    ready.send(await _bind() ?? 0);
  }

  static Future<int?> _bind() async {
    try {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen(_handle, onError: (Object _) {});
      return server.port;
    } on Object {
      return null;
    }
  }

  static StreamTunnel? get running => _instance;

  static bool routePlayback = true;

  static const _routeKey = 'net.route_playback';

  static Future<void> loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      routePlayback = prefs.getBool(_routeKey) ?? true;
    } on Object {
      routePlayback = true;
    }
  }

  static Future<void> setRoutePlayback(bool value) async {
    routePlayback = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_routeKey, value);
    } on Object {
      return;
    }
  }

  static void _handle(Socket client) {
    final buffer = BytesBuilder(copy: false);
    late final StreamSubscription<Uint8List> subscription;
    var routed = false;

    subscription = client.listen(
      (chunk) {
        if (routed) return;
        buffer.add(chunk);
        final bytes = buffer.toBytes();
        final end = _headerEnd(bytes);
        if (end < 0) {
          if (bytes.length > 16384) client.destroy();
          return;
        }
        routed = true;
        subscription.pause();
        unawaited(_route(client, subscription, bytes, end));
      },
      onError: (Object _) => client.destroy(),
      cancelOnError: true,
    );
  }

  static int _headerEnd(Uint8List bytes) {
    for (var i = 0; i + 3 < bytes.length; i++) {
      if (bytes[i] == 13 && bytes[i + 1] == 10 && bytes[i + 2] == 13 && bytes[i + 3] == 10) {
        return i + 4;
      }
    }
    return -1;
  }

  static Future<void> _route(
    Socket client,
    StreamSubscription<Uint8List> incoming,
    Uint8List head,
    int headerEnd,
  ) async {
    final header = latin1.decode(head.sublist(0, headerEnd));
    final requestLine = header.split('\r\n').first.split(' ');
    if (requestLine.length < 3) {
      client.destroy();
      return;
    }

    final method = requestLine[0].toUpperCase();
    final target = requestLine[1];

    String host;
    int port;
    Uint8List forward;

    if (method == 'CONNECT') {
      final colon = target.lastIndexOf(':');
      host = colon > 0 ? target.substring(0, colon) : target;
      port = colon > 0 ? int.tryParse(target.substring(colon + 1)) ?? 443 : 443;
      forward = head.sublist(headerEnd);
    } else {
      final uri = Uri.tryParse(target);
      if (uri == null || !uri.isScheme('http') || uri.host.isEmpty) {
        client.write('HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n');
        await client.close();
        return;
      }
      host = uri.host;
      port = uri.hasPort ? uri.port : 80;
      forward = _originForm(header, method, uri, head.sublist(headerEnd));
    }

    if (host.startsWith('[') && host.endsWith(']')) host = host.substring(1, host.length - 1);

    Socket upstream;
    try {
      upstream = await SecureDns.instance.connect(host, port);
    } on Object {
      client.write('HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n');
      await client.close();
      return;
    }

    if (method == 'CONNECT') {
      client.write('HTTP/1.1 200 Connection Established\r\n\r\n');
    }
    if (forward.isNotEmpty) upstream.add(forward);

    _relay(incoming, upstream, client);
    _relay(upstream.listen(null), client, upstream);
  }

  static Uint8List _originForm(String header, String method, Uri uri, Uint8List body) {
    final lines = header.split('\r\n');
    final version = lines.first.split(' ').last;
    final path = uri.hasQuery
        ? '${uri.path.isEmpty ? '/' : uri.path}?${uri.query}'
        : (uri.path.isEmpty ? '/' : uri.path);
    final kept = <String>['$method $path $version'];
    var hasHost = false;
    for (final line in lines.skip(1)) {
      if (line.isEmpty) continue;
      final name = line.split(':').first.trim().toLowerCase();
      if (name == 'proxy-connection' || name == 'connection' || name == 'proxy-authorization') {
        continue;
      }
      if (name == 'host') hasHost = true;
      kept.add(line);
    }
    if (!hasHost) kept.add('Host: ${uri.hasPort ? '${uri.host}:${uri.port}' : uri.host}');
    kept.add('Connection: close');
    final rewritten = latin1.encode('${kept.join('\r\n')}\r\n\r\n');
    return Uint8List.fromList([...rewritten, ...body]);
  }

  static void _relay(StreamSubscription<Uint8List> from, Socket to, Socket other) {
    var closed = false;
    void shut() {
      if (closed) return;
      closed = true;
      to.destroy();
      other.destroy();
    }

    from.onData((data) {
      try {
        to.add(data);
      } on Object {
        shut();
        return;
      }
      from.pause();
      to.flush().then((_) => from.resume(), onError: (Object _) => shut());
    });
    from.onDone(shut);
    from.onError((Object _) => shut());
    if (from.isPaused) from.resume();
  }
}
