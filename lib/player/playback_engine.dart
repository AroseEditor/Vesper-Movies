import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/redact.dart';
import '../core/secure_dns.dart';
import '../models/release.dart';
import 'subtitle_style.dart';

final _urlPattern = RegExp(r'[a-z][a-z0-9+.-]*://[^\s"<>]+', caseSensitive: false);

String redactLog(String text) => text.replaceAllMapped(_urlPattern, (m) => redactUrl(m[0]!));

class EngineChapter {
  const EngineChapter({required this.title, required this.start});

  final String title;
  final Duration start;
}

abstract class PlaybackEngine {
  static PlaybackEngine create() => Platform.isAndroid ? ExoEngine() : MpvEngine();

  String get name;

  mk.PlayerState get state;

  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<bool> get playingStream;
  Stream<bool> get bufferingStream;
  Stream<mk.Tracks> get tracksStream;
  Stream<mk.Track> get trackStream;
  Stream<String> get errorStream;

  bool get rendersSubtitles;
  Stream<String> get cueStream;

  bool get needsStartBuffer;

  bool get errorsAreTerminal;

  Future<void> open({
    required String url,
    required Map<String, String> headers,
    required Duration start,
    required List<SubtitleOption> subtitles,
    required int maxHeight,
  });

  Future<void> play();
  Future<void> pause();
  Future<void> playOrPause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> setRate(double rate);
  Future<void> setAudioTrack(mk.AudioTrack track);
  Future<void> setVideoTrack(mk.VideoTrack track);
  Future<void> setSubtitleTrack(mk.SubtitleTrack track);
  Future<void> applySubtitleStyle(SubtitleStyle style);
  Future<void> setMaxHeight(int height);

  Future<(Duration, bool)> bufferedAhead();
  Future<List<EngineChapter>> chapters();

  Widget buildVideo();

  Future<void> stop();
  Future<void> dispose();
}

class MpvEngine implements PlaybackEngine {
  MpvEngine() {
    _player = mk.Player(
      configuration: const mk.PlayerConfiguration(
        title: 'Vesper Movies',
        bufferSize: 256 * 1024 * 1024,
        logLevel: mk.MPVLogLevel.warn,
        protocolWhitelist: [
          'udp',
          'rtp',
          'tcp',
          'tls',
          'data',
          'file',
          'http',
          'https',
          'crypto',
          'httpproxy',
        ],
      ),
    );
    _video = VideoController(_player);
    _logs = _player.stream.log.listen((entry) {
      debugPrint('mpv [${entry.prefix}] ${entry.level}: ${redactLog(entry.text)}');
    });
  }

  late final mk.Player _player;
  late final VideoController _video;
  late final StreamSubscription<mk.PlayerLog> _logs;

  @override
  String get name => 'mpv';

  @override
  mk.PlayerState get state => _player.state;

  @override
  Stream<Duration> get positionStream => _player.stream.position;

  @override
  Stream<Duration> get durationStream => _player.stream.duration;

  @override
  Stream<bool> get playingStream => _player.stream.playing;

  @override
  Stream<bool> get bufferingStream => _player.stream.buffering;

  @override
  Stream<mk.Tracks> get tracksStream => _player.stream.tracks;

  @override
  Stream<mk.Track> get trackStream => _player.stream.track;

  @override
  Stream<String> get errorStream => _player.stream.error;

  @override
  bool get rendersSubtitles => true;

  @override
  Stream<String> get cueStream => const Stream.empty();

  @override
  bool get needsStartBuffer => true;

  @override
  bool get errorsAreTerminal => false;

  mk.NativePlayer? get _native {
    final platform = _player.platform;
    return platform is mk.NativePlayer ? platform : null;
  }

  @override
  Future<void> open({
    required String url,
    required Map<String, String> headers,
    required Duration start,
    required List<SubtitleOption> subtitles,
    required int maxHeight,
  }) async {
    await _tune(maxHeight);
    await _player.open(mk.Media(url, httpHeaders: headers, start: start), play: false);
  }

  Future<void> _tune(int maxHeight) async {
    final native = _native;
    if (native == null) return;

    var diskCache = false;
    try {
      final dir = await getTemporaryDirectory();
      final cacheDir = Directory(p.join(dir.path, 'stream-cache'));
      if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);
      await native.setProperty('cache-dir', cacheDir.path);
      diskCache = true;
    } on Object catch (error) {
      debugPrint('stream cache dir unavailable: $error');
    }

