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

  String get manifestUrl => 'http://127.0.0.1:$port/manifest.mpd';

  static Future<ProbeServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final probe = ProbeServer(server);
    unawaited(probe._listen());
    return probe;
  }

  Future<void> _listen() async {
    await for (final request in _server) {
      final path = request.uri.path;
      final carried = request.headers.value(_probeHeader) == _probeValue;
      final cookie = request.headers.value('cookie') ?? '';
      final sawCookie = cookie.contains(_probeValue);
      final ok = carried || sawCookie;

      if (path.endsWith('.mpd')) {
        (ok ? manifestHits : manifestMisses).add(path);
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType('application', 'dash+xml')
          ..write(_manifest());
      } else if (path.startsWith('/seg/')) {
        (ok ? segmentHits : segmentMisses).add(path);
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType('video', 'iso.segment')
          ..add(const []);
      } else {
        request.response.statusCode = 404;
      }

      await request.response.close();
    }
  }

  String _manifest() {
    return '''
<?xml version="1.0" encoding="utf-8"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" profiles="urn:mpeg:dash:profile:isoff-live:2011"
     type="static" mediaPresentationDuration="PT10S" minBufferTime="PT2S">
  <Period id="0">
    <AdaptationSet mimeType="video/mp4" segmentAlignment="true">
      <Representation id="v0" codecs="avc1.64001f" bandwidth="500000" width="640" height="360">
        <SegmentTemplate media="/seg/chunk-\$Number\$.m4s" initialization="/seg/init.mp4"
                         startNumber="1" duration="2" timescale="1"/>
      </Representation>
    </AdaptationSet>
  </Period>
</MPD>
''';
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
      return 'INCONCLUSIVE — the player never requested a segment.';
    }
    if (proxyCanBeDeleted) {
      return 'PASS — headers reach segment requests. The loopback proxy is not needed on $platform.';
    }
    if (manifestCarried) {
      return 'FAIL — headers reach the manifest but not segments. Port the loopback proxy.';
    }
    return 'FAIL — headers do not reach the manifest at all.';
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

    final deadline = DateTime.now().add(const Duration(seconds: 12));
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
      debugPrint('SPIKE ${result.verdict}');
      debugPrint(
        'SPIKE manifest=${result.manifestCarried} '
        'segments=${result.segmentCarried} count=${result.segmentTotal}',
      );
      if (mounted) setState(() => _result = result);
    } on Object catch (error) {
      debugPrint('SPIKE ERROR $error');
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final error = _error;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: Scaffold(
        backgroundColor: const Color(0xFF141414),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              error != null
                  ? 'Spike failed: $error'
                  : result == null
                  ? 'Probing DASH segment headers...'
                  : '${result.verdict}\n\n'
                        'manifest carried: ${result.manifestCarried}\n'
                        'segments carried: ${result.segmentCarried}\n'
                        'segment requests: ${result.segmentTotal}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, height: 1.5),
            ),
          ),
        ),
      ),
    );
  }
}
