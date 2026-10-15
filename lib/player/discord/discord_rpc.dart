import 'dart:io';

import 'unix_socket.dart';
import 'windows_pipe_session.dart';

bool get discordRpcAvailable => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

class DiscordSession {
  WindowsPipeSession? _windows;
  UnixSocketSession? _unix;

  bool get isConnected => _windows != null || _unix != null;

  Future<bool> connect(String clientId) async {
    if (!discordRpcAvailable) return false;

    if (Platform.isWindows) {
      final session = WindowsPipeSession();
      final ok = await session.connect(clientId);
      _windows = ok ? session : null;
      return ok;
    }

    final session = UnixSocketSession();
    final ok = await session.connect(clientId);
    _unix = ok ? session : null;
    return ok;
  }

  void setActivity(Map<String, dynamic>? activity) {
    _windows?.send(activity);
    _unix?.send(activity);
  }

  void close() {
    _windows?.close();
    _unix?.close();
    _windows = null;
    _unix = null;
  }
}