    final properties = {
      'cache': 'yes',
      'cache-secs': '900',
      'cache-on-disk': diskCache ? 'yes' : 'no',
      'demuxer-max-bytes': diskCache ? '1073741824' : '268435456',
      'demuxer-max-back-bytes': diskCache ? '268435456' : '67108864',
      'demuxer-readahead-secs': '900',
      'cache-pause': 'yes',
      'cache-pause-initial': 'yes',
      'cache-pause-wait': '12',
      'demuxer-hysteresis-secs': '60',
      'network-timeout': '30',
      'stream-lavf-o':
          'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_delay_max=15',
      'keep-open': 'yes',
      'hr-seek': 'yes',
      'force-seekable': 'yes',
      'vd-lavc-threads': '0',
      'hwdec': 'auto-safe',
      'hls-bitrate': switch (maxHeight) {
        <= 0 => 'max',
        <= 480 => '2000000',
        <= 720 => '5000000',
        _ => '9000000',
      },
    };

    for (final entry in properties.entries) {
      try {
        await native.setProperty(entry.key, entry.value);
      } on Object catch (_) {
        continue;
      }
    }

    final tunnel = StreamTunnel.running;
    final useTunnel = tunnel != null && StreamTunnel.routePlayback;
    try {
      await native.setProperty('http-proxy', useTunnel ? tunnel.proxyUrl : '');
    } on Object catch (error) {
      debugPrint('http-proxy not applied: $error');
    }
    debugPrint('playback engine mpv, tunnel ${useTunnel ? 'on' : 'off'}');
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> playOrPause() => _player.playOrPause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> setRate(double rate) => _player.setRate(rate);

  @override
  Future<void> setAudioTrack(mk.AudioTrack track) => _player.setAudioTrack(track);

  @override
  Future<void> setVideoTrack(mk.VideoTrack track) => _player.setVideoTrack(track);

  @override
  Future<void> setSubtitleTrack(mk.SubtitleTrack track) => _player.setSubtitleTrack(track);

  @override
  Future<void> applySubtitleStyle(SubtitleStyle style) async {
    final native = _native;
    if (native == null) return;
    for (final entry in style.toMpvProperties().entries) {
      try {
        await native.setProperty(entry.key, entry.value);
      } on Object catch (_) {
        continue;
      }
    }
  }

  @override
  Future<void> setMaxHeight(int height) async {}

  @override
  Future<(Duration, bool)> bufferedAhead() async {
    final native = _native;
    if (native == null) return (Duration.zero, false);
    final idle = await native.getProperty('demuxer-cache-idle');
    final raw = await native.getProperty('demuxer-cache-duration');
    final seconds = double.tryParse(raw) ?? 0;
    return (Duration(milliseconds: (seconds * 1000).round()), idle == 'yes');
  }

  @override
  Future<List<EngineChapter>> chapters() async {
    final native = _native;
    if (native == null) return const [];
    try {
      final decoded = jsonDecode(await native.getProperty('chapter-list'));
      if (decoded is! List) return const [];
      return [
        for (final entry in decoded)
          if (entry is Map && entry['time'] is num)
            EngineChapter(
              title: '${entry['title'] ?? ''}',
              start: Duration(milliseconds: ((entry['time'] as num) * 1000).round()),
            ),
      ];
    } on Object {
      return const [];
    }
  }

  @override
  Widget buildVideo() => Video(controller: _video, controls: NoVideoControls, fit: BoxFit.contain);

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() async {
    await _logs.cancel();
    await _player.dispose();
  }
}

class ExoEngine implements PlaybackEngine {
  ExoEngine() {
    _ready = _create();
  }

  static const _channel = MethodChannel('vesper/exo');

  late final Future<int?> _ready;
  int? _id;
  StreamSubscription<dynamic>? _events;

  mk.PlayerState _state = const mk.PlayerState();
  List<SubtitleOption> _external = const [];
  final ValueNotifier<Size?> _videoSize = ValueNotifier(null);

  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _tracks = StreamController<mk.Tracks>.broadcast();
  final _track = StreamController<mk.Track>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final _cues = StreamController<String>.broadcast();

  Future<int?> _create() async {
    try {
      final id = await _channel.invokeMethod<int>('create');
      if (id == null) return null;
      _id = id;
      _events = EventChannel('vesper/exo/$id')
          .receiveBroadcastStream()
          .listen(_onEvent, onError: (Object error) => debugPrint('exo events failed: $error'));
      return id;
    } on Object catch (error) {
      debugPrint('exo create failed: $error');
      _errors.add('Failed to open: the Android player could not start.');
      return null;
    }
  }

