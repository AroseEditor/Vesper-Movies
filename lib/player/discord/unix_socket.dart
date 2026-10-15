import 'dart:async';
import 'dart:io';

import 'ipc_frame.dart';

String? _findSocketPath() {
  final candidates = [
    Platform.environment['XDG_RUNTIME_DIR'],
    Platform.environment['TMPDIR'],
    Platform.environment['TMP'],
    Platform.environment['TEMP'],
    '/tmp',
  ];

  for (final dir in candidates) {
    if (dir == null || dir.isEmpty) continue;
    for (var i = 0; i < 10; i++) {
      final candidate = '$dir/discord-ipc-$i';
      if (File(candidate).existsSync()) return candidate;
    }
  }
  return null;
}

class UnixSocketSession {
  Socket? _socket;

  Future<bool> connect(String clientId) async {
    final path = _findSocketPath();
    if (path == null) return false;

    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      ).timeout(const Duration(seconds: 3));

      socket.add(encodeFrame(0, {'v': 1, 'client_id': clientId}));
      await socket.flush();
      await socket.first.timeout(const Duration(seconds: 3));

      _socket = socket;
      return true;
    } on Object {
      unawaited(socket?.close());
      return false;
    }
  }

  void send(Map<String, dynamic>? activity) {
    final socket = _socket;
    if (socket == null) return;
    socket.add(
      encodeFrame(1, {
        'cmd': 'SET_ACTIVITY',
        'args': {'pid': pid, 'activity': activity},
        'nonce': DateTime.now().microsecondsSinceEpoch.toString(),
      }),
    );
  }

  void close() {
    final socket = _socket;
    _socket = null;
    unawaited(socket?.close());
  }
}
