import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

const _probeHeader = 'x-vesper-probe';
const _probeValue = 'segment-header-check';

class ProbeServer {
  ProbeServer(this._server);

  final HttpServer _server;
  final List<String> manifestHits = [];
  final List<String> segmentHits = [];
  final List<String> manifestMisses = [];
  final List<String> segmentMisses = [];

  int get port => _server.port;

  String get manifestUrl => 'http://127.0.0.1:$port/playlist.m3u8';

  static Future<ProbeServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final probe = ProbeServer(server);
    unawaited(probe._listen());
    return probe;
  }

  Future<void> _listen() async {
    try {
      await _serve();
    } on Object catch (_) {
      return;
    }
  }

  Future<void> _serve() async {
    await for (final request in _server) {
      final path = request.uri.path;
      final tagged = request.headers.value(_probeHeader) == _probeValue;
      final cookie = request.headers.value('cookie') ?? '';
      final carried = tagged || cookie.contains(_probeValue);

      if (path.endsWith('.m3u8')) {
        (carried ? manifestHits : manifestMisses).add(path);
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType('application', 'vnd.apple.mpegurl')
          ..write(_playlist());
      } else if (path.startsWith('/seg/')) {
        (carried ? segmentHits : segmentMisses).add(path);
        request.response.statusCode = 404;
      } else {
        request.response.statusCode = 404;
      }

      await request.response.close();
    }
  }

  String _playlist() {
    final lines = [
      '#EXTM3U',
      '#EXT-X-VERSION:3',
      '#EXT-X-TARGETDURATION:2',
      '#EXT-X-MEDIA-SEQUENCE:0',
      '#EXTINF:2.0,',
      '/seg/chunk-0.ts',
      '#EXTINF:2.0,',
      '/seg/chunk-1.ts',
      '#EXT-X-ENDLIST',
    ];
    return lines.join('\n');
  }

  Future<void> stop() => _server.close(force: true);
}

class SpikeResult {
  const SpikeResult({
    required this.manifestCarried,
    required this.segmentCarried,
    required this.segmentTotal,
    required this.platform,
  });

  final bool manifestCarried;
  final bool segmentCarried;
  final int segmentTotal;
  final String platform;

  bool get proxyCanBeDeleted => manifestCarried && segmentCarried;

  String get verdict {
    if (segmentTotal == 0) {
      return 'INCONCLUSIVE - the player never requested a segment';
    }
    if (proxyCanBeDeleted) {
      return 'PASS - headers reach segment requests, no loopback proxy needed on $platform';
    }
    if (manifestCarried) {
      return 'FAIL - headers reach the manifest but not segments, port the loopback proxy';
    }
    return 'FAIL - headers do not reach the manifest at all';
  }
}

Future<SpikeResult> runSpike() async {
  final server = await ProbeServer.start();
  final player = Player();

  try {
    await player.open(
      Media(
        server.manifestUrl,
        httpHeaders: const {_probeHeader: _probeValue, 'Cookie': 'probe=$_probeValue'},
      ),
      play: true,
    );

    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (server.segmentHits.isNotEmpty || server.segmentMisses.isNotEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 750));
        break;
      }
    }

    return SpikeResult(
      manifestCarried: server.manifestHits.isNotEmpty,
      segmentCarried: server.segmentHits.isNotEmpty && server.segmentMisses.isEmpty,
      segmentTotal: server.segmentHits.length + server.segmentMisses.length,
      platform: Platform.operatingSystem,
    );
  } finally {
    await player.dispose();
    await server.stop();
  }
}

void writeReport(String verdict, SpikeResult? result) {
  final buffer = StringBuffer()
    ..writeln('platform: ${Platform.operatingSystem}')
    ..writeln('verdict: $verdict');

  if (result != null) {
    buffer
      ..writeln('manifestCarried: ${result.manifestCarried}')
      ..writeln('segmentCarried: ${result.segmentCarried}')
      ..writeln('segmentTotal: ${result.segmentTotal}')
      ..writeln('proxyCanBeDeleted: ${result.proxyCanBeDeleted}');
  }

  try {
    File('spike_result.txt').writeAsStringSync(buffer.toString());
  } on Object catch (_) {
    return;
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const SpikeApp());
}

class SpikeApp extends StatefulWidget {
  const SpikeApp({super.key});

  @override
  State<SpikeApp> createState() => _SpikeAppState();
}

class _SpikeAppState extends State<SpikeApp> {
  SpikeResult? _result;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final result = await runSpike();
      writeReport(result.verdict, result);
      debugPrint('SPIKE ${result.verdict}');
      if (mounted) setState(() => _result = result);
    } on Object catch (error) {
      writeReport('ERROR $error', null);
      debugPrint('SPIKE ERROR $error');
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final error = _error;

    final message = error != null
        ? 'Spike failed: $error'
        : result == null
        ? 'Probing segment headers...'
        : '${result.verdict}\n\n'
              'manifest carried: ${result.manifestCarried}\n'
              'segments carried: ${result.segmentCarried}\n'
              'segment requests: ${result.segmentTotal}';

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: Scaffold(
        backgroundColor: const Color(0xFF141414),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, height: 1.5),
            ),
          ),
        ),
      ),
    );
  }
}