  Future<void> _call(String method, [Map<String, Object?> args = const {}]) async {
    final id = await _ready;
    if (id == null) return;
    try {
      await _channel.invokeMethod<void>(method, {'id': id, ...args});
    } on PlatformException catch (error) {
      debugPrint('exo $method failed: ${redactLog(error.message ?? error.code)}');
      if (method == 'open') _errors.add('Failed to open: ${error.message ?? error.code}');
    }
  }

  static Duration _ms(Object? value) => Duration(milliseconds: value is num ? value.toInt() : 0);

  void _onEvent(dynamic raw) {
    if (raw is! Map) return;
    switch (raw['type']) {
      case 'state':
        final position = _ms(raw['position']);
        final duration = _ms(raw['duration']);
        final playing = raw['playing'] == true;
        final buffering = raw['buffering'] == true;
        final previous = _state;
        _state = _state.copyWith(
          position: position,
          duration: duration,
          buffer: _ms(raw['buffered']),
          playing: playing,
          buffering: buffering,
          completed: raw['completed'] == true,
          rate: (raw['rate'] as num?)?.toDouble() ?? _state.rate,
          volume: ((raw['volume'] as num?)?.toDouble() ?? 1) * 100,
        );
        _position.add(position);
        if (previous.duration != duration) _duration.add(duration);
        if (previous.playing != playing) _playing.add(playing);
        if (previous.buffering != buffering) _buffering.add(buffering);
      case 'tracks':
        _applyTracks(raw);
      case 'cues':
        _cues.add('${raw['text'] ?? ''}');
      case 'video':
        final width = (raw['width'] as num?)?.toDouble() ?? 0;
        final height = (raw['height'] as num?)?.toDouble() ?? 0;
        final ratio = (raw['ratio'] as num?)?.toDouble() ?? 1;
        if (width > 0 && height > 0) _videoSize.value = Size(width * ratio, height);
      case 'error':
        final message = '${raw['message'] ?? 'playback error'}';
        debugPrint('exo error: $message');
        _errors.add('Failed to open: $message');
    }
  }

  static String? _string(Object? value) => value is String && value.isNotEmpty ? value : null;

  static int? _int(Object? value) => value is num ? value.toInt() : null;

  void _applyTracks(Map<dynamic, dynamic> raw) {
    List<Map<dynamic, dynamic>> list(String key) => [
      for (final entry in (raw[key] as List? ?? const []))
        if (entry is Map) entry,
    ];

    final audio = <mk.AudioTrack>[
      mk.AudioTrack.auto(),
      mk.AudioTrack.no(),
      for (final entry in list('audio'))
        mk.AudioTrack(
          '${entry['id']}',
          _string(entry['title']),
          _string(entry['language']),
          codec: _string(entry['codec']),
          bitrate: _int(entry['bitrate']),
          channelscount: _int(entry['channels']),
        ),
    ];
    final video = <mk.VideoTrack>[
      mk.VideoTrack.auto(),
      mk.VideoTrack.no(),
      for (final entry in list('video'))
        mk.VideoTrack(
          '${entry['id']}',
          _string(entry['title']) ??
              (_int(entry['height']) == null ? null : '${_int(entry['height'])}p'),
          _string(entry['language']),
          w: _int(entry['width']),
          h: _int(entry['height']),
          bitrate: _int(entry['bitrate']),
          codec: _string(entry['codec']),
        ),
    ];
    final subtitle = <mk.SubtitleTrack>[
      mk.SubtitleTrack.auto(),
      mk.SubtitleTrack.no(),
      for (final entry in list('subtitle'))
        if (!'${entry['id']}'.startsWith('ext:'))
          mk.SubtitleTrack('${entry['id']}', _string(entry['title']), _string(entry['language'])),
    ];

    T pick<T>(List<T> tracks, Object? id, String Function(T) idOf, T fallback) {
      if (id is! String) return fallback;
      for (final track in tracks) {
        if (idOf(track) == id) return track;
      }
      return fallback;
    }

    final selectedSub = raw['selectedSubtitle'];
    mk.SubtitleTrack currentSub;
    if (selectedSub is String && selectedSub.startsWith('ext:')) {
      final index = int.tryParse(selectedSub.substring(4)) ?? -1;
      currentSub = index >= 0 && index < _external.length
          ? mk.SubtitleTrack.uri(_external[index].url, title: _external[index].name)
          : mk.SubtitleTrack.auto();
    } else {
      currentSub = pick(subtitle, selectedSub, (t) => t.id, mk.SubtitleTrack.auto());
    }

    final tracks = mk.Tracks(video: video, audio: audio, subtitle: subtitle);
    _state = _state.copyWith(
      tracks: tracks,
      track: mk.Track(
        audio: pick(audio, raw['selectedAudio'], (t) => t.id, mk.AudioTrack.auto()),
        video: pick(video, raw['selectedVideo'], (t) => t.id, mk.VideoTrack.auto()),
        subtitle: currentSub,
      ),
    );
    _tracks.add(tracks);
    _track.add(_state.track);
  }

