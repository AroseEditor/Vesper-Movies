import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
    ..connectionTimeout = const Duration(seconds: 6)
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
    for (final endpoint in _dohEndpoints) {
      try {
        final result = await _query(endpoint, host).timeout(const Duration(seconds: 7));
        if (result == null) continue;
        _cache[host] = _Cached(result.$1, DateTime.now().add(result.$2));
        return result.$1;
      } on Object {
        continue;
      }
    }
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
  StreamTunnel._(this._server);

  static StreamTunnel? _instance;

  final ServerSocket _server;

  int get port => _server.port;

  String get proxyUrl => 'http://127.0.0.1:$port';

  static Future<StreamTunnel?> start() async {
    final existing = _instance;
    if (existing != null) return existing;
    try {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final tunnel = StreamTunnel._(server);
      server.listen(tunnel._handle, onError: (Object _) {});
      return _instance = tunnel;
    } on Object {
      return null;
    }
  }

  static StreamTunnel? get running => _instance;

  void _handle(Socket client) {
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

  Future<void> _route(
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
      forward = head;
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

    incoming.onData((data) {
      try {
        upstream.add(data);
      } on Object {
        client.destroy();
      }
    });
    incoming.onDone(() => upstream.destroy());
    incoming.onError((Object _) => upstream.destroy());
    incoming.resume();

    upstream.listen(
      (data) {
        try {
          client.add(data);
        } on Object {
          upstream.destroy();
        }
      },
      onDone: () => client.destroy(),
      onError: (Object _) => client.destroy(),
      cancelOnError: true,
    );
  }
}
