import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/release.dart';

enum PlayerChoice {
  builtIn('Vesper player'),
  vlc('VLC media player');

  const PlayerChoice(this.label);

  final String label;
}

const _prefsKey = 'pref.player_choice';

class PlayerChoiceNotifier extends Notifier<PlayerChoice> {
  @override
  PlayerChoice build() {
    unawaited(_load());
    return PlayerChoice.builtIn;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString(_prefsKey);
      for (final value in PlayerChoice.values) {
        if (value.name == name) state = value;
      }
    } on Object {
      return;
    }
  }

  Future<void> set(PlayerChoice value) async {
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, value.name);
    } on Object {
      return;
    }
  }

  void cycle() {
    const values = PlayerChoice.values;
    unawaited(set(values[(values.indexOf(state) + 1) % values.length]));
  }
}

final playerChoiceProvider = NotifierProvider<PlayerChoiceNotifier, PlayerChoice>(
  PlayerChoiceNotifier.new,
);

const _channel = MethodChannel('vesper/external');

bool vlcCanPlay(PlaybackSource source) {
  if (source.url.startsWith('data:')) return false;
  if (Platform.isAndroid && source.headers.containsKey('Referer') && source.isHls) return false;
  return true;
}

String? _windowsVlc() {
  final roots = [
    Platform.environment['ProgramFiles'],
    Platform.environment['ProgramFiles(x86)'],
    Platform.environment['LOCALAPPDATA'] == null
        ? null
        : '${Platform.environment['LOCALAPPDATA']}\\Programs',
  ];
  for (final root in roots) {
    if (root == null) continue;
    final path = '$root\\VideoLAN\\VLC\\vlc.exe';
    if (File(path).existsSync()) return path;
  }
  return null;
}

Future<bool> openInVlc(
  PlaybackSource source, {
  required String title,
  Duration start = Duration.zero,
}) async {
  if (Platform.isAndroid) {
    try {
      final opened = await _channel.invokeMethod<bool>('openVlc', {
        'url': source.url,
        'title': title,
        'positionMs': start.inMilliseconds,
      });
      return opened ?? false;
    } on PlatformException {
      return false;
    }
  }

  final executable = Platform.isWindows ? _windowsVlc() : 'vlc';
  if (executable == null) return false;

  final headers = source.headers;
  final arguments = [
    source.url,
    '--meta-title=$title',
    if (headers['Referer'] != null) '--http-referrer=${headers['Referer']}',
    if (headers['User-Agent'] != null) '--http-user-agent=${headers['User-Agent']}',
    if (start > const Duration(seconds: 5)) '--start-time=${start.inSeconds}',
    '--no-video-title-show',
  ];
  try {
    await Process.start(executable, arguments, mode: ProcessStartMode.detached);
    return true;
  } on Object {
    return false;
  }
}