  @override
  String get name => 'exoplayer';

  @override
  mk.PlayerState get state => _state;

  @override
  Stream<Duration> get positionStream => _position.stream;

  @override
  Stream<Duration> get durationStream => _duration.stream;

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Stream<bool> get bufferingStream => _buffering.stream;

  @override
  Stream<mk.Tracks> get tracksStream => _tracks.stream;

  @override
  Stream<mk.Track> get trackStream => _track.stream;

  @override
  Stream<String> get errorStream => _errors.stream;

  @override
  bool get rendersSubtitles => false;

  @override
  Stream<String> get cueStream => _cues.stream;

  @override
  bool get needsStartBuffer => false;

  @override
  bool get errorsAreTerminal => true;

  @override
  Future<void> open({
    required String url,
    required Map<String, String> headers,
    required Duration start,
    required List<SubtitleOption> subtitles,
    required int maxHeight,
  }) async {
    _external = subtitles;
    _state = const mk.PlayerState();
    _videoSize.value = null;
    _cues.add('');
    debugPrint(
      'playback engine exoplayer, secure dns ${StreamTunnel.routePlayback ? 'on' : 'off'}',
    );
    await _call('open', {
      'url': url,
      'headers': headers,
      'startMs': start.inMilliseconds,
      'play': true,
      'secureDns': StreamTunnel.routePlayback,
      'maxHeight': maxHeight,
      'subtitles': [
        for (final option in subtitles) {'url': option.url, 'name': option.name},
      ],
    });
  }

  @override
  Future<void> play() => _call('play');

  @override
  Future<void> pause() => _call('pause');

  @override
  Future<void> playOrPause() => _state.playing ? pause() : play();

  @override
  Future<void> seek(Duration position) => _call('seek', {'ms': position.inMilliseconds});

  @override
  Future<void> setVolume(double volume) => _call('volume', {'value': volume / 100});

  @override
  Future<void> setRate(double rate) => _call('rate', {'value': rate});

  @override
  Future<void> setAudioTrack(mk.AudioTrack track) =>
      _call('select', {'type': 'audio', 'id': track.id});

  @override
  Future<void> setVideoTrack(mk.VideoTrack track) =>
      _call('select', {'type': 'video', 'id': track.id});

  @override
  Future<void> setSubtitleTrack(mk.SubtitleTrack track) {
    var id = track.id;
    if (track.uri) {
      final index = _external.indexWhere((option) => option.url == track.id);
      if (index < 0) return Future.value();
      id = 'ext:$index';
    }
    if (id == 'no') _cues.add('');
    return _call('select', {'type': 'text', 'id': id});
  }

  @override
  Future<void> applySubtitleStyle(SubtitleStyle style) async {}

  @override
  Future<void> setMaxHeight(int height) => _call('maxHeight', {'value': height});

  @override
  Future<(Duration, bool)> bufferedAhead() async {
    final ahead = _state.buffer - _state.position;
    return (ahead.isNegative ? Duration.zero : ahead, false);
  }

  @override
  Future<List<EngineChapter>> chapters() async => const [];

  @override
  Widget buildVideo() {
    return ValueListenableBuilder<Size?>(
      valueListenable: _videoSize,
      builder: (context, size, _) {
        final id = _id;
        if (id == null) return const SizedBox.expand();
        final ratio = size == null || size.height <= 0 ? 16 / 9 : size.width / size.height;
        return Center(
          child: AspectRatio(
            aspectRatio: ratio,
            child: Texture(textureId: id, filterQuality: FilterQuality.medium),
          ),
        );
      },
    );
  }

  @override
  Future<void> stop() async {
    _cues.add('');
    await _call('stop');
    _state = const mk.PlayerState();
  }

  @override
  Future<void> dispose() async {
    await _events?.cancel();
    await _call('dispose');
    for (final controller in [
      _position,
      _duration,
      _playing,
      _buffering,
      _tracks,
      _track,
      _errors,
      _cues,
    ]) {
      await controller.close();
    }
    _videoSize.dispose();
  }
}
