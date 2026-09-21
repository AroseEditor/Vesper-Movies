import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/release.dart';
import 'subtitle_style.dart';

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

class PlayerState {
  const PlayerState({
    this.target,
    this.subtitleStyle = SubtitleStyle.defaults,
    this.externalSubtitles = const [],
    this.activeExternal,
    this.isReady = false,
    this.error,
  });

  final PlaybackTarget? target;
  final SubtitleStyle subtitleStyle;
  final List<SubtitleOption> externalSubtitles;
  final String? activeExternal;
  final bool isReady;
  final String? error;

  PlayerState copyWith({
    PlaybackTarget? target,
    SubtitleStyle? subtitleStyle,
    List<SubtitleOption>? externalSubtitles,
    String? activeExternal,
    bool clearActiveExternal = false,
    bool? isReady,
    String? error,
    bool clearError = false,
  }) {
    return PlayerState(
      target: target ?? this.target,
      subtitleStyle: subtitleStyle ?? this.subtitleStyle,
      externalSubtitles: externalSubtitles ?? this.externalSubtitles,
      activeExternal: clearActiveExternal ? null : (activeExternal ?? this.activeExternal),
      isReady: isReady ?? this.isReady,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class PlayerControllerNotifier extends Notifier<PlayerState> {
  Player? _player;
  VideoController? _videoController;
  StreamSubscription<String>? _errorSubscription;

  Player get player => _player ??= Player(
    configuration: const PlayerConfiguration(title: 'Vesper Movies', bufferSize: 256 * 1024 * 1024),
  );

  VideoController get videoController => _videoController ??= VideoController(player);

  @override
  PlayerState build() {
    ref.onDispose(() {
      unawaited(_errorSubscription?.cancel());
      unawaited(_player?.dispose());
      _player = null;
      _videoController = null;
    });
    return const PlayerState();
  }

  Future<void> load(PlaybackTarget target) async {
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
      play: true,
    );

    await applySubtitleStyle(state.subtitleStyle);

    final external = target.subtitle ?? target.source.subtitle;
    if (external != null && external.isNotEmpty) {
      await selectExternalSubtitle(SubtitleOption(name: 'Default', url: external));
    }

    state = state.copyWith(isReady: true);
  }

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
  }

  Future<void> selectExternalSubtitle(SubtitleOption option) async {
    await player.setSubtitleTrack(SubtitleTrack.uri(option.url, title: option.name));
    state = state.copyWith(activeExternal: option.url);
  }

  Future<void> clearSubtitles() async {
    await player.setSubtitleTrack(SubtitleTrack.no());
    state = state.copyWith(clearActiveExternal: true);
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

  Future<void> togglePlay() => player.playOrPause();

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

  Future<void> selectAudio(AudioTrack track) => player.setAudioTrack(track);

  Future<void> selectSubtitle(SubtitleTrack track) async {
    await player.setSubtitleTrack(track);
    state = state.copyWith(clearActiveExternal: true);
  }

  Future<void> selectVideo(VideoTrack track) => player.setVideoTrack(track);

  Future<void> nudgeSubtitleDelay(int deltaMs) =>
      applySubtitleStyle(state.subtitleStyle.nudgeDelay(deltaMs));

  Future<void> stop() async {
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
