import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'player_controller.dart';

const Duration _bucket = Duration(seconds: 10);
const Duration _idleTimeout = Duration(seconds: 4);
const int _maxFrames = 48;

class PreviewFrame {
  const PreviewFrame({required this.position, required this.bytes});

  final Duration position;
  final Uint8List bytes;
}

class PreviewState {
  const PreviewState({this.frame, this.position, this.loading = false});

  final PreviewFrame? frame;
  final Duration? position;
  final bool loading;

  bool get isActive => position != null;

  static const idle = PreviewState();
}

class ScrubPreviewNotifier extends Notifier<PreviewState> {
  Player? _player;
  VideoController? _video;
  Timer? _idle;
  Timer? _debounce;
  bool _grabbing = false;
  String? _openedUrl;
  Duration? _wanted;

  final Map<int, Uint8List> _frames = {};

  @override
  PreviewState build() {
    ref.onDispose(_teardown);
    return PreviewState.idle;
  }

  void hover(Duration position) {
    _idle?.cancel();
    _idle = Timer(_idleTimeout, cancel);

    final key = _keyFor(position);
    final cached = _frames[key];

    state = PreviewState(
      position: position,
      frame: cached == null ? state.frame : PreviewFrame(position: position, bytes: cached),
      loading: cached == null,
    );

    if (cached != null) return;

    _wanted = position;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () => unawaited(_grab()));
  }

  void cancel() {
    _idle?.cancel();
    _debounce?.cancel();
    _idle = null;
    _debounce = null;
    _wanted = null;
    state = PreviewState.idle;
    _teardown();
  }

  int _keyFor(Duration position) => position.inMilliseconds ~/ _bucket.inMilliseconds;

  Future<void> _grab() async {
    if (_grabbing) return;

    final target = _wanted;
    final source = ref.read(playerControllerProvider).target?.source;
    if (target == null || source == null) return;

    _grabbing = true;
    try {
      final player = await _ensurePlayer(source.url, source.headers);
      if (player == null) return;

      await player.seek(target);
      await Future<void>.delayed(const Duration(milliseconds: 140));

      final bytes = await player.screenshot();
      if (bytes == null || bytes.isEmpty) return;

      if (_frames.length >= _maxFrames) {
        _frames.remove(_frames.keys.first);
      }
      _frames[_keyFor(target)] = bytes;

      if (state.isActive) {
        state = PreviewState(
          position: state.position,
          frame: PreviewFrame(position: target, bytes: bytes),
          loading: false,
        );
      }
    } on Object {
      if (state.isActive) {
        state = PreviewState(position: state.position, frame: state.frame);
      }
    } finally {
      _grabbing = false;
      if (_wanted != target && state.isActive) unawaited(_grab());
    }
  }

  Future<Player?> _ensurePlayer(String url, Map<String, String> headers) async {
    if (_player != null && _video != null && _openedUrl == url) return _player;

    await _disposePlayer();

    final player = Player(
      configuration: const PlayerConfiguration(
        title: 'Vesper Preview',
        muted: true,
        bufferSize: 4 * 1024 * 1024,
      ),
    );

    final native = player.platform;
    if (native is NativePlayer) {
      const tuning = {
        'audio': 'no',
        'sub': 'no',
        'cache': 'no',
        'hr-seek': 'yes',
        'hr-seek-framedrop': 'yes',
        'demuxer-readahead-secs': '0',
        'demuxer-max-bytes': '16777216',
        'vd-lavc-skiploopfilter': 'all',
        'vd-lavc-fast': 'yes',
        'vd-lavc-threads': '1',
        'framedrop': 'vo',
      };
      for (final entry in tuning.entries) {
        try {
          await native.setProperty(entry.key, entry.value);
        } on Object {
          continue;
        }
      }
    }

    _video = VideoController(
      player,
      configuration: const VideoControllerConfiguration(width: 320, height: 180),
    );

    await player.open(Media(url, httpHeaders: headers), play: false);
    await player.setVolume(0);

    _player = player;
    _openedUrl = url;
    return player;
  }

  Future<void> _disposePlayer() async {
    final player = _player;
    _player = null;
    _video = null;
    _openedUrl = null;
    if (player != null) await player.dispose();
  }

  void _teardown() {
    _idle?.cancel();
    _debounce?.cancel();
    _frames.clear();
    unawaited(_disposePlayer());
  }
}

final scrubPreviewProvider = NotifierProvider<ScrubPreviewNotifier, PreviewState>(
  ScrubPreviewNotifier.new,
);
