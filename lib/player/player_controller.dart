import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/secure_dns.dart';
import '../models/release.dart';
import 'language_prefs.dart';
import 'subtitle_style.dart';

const Duration preloadWindow = Duration(minutes: 10);
const Duration preloadDeadline = Duration(seconds: 100);

class PlaybackTarget {
  const PlaybackTarget({
    required this.source,
    required this.title,
    this.subtitle,
    this.startAt = Duration.zero,
    this.season,
    this.episode,
    this.mediaId,
  });

  final PlaybackSource source;
  final String title;
  final String? subtitle;
  final Duration startAt;
  final int? season;
  final int? episode;
  final String? mediaId;
}

class Chapter {
  const Chapter({required this.title, required this.start});

  final String title;
  final Duration start;
}

class Preload {
  const Preload({this.active = false, this.buffered = Duration.zero, this.target = Duration.zero});

  final bool active;
  final Duration buffered;
  final Duration target;

  double get ratio {
    if (target <= Duration.zero) return 0;
    final value = buffered.inMilliseconds / target.inMilliseconds;
    return value < 0 ? 0 : (value > 1 ? 1 : value);
  }

  static const idle = Preload();
}

class PlayerState {
  const PlayerState({
    this.target,
    this.subtitleStyle = SubtitleStyle.defaults,
    this.externalSubtitles = const [],
    this.activeExternal,
    this.isReady = false,
    this.error,
    this.preload = Preload.idle,
  });

  final PlaybackTarget? target;
  final SubtitleStyle subtitleStyle;
  final List<SubtitleOption> externalSubtitles;
  final String? activeExternal;
  final bool isReady;
  final String? error;
  final Preload preload;

  PlayerState copyWith({
    PlaybackTarget? target,
    SubtitleStyle? subtitleStyle,
    List<SubtitleOption>? externalSubtitles,
    String? activeExternal,
    bool clearActiveExternal = false,
    bool? isReady,
    String? error,
    bool clearError = false,
    Preload? preload,
  }) {
    return PlayerState(
      target: target ?? this.target,
      subtitleStyle: subtitleStyle ?? this.subtitleStyle,
      externalSubtitles: externalSubtitles ?? this.externalSubtitles,
      activeExternal: clearActiveExternal ? null : (activeExternal ?? this.activeExternal),
      isReady: isReady ?? this.isReady,
      error: clearError ? null : (error ?? this.error),
      preload: preload ?? this.preload,
    );
  }
}

class PlayerControllerNotifier extends Notifier<PlayerState> {
  Player? _player;
  VideoController? _videoController;
  StreamSubscription<String>? _errorSubscription;
  Timer? _preloadDeadline;
  Timer? _preloadPoll;
  int _session = 0;

  Player get player => _player ??= Player(
    configuration: const PlayerConfiguration(title: 'Vesper Movies', bufferSize: 256 * 1024 * 1024),
  );

  VideoController get videoController => _videoController ??= VideoController(player);

  @override
  PlayerState build() {
    ref.onDispose(() {
      _preloadDeadline?.cancel();
      _preloadPoll?.cancel();
      unawaited(_errorSubscription?.cancel());
      unawaited(_player?.dispose());
      _player = null;
      _videoController = null;
    });
    return const PlayerState();
  }

  void beginOpening() {
    _session++;
    _stopPreloadTimers();
    state = PlayerState(subtitleStyle: state.subtitleStyle);
  }

  void fail(String message) {
    state = state.copyWith(error: message, isReady: false, preload: Preload.idle);
  }

  Future<void> load(PlaybackTarget target) async {
    final session = ++_session;
    _stopPreloadTimers();
    state = state.copyWith(
      target: target,
      externalSubtitles: target.source.subtitles,
      isReady: false,
      clearError: true,
      clearActiveExternal: true,
    );

    _errorSubscription ??= player.stream.error.listen((message) {
      state = state.copyWith(error: message, isReady: false);
    });

    await _applyNetworkTuning();

    await player.open(
      Media(target.source.url, httpHeaders: target.source.headers, start: target.startAt),
      play: false,
    );

    await applySubtitleStyle(state.subtitleStyle);

    final external = target.subtitle ?? target.source.subtitle;
    if (external != null && external.isNotEmpty) {
      await selectExternalSubtitle(SubtitleOption(name: 'Default', url: external));
    }

    if (session != _session) return;
    state = state.copyWith(isReady: true);
    _gatePreload(session);
  }

