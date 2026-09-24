import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;

import '../core/redact.dart';
import '../models/release.dart';
import 'language_prefs.dart';
import 'playback_engine.dart';
import 'quality_cap.dart';
import 'subtitle_style.dart';

const Duration preloadWindow = Duration(seconds: 60);
const Duration preloadDeadline = Duration(seconds: 30);

const _fatalMarkers = [
  'failed to open',
  'failed to recognize file format',
  'no video or audio streams',
  'errors when loading file',
];

bool isFatalPlaybackError(String text) {
  final lower = text.toLowerCase();
  if (lower.contains('external file') || lower.contains('subtitle')) return false;
  return _fatalMarkers.any(lower.contains);
}

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

typedef Chapter = EngineChapter;

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
  PlaybackEngine? _engine;
  StreamSubscription<String>? _errorSubscription;
  StreamSubscription<Duration>? _startSubscription;
  Timer? _preloadDeadline;
  Timer? _preloadPoll;
  int _session = 0;

  PlaybackEngine get engine => _engine ??= PlaybackEngine.create();

  @override
  PlayerState build() {
    ref.listen(qualityCapProvider, (_, cap) => unawaited(_engine?.setMaxHeight(cap.maxHeight)));
    ref.onDispose(() {
      _stopPreloadTimers();
      unawaited(_errorSubscription?.cancel());
      unawaited(_startSubscription?.cancel());
      unawaited(_engine?.dispose());
      _engine = null;
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

  List<SubtitleOption> _subtitlesFor(PlaybackTarget target) {
    final options = [...target.source.subtitles];
    final fallback = target.source.subtitle;
    if (fallback != null && fallback.isNotEmpty && options.every((o) => o.url != fallback)) {
      options.add(SubtitleOption(name: 'Default', url: fallback));
    }
    return options;
  }

  Future<void> load(PlaybackTarget target) async {
    final session = ++_session;
    _stopPreloadTimers();
    final subtitles = _subtitlesFor(target);
    state = state.copyWith(
      target: target,
      externalSubtitles: subtitles,
      isReady: false,
      clearError: true,
      clearActiveExternal: true,
    );

    _errorSubscription ??= engine.errorStream.listen((message) {
      debugPrint('playback error: ${redactLog(message)}');
      if (!isFatalPlaybackError(message)) return;
      if (!engine.errorsAreTerminal && engine.state.duration > Duration.zero) return;
      state = state.copyWith(error: message, isReady: false);
    });

    debugPrint('playback open ${redactUrl(target.source.url)} at ${target.startAt.inSeconds}s');
    await engine.open(
      url: target.source.url,
      headers: target.source.headers,
      start: target.startAt,
      subtitles: subtitles,
      maxHeight: ref.read(qualityCapProvider).maxHeight,
    );

    await applySubtitleStyle(state.subtitleStyle);

    await _startSubscription?.cancel();
    _startSubscription = engine.durationStream.where((d) => d > Duration.zero).take(1).listen((_) {
      if (session != _session) return;
      unawaited(_afterStart(target, session));
    });

    if (session != _session) return;
    state = state.copyWith(isReady: true);
    _gatePreload(session);
  }

  Future<void> _afterStart(PlaybackTarget target, int session) async {
    unawaited(
      applyPreferredTracks(session).catchError((Object error) {
        debugPrint('track preferences failed: $error');
      }),
    );

    final resume = target.startAt;
    if (resume <= const Duration(seconds: 5)) return;
    await Future<void>.delayed(const Duration(seconds: 2));
    if (session != _session) return;
    if (engine.state.position < const Duration(seconds: 3)) {
      debugPrint('playback resume re-seek to ${resume.inSeconds}s');
      await engine.seek(resume);
    }
  }

  void _gatePreload(int session) {
    if (!engine.needsStartBuffer) {
      unawaited(engine.play());
      return;
    }

    state = state.copyWith(preload: const Preload(active: true, target: preloadWindow));

    _preloadDeadline = Timer(preloadDeadline, () => unawaited(_releasePreload()));
    _preloadPoll = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (session != _session) {
        _stopPreloadTimers();
        return;
      }
      unawaited(_pollPreload());
    });
  }

  bool _polling = false;

  Future<void> _pollPreload() async {
    if (_polling || !state.preload.active) return;
    _polling = true;
    try {
      final (buffered, idle) = await engine.bufferedAhead();
      final remaining = engine.state.duration - engine.state.position;
      final goal = remaining > Duration.zero && remaining < preloadWindow
          ? remaining
          : preloadWindow;

      if (!state.preload.active) return;
      state = state.copyWith(
        preload: Preload(active: true, buffered: buffered, target: goal),
      );

      final full = idle && buffered > const Duration(seconds: 5);
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
    await engine.play();
  }

  Future<void> skipPreload() => _releasePreload();

  Future<void> selectExternalSubtitle(SubtitleOption option, {bool remember = false}) async {
    await engine.setSubtitleTrack(SubtitleTrack.uri(option.url, title: option.name));
    state = state.copyWith(activeExternal: option.url);
    if (remember) {
      await ref.read(languagePrefsProvider.notifier).rememberSubtitle(languageKey(option.name));
    }
  }

  Future<void> clearSubtitles() async {
    await engine.setSubtitleTrack(SubtitleTrack.no());
    state = state.copyWith(clearActiveExternal: true);
    await ref.read(languagePrefsProvider.notifier).rememberSubtitle(null);
  }

  Future<bool> waitUntilPlayable(Duration timeout) async {
    if (state.error != null) return false;
    if (engine.state.duration > Duration.zero) return true;

    final completer = Completer<bool>();
    final subs = <StreamSubscription<Object>>[
      engine.durationStream.listen((value) {
        if (value > Duration.zero && !completer.isCompleted) completer.complete(true);
      }),
      engine.errorStream.listen((message) {
        if (isFatalPlaybackError(message) && !completer.isCompleted) completer.complete(false);
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

  static bool _isReal(String id) => id != 'auto' && id != 'no';

  Future<void> applyPreferredTracks(int session) async {
    final prefs = ref.read(languagePrefsProvider);

    var tracks = engine.state.tracks;
    if (tracks.audio.length <= 2 && tracks.subtitle.length <= 2) {
      tracks = await engine.tracksStream
          .firstWhere((t) => t.audio.length > 2 || t.subtitle.length > 2)
          .timeout(const Duration(seconds: 4), onTimeout: () => engine.state.tracks);
    }
    if (session != _session) return;

    final realAudio = [
      for (final t in tracks.audio)
        if (_isReal(t.id)) t,
    ];
    String? audioKey;
    final audioPref = prefs.audio;
    if (audioPref != null) {
      for (final track in realAudio) {
        if (languageKey(track.language, track.title) == audioPref) {
          await engine.setAudioTrack(track);
          audioKey = audioPref;
          break;
        }
      }
    }
    if (audioKey == null) {
      final selected = engine.state.track.audio;
      final active = _isReal(selected.id) ? selected : realAudio.firstOrNull;
      if (active != null) audioKey = languageKey(active.language, active.title);
    }

    if (prefs.subtitlesOff) {
      await engine.setSubtitleTrack(SubtitleTrack.no());
      state = state.copyWith(clearActiveExternal: true);
      return;
    }

    final embedded = [
      for (final t in tracks.subtitle)
        if (_isReal(t.id)) t,
    ];
    final external = state.externalSubtitles;

    final subPref = prefs.subtitle;
    if (subPref != null) {
      for (final track in embedded) {
        if (languageKey(track.language, track.title) == subPref) {
          await engine.setSubtitleTrack(track);
          state = state.copyWith(clearActiveExternal: true);
          return;
        }
      }
      for (final option in external) {
        if (languageKey(option.name) == subPref) {
          await selectExternalSubtitle(option);
          return;
        }
      }
    }

    if (_isReal(engine.state.track.subtitle.id) || audioKey == 'en') return;

    final embeddedEnglish = embedded.where((t) => languageKey(t.language, t.title) == 'en');
    final track = embeddedEnglish.firstOrNull ?? embedded.firstOrNull;
    if (track != null) {
      await engine.setSubtitleTrack(track);
      state = state.copyWith(clearActiveExternal: true);
      return;
    }

    final externalEnglish = external.where((o) => languageKey(o.name) == 'en');
    final option = externalEnglish.firstOrNull ?? external.firstOrNull;
    if (option != null) await selectExternalSubtitle(option);
  }

  Future<List<Chapter>> chapters() => engine.chapters();

  Tracks get tracks => engine.state.tracks;

  Future<void> applySubtitleStyle(SubtitleStyle style) async {
    state = state.copyWith(subtitleStyle: style);
    await engine.applySubtitleStyle(style);
  }

  Future<void> togglePlay() async {
    if (state.preload.active) {
      await _releasePreload();
      return;
    }
    await engine.playOrPause();
  }

  Future<void> seekBy(Duration delta) async {
    final position = engine.state.position + delta;
    final duration = engine.state.duration;
    final clamped = position < Duration.zero
        ? Duration.zero
        : (duration > Duration.zero && position > duration ? duration : position);
    await engine.seek(clamped);
  }

  Future<void> seekTo(Duration position) => engine.seek(position);

  Future<void> setVolume(double volume) => engine.setVolume(volume.clamp(0, 100));

  Future<void> nudgeVolume(double delta) => setVolume(engine.state.volume + delta);

  Future<void> toggleMute() => engine.setVolume(engine.state.volume > 0 ? 0 : 100);

  Future<void> setSpeed(double rate) => engine.setRate(rate.clamp(0.25, 3.0));

  Future<void> nudgeSpeed(double delta) => setSpeed(engine.state.rate + delta);

  Future<void> selectAudio(AudioTrack track) async {
    await engine.setAudioTrack(track);
    await ref
        .read(languagePrefsProvider.notifier)
        .rememberAudio(languageKey(track.language, track.title));
  }

  Future<void> selectSubtitle(SubtitleTrack track) async {
    await engine.setSubtitleTrack(track);
    state = state.copyWith(clearActiveExternal: true);
    final prefs = ref.read(languagePrefsProvider.notifier);
    if (track.id == 'no') {
      await prefs.rememberSubtitle(null);
    } else {
      final key = languageKey(track.language, track.title);
      if (key != null) await prefs.rememberSubtitle(key);
    }
  }

  Future<void> selectVideo(VideoTrack track) => engine.setVideoTrack(track);

  Future<void> nudgeSubtitleDelay(int deltaMs) =>
      applySubtitleStyle(state.subtitleStyle.nudgeDelay(deltaMs));

  Future<void> stop() async {
    _session++;
    _stopPreloadTimers();
    await engine.stop();
    state = const PlayerState();
  }
}

final playerControllerProvider = NotifierProvider<PlayerControllerNotifier, PlayerState>(
  PlayerControllerNotifier.new,
);

final playerPositionProvider = StreamProvider.autoDispose<Duration>((ref) {
  return ref.watch(playerControllerProvider.notifier).engine.positionStream;
});

final playerDurationProvider = StreamProvider.autoDispose<Duration>((ref) {
  final engine = ref.watch(playerControllerProvider.notifier).engine;
  return engine.durationStream.startWith(engine.state.duration);
});

final playerPlayingProvider = StreamProvider.autoDispose<bool>((ref) {
  final engine = ref.watch(playerControllerProvider.notifier).engine;
  return engine.playingStream.startWith(engine.state.playing);
});

final playerBufferingProvider = StreamProvider.autoDispose<bool>((ref) {
  return ref.watch(playerControllerProvider.notifier).engine.bufferingStream;
});

final playerTracksProvider = StreamProvider.autoDispose<Tracks>((ref) {
  final notifier = ref.watch(playerControllerProvider.notifier);
  return notifier.engine.tracksStream.startWith(notifier.tracks);
});

final playerTrackProvider = StreamProvider.autoDispose<Track>((ref) {
  final engine = ref.watch(playerControllerProvider.notifier).engine;
  return engine.trackStream.startWith(engine.state.track);
});

final playerCuesProvider = StreamProvider.autoDispose<String>((ref) {
  return ref.watch(playerControllerProvider.notifier).engine.cueStream;
});

extension _SeedStream<T> on Stream<T> {
  Stream<T> startWith(T value) async* {
    yield value;
    yield* this;
  }
}
