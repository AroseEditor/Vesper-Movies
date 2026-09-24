import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

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

typedef ExternalProgress = void Function(Duration position, Duration duration);

ExternalProgress? _androidProgress;

Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

String _randomToken() {
  final random = Random.secure();
  return List.generate(24, (_) => random.nextInt(16).toRadixString(16)).join();
}

Future<void> _pollVlc(Process process, int port, String token, ExternalProgress report) async {
  var exited = false;
  unawaited(process.exitCode.then((_) => exited = true));
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  final auth = 'Basic ${base64Encode(utf8.encode(':$token'))}';
  final address = Uri.parse('http://127.0.0.1:$port/requests/status.json');
  try {
    while (!exited) {
      await Future<void>.delayed(const Duration(seconds: 3));
      try {
        final request = await client.getUrl(address);
        request.headers.set(HttpHeaders.authorizationHeader, auth);
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        if (response.statusCode != 200) continue;
        final data = jsonDecode(body);
        if (data is! Map || data['state'] == 'stopped') continue;
        final time = data['time'];
        final length = data['length'];
        if (time is num && length is num && length > 0 && time >= 0) {
          report(Duration(seconds: time.toInt()), Duration(seconds: length.toInt()));
        }
      } on Object {
        continue;
      }
    }
  } finally {
    client.close(force: true);
  }
}

Future<bool> openInVlc(
  PlaybackSource source, {
  required String title,
  Duration start = Duration.zero,
  ExternalProgress? onProgress,
}) async {
  if (Platform.isAndroid) {
    _androidProgress = onProgress;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'vlcResult') return;
      final args = call.arguments;
      if (args is! Map) return;
      final position = args['position'];
      final duration = args['duration'];
      if (position is num && duration is num && duration > 0) {
        _androidProgress?.call(
          Duration(milliseconds: position.toInt()),
          Duration(milliseconds: duration.toInt()),
        );
      }
    });
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
  final port = onProgress == null ? 0 : await _freePort();
  final token = _randomToken();
  final arguments = [
    source.url,
    '--meta-title=$title',
    if (headers['Referer'] != null) '--http-referrer=${headers['Referer']}',
    if (headers['User-Agent'] != null) '--http-user-agent=${headers['User-Agent']}',
    if (start > const Duration(seconds: 5)) '--start-time=${start.inSeconds}',
    '--no-video-title-show',
    if (onProgress != null) ...[
      '--extraintf=http',
      '--http-host=127.0.0.1',
      '--http-port=$port',
      '--http-password=$token',
    ],
  ];
  try {
    final process = await Process.start(executable, arguments);
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    if (onProgress != null) unawaited(_pollVlc(process, port, token, onProgress));
    return true;
  } on Object {
    return false;
  }
}