  void _gatePreload(int session) {
    final native = player.platform;
    if (native is! NativePlayer) {
      unawaited(player.play());
      return;
    }

    state = state.copyWith(preload: const Preload(active: true, target: preloadWindow));

    _preloadDeadline = Timer(preloadDeadline, () => unawaited(_releasePreload()));
    _preloadPoll = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (session != _session) {
        _stopPreloadTimers();
        return;
      }
      unawaited(_pollPreload(native));
    });
  }

  bool _polling = false;

  Future<void> _pollPreload(NativePlayer native) async {
    if (_polling || !state.preload.active) return;
    _polling = true;
    try {
      final idle = await native.getProperty('demuxer-cache-idle');
      final raw = await native.getProperty('demuxer-cache-duration');
      final seconds = double.tryParse(raw) ?? 0;

      final buffered = Duration(milliseconds: (seconds * 1000).round());
      final remaining = player.state.duration - player.state.position;
      final goal = remaining > Duration.zero && remaining < preloadWindow
          ? remaining
          : preloadWindow;

      if (!state.preload.active) return;
      state = state.copyWith(
        preload: Preload(active: true, buffered: buffered, target: goal),
      );

      final full = idle == 'yes' && buffered > const Duration(seconds: 5);
      if (buffered >= goal || full) await _releasePreload();
    } on Object {
      return;
    } finally {
      _polling = false;
    }
  }

  void _stopPreloadTimers() {
    _preloadDeadline?.cancel();
    _preloadPoll?.cancel();
    _preloadDeadline = null;
    _preloadPoll = null;
  }

  Future<void> _releasePreload() async {
    _stopPreloadTimers();
    if (!state.preload.active) return;

    state = state.copyWith(preload: Preload.idle);
    await player.play();
  }

  Future<void> skipPreload() => _releasePreload();

  Future<void> _applyNetworkTuning() async {
    final native = player.platform;
    if (native is! NativePlayer) return;

    try {
      final dir = await getTemporaryDirectory();
      final cacheDir = Directory(p.join(dir.path, 'stream-cache'));
      if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);
      await native.setProperty('cache-dir', cacheDir.path);
    } on Object catch (_) {
      await native.setProperty('cache-on-disk', 'no');
    }

    const properties = {
      'cache': 'yes',
      'cache-secs': '900',
      'cache-on-disk': 'yes',
      'demuxer-max-bytes': '1073741824',
      'demuxer-max-back-bytes': '268435456',
      'demuxer-readahead-secs': '600',
      'demuxer-hysteresis-secs': '60',
      'network-timeout': '30',
      'stream-lavf-o':
          'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_delay_max=15',
      'keep-open': 'yes',
      'hr-seek': 'yes',
      'force-seekable': 'yes',
      'vd-lavc-threads': '0',
      'hwdec': 'auto-safe',
    };

    for (final entry in properties.entries) {
      try {
        await native.setProperty(entry.key, entry.value);
      } on Object catch (_) {
        continue;
      }
    }

    final tunnel = StreamTunnel.running;
    if (tunnel != null) {
      try {
        await native.setProperty('http-proxy', tunnel.proxyUrl);
      } on Object catch (_) {
        return;
      }
    }
  }

  Future<void> selectExternalSubtitle(SubtitleOption option, {bool remember = false}) async {
    await player.setSubtitleTrack(SubtitleTrack.uri(option.url, title: option.name));
    state = state.copyWith(activeExternal: option.url);
    if (remember) {
      await ref.read(languagePrefsProvider.notifier).rememberSubtitle(languageKey(option.name));
    }
  }

  Future<void> clearSubtitles() async {
    await player.setSubtitleTrack(SubtitleTrack.no());
    state = state.copyWith(clearActiveExternal: true);
    await ref.read(languagePrefsProvider.notifier).rememberSubtitle(null);
  }

  Future<bool> waitUntilPlayable(Duration timeout) async {
    if (state.error != null) return false;
    if (player.state.duration > Duration.zero) return true;

    final completer = Completer<bool>();
    final subs = <StreamSubscription<Object>>[
      player.stream.duration.listen((value) {
        if (value > Duration.zero && !completer.isCompleted) completer.complete(true);
      }),
      player.stream.error.listen((_) {
        if (!completer.isCompleted) completer.complete(false);
      }),
    ];

    try {
      return await completer.future.timeout(timeout, onTimeout: () => false);
    } finally {
      for (final sub in subs) {
        await sub.cancel();
      }
    }
  }

  Future<void> applyPreferredTracks() async {
    final prefs = ref.read(languagePrefsProvider);
    if (prefs.audio == null && prefs.subtitle == null && !prefs.subtitlesOff) return;

    var tracks = player.state.tracks;
    if (tracks.audio.length <= 2 && tracks.subtitle.length <= 2) {
      tracks = await player.stream.tracks
          .firstWhere((t) => t.audio.length > 2 || t.subtitle.length > 2)
          .timeout(const Duration(seconds: 15), onTimeout: () => player.state.tracks);
    }

    final audioPref = prefs.audio;
    if (audioPref != null) {
      for (final track in tracks.audio) {
        if (languageKey(track.language, track.title) == audioPref) {
          await player.setAudioTrack(track);
          break;
        }
      }
    }

    if (prefs.subtitlesOff) {
      await player.setSubtitleTrack(SubtitleTrack.no());
      state = state.copyWith(clearActiveExternal: true);
      return;
    }

    final subPref = prefs.subtitle;
    if (subPref == null) return;

    for (final track in tracks.subtitle) {
      if (languageKey(track.language, track.title) == subPref) {
        await player.setSubtitleTrack(track);
        state = state.copyWith(clearActiveExternal: true);
        return;
      }
    }

    for (final option in state.externalSubtitles) {
      if (languageKey(option.name) == subPref) {
        await selectExternalSubtitle(option);
        return;
      }
    }
  }

  Future<List<Chapter>> chapters() async {
    final native = player.platform;
    if (native is! NativePlayer) return const [];
    try {
      final raw = await native.getProperty('chapter-list');
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final entry in decoded)
          if (entry is Map && entry['time'] is num)
            Chapter(
              title: '${entry['title'] ?? ''}',
              start: Duration(milliseconds: ((entry['time'] as num) * 1000).round()),
            ),
      ];
    } on Object {
      return const [];
    }
  }

  Tracks get tracks => player.state.tracks;

  Future<void> applySubtitleStyle(SubtitleStyle style) async {
    state = state.copyWith(subtitleStyle: style);

    final native = player.platform;
    if (native is! NativePlayer) return;

    for (final entry in style.toMpvProperties().entries) {
      try {
        await native.setProperty(entry.key, entry.value);
      } on Object catch (_) {
        continue;
      }
    }
  }

  Future<void> togglePlay() async {
    if (state.preload.active) {
      await _releasePreload();
      return;
    }
    await player.playOrPause();
  }

  Future<void> seekBy(Duration delta) async {
    final position = player.state.position + delta;
    final duration = player.state.duration;
    final clamped = position < Duration.zero
        ? Duration.zero
        : (duration > Duration.zero && position > duration ? duration : position);
    await player.seek(clamped);
  }

  Future<void> seekTo(Duration position) => player.seek(position);

  Future<void> setVolume(double volume) => player.setVolume(volume.clamp(0, 100));

  Future<void> nudgeVolume(double delta) => setVolume(player.state.volume + delta);

  Future<void> toggleMute() => player.setVolume(player.state.volume > 0 ? 0 : 100);

  Future<void> setSpeed(double rate) => player.setRate(rate.clamp(0.25, 3.0));

  Future<void> nudgeSpeed(double delta) => setSpeed(player.state.rate + delta);

  Future<void> selectAudio(AudioTrack track) async {
    await player.setAudioTrack(track);
    await ref
        .read(languagePrefsProvider.notifier)
        .rememberAudio(languageKey(track.language, track.title));
  }

  Future<void> selectSubtitle(SubtitleTrack track) async {
    await player.setSubtitleTrack(track);
    state = state.copyWith(clearActiveExternal: true);
    final prefs = ref.read(languagePrefsProvider.notifier);
    if (track.id == 'no') {
      await prefs.rememberSubtitle(null);
    } else {
      final key = languageKey(track.language, track.title);
      if (key != null) await prefs.rememberSubtitle(key);
    }
  }

  Future<void> selectVideo(VideoTrack track) => player.setVideoTrack(track);

  Future<void> nudgeSubtitleDelay(int deltaMs) =>
      applySubtitleStyle(state.subtitleStyle.nudgeDelay(deltaMs));

  Future<void> stop() async {
    _session++;
    _stopPreloadTimers();
    await player.stop();
    state = const PlayerState();
  }
}

final playerControllerProvider = NotifierProvider<PlayerControllerNotifier, PlayerState>(
  PlayerControllerNotifier.new,
);

final playerPositionProvider = StreamProvider.autoDispose<Duration>((ref) {
  return ref.watch(playerControllerProvider.notifier).player.stream.position;
});

final playerDurationProvider = StreamProvider.autoDispose<Duration>((ref) {
  return ref.watch(playerControllerProvider.notifier).player.stream.duration;
});

final playerPlayingProvider = StreamProvider.autoDispose<bool>((ref) {
  return ref.watch(playerControllerProvider.notifier).player.stream.playing;
});

final playerBufferingProvider = StreamProvider.autoDispose<bool>((ref) {
  return ref.watch(playerControllerProvider.notifier).player.stream.buffering;
});

final playerTracksProvider = StreamProvider.autoDispose<Tracks>((ref) {
  final notifier = ref.watch(playerControllerProvider.notifier);
  return notifier.player.stream.tracks.startWith(notifier.tracks);
});

extension _SeedStream<T> on Stream<T> {
  Stream<T> startWith(T value) async* {
    yield value;
    yield* this;
  }
}
