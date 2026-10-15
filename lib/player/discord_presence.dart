import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/details/playback_session.dart';
import 'discord/discord_rpc.dart';
import 'player_controller.dart';

const _clientId = String.fromEnvironment('DISCORD_CLIENT_ID');
const _repoUrl = 'https://github.com/AroseEditor/Vesper-Movies';
const _logoUrl = 'https://raw.githubusercontent.com/AroseEditor/Vesper-Movies/main/assets/icon.png';
const _buttons = [
  {'label': 'View on GitHub', 'url': _repoUrl},
];

const _enabledKey = 'pref.discord_presence_enabled';

class DiscordPresenceEnabledNotifier extends Notifier<bool> {
  @override
  bool build() {
    unawaited(_load());
    return true;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(_enabledKey) ?? true;
    } on Object {
      return;
    }
  }

  Future<void> toggle() async {
    state = !state;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, state);
    } on Object {
      return;
    }
  }
}

final discordPresenceEnabledProvider = NotifierProvider<DiscordPresenceEnabledNotifier, bool>(
  DiscordPresenceEnabledNotifier.new,
);

class DiscordPresenceController {
  DiscordPresenceController(this._ref) {
    if (!discordRpcAvailable || _clientId.isEmpty) return;
    _ref.listen<PlaybackSession?>(
      playbackSessionProvider,
      (_, session) => _onSessionChanged(session),
    );
    _ref.listen(playerDurationProvider, (_, duration) => _onDurationChanged(duration.value));
    _ref.listen(playerPlayingProvider, (_, playing) => unawaited(_refresh()));
    _ref.listen(
      discordPresenceEnabledProvider,
      (_, enabled) => unawaited(_onEnabledChanged(enabled)),
    );
    if (_ref.read(discordPresenceEnabledProvider)) unawaited(_refresh());
  }

  final Ref _ref;
  final DiscordSession _session = DiscordSession();
  String? _sessionKey;
  bool _connecting = false;

  Future<bool> _ensureConnected() async {
    if (_session.isConnected) return true;
    if (_connecting) return false;

    _connecting = true;
    try {
      return await _session.connect(_clientId);
    } finally {
      _connecting = false;
    }
  }

  Future<void> _onEnabledChanged(bool enabled) async {
    if (enabled) {
      unawaited(_refresh());
      return;
    }
    _session.setActivity(null);
    _session.close();
  }

  void _onSessionChanged(PlaybackSession? session) {
    final key = session == null
        ? null
        : '${session.item.id.value}:${session.season}:${session.episode}';
    if (key == _sessionKey) return;
    _sessionKey = key;
    unawaited(_refresh());
  }

  void _onDurationChanged(Duration? duration) {
    if (duration == null || duration <= Duration.zero) return;
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (!_ref.read(discordPresenceEnabledProvider)) return;
    if (!await _ensureConnected()) return;

    final session = _ref.read(playbackSessionProvider);
    if (session == null) {
      _session.setActivity(_browsingActivity());
      return;
    }

    final duration = _ref.read(playerDurationProvider).value ?? Duration.zero;
    if (duration <= Duration.zero) return;

    final position = _ref.read(playerPositionProvider).value ?? Duration.zero;
    final playing = _ref.read(playerPlayingProvider).value ?? false;
    _session.setActivity(_watchingActivity(session, position, duration, playing));
  }

  Map<String, dynamic> _browsingActivity() => {
    'type': 3,
    'details': 'Browsing the catalog',
    'assets': {'large_image': _logoUrl, 'large_text': 'Vesper Movies'},
    'buttons': _buttons,
  };

  Map<String, dynamic> _watchingActivity(
    PlaybackSession session,
    Duration position,
    Duration duration,
    bool playing,
  ) {
    final image = session.item.backdropUrl ?? session.item.posterUrl ?? _logoUrl;
    final episodeLabel = session.isEpisode ? session.episodeLabel : null;

    final activity = <String, dynamic>{
      'type': 3,
      'details': session.title,
      'assets': {
        'large_image': image,
        'large_text': session.title,
        'small_image': _logoUrl,
        'small_text': 'Vesper Movies',
      },
      'buttons': _buttons,
    };

    if (!playing) {
      activity['state'] = episodeLabel == null ? 'Paused' : '$episodeLabel · Paused';
      return activity;
    }

    activity['state'] = episodeLabel;
    final start = DateTime.now().subtract(position);
    activity['timestamps'] = {
      'start': start.millisecondsSinceEpoch ~/ 1000,
      'end': start.add(duration).millisecondsSinceEpoch ~/ 1000,
    };
    return activity;
  }

  void dispose() {
    _session.setActivity(null);
    _session.close();
  }
}

final discordPresenceProvider = Provider<DiscordPresenceController>((ref) {
  final controller = DiscordPresenceController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});
