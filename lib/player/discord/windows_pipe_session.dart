import 'dart:async';
import 'dart:io' show pid;
import 'dart:isolate';

import 'ipc_frame.dart';
import 'windows_pipe.dart';

class WindowsPipeSession {
  Isolate? _isolate;
  SendPort? _commands;
  ReceivePort? _events;
  StreamSubscription<dynamic>? _eventSub;

  Future<bool> connect(String clientId) async {
    final ready = ReceivePort();
    final isolate = await Isolate.spawn(_entry, ready.sendPort);
    _isolate = isolate;

    final commands = await ready.first as SendPort;
    _commands = commands;

    final events = ReceivePort();
    _events = events;

    final connected = Completer<bool>();
    _eventSub = events.listen((message) {
      if (message is Map && message['event'] == 'connected' && !connected.isCompleted) {
        connected.complete(message['ok'] as bool);
      }
    });

    commands.send({'cmd': 'connect', 'clientId': clientId, 'replyPort': events.sendPort});
    final ok = await connected.future.timeout(const Duration(seconds: 5), onTimeout: () => false);
    if (!ok) close();
    return ok;
  }

  void send(Map<String, dynamic>? activity) {
    _commands?.send({'cmd': 'activity', 'activity': activity});
  }

  void close() {
    _commands?.send({'cmd': 'close'});
    unawaited(_eventSub?.cancel());
    _events?.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _commands = null;
    _events = null;
    _eventSub = null;
  }

  static void _entry(SendPort mainPort) {
    final commands = ReceivePort();
    mainPort.send(commands.sendPort);

    WindowsPipeTransport? transport;

    commands.listen((message) {
      if (message is! Map) return;
      switch (message['cmd']) {
        case 'connect':
          final replyPort = message['replyPort'] as SendPort;
          final clientId = message['clientId'] as String;
          final t = WindowsPipeTransport();
          var ok = t.connect();
          if (ok) {
            ok = t.write(encodeFrame(0, {'v': 1, 'client_id': clientId})) && t.read(4096) != null;
          }
          if (ok) {
            transport = t;
          } else {
            t.close();
          }
          replyPort.send({'event': 'connected', 'ok': ok});
        case 'activity':
          transport?.write(
            encodeFrame(1, {
              'cmd': 'SET_ACTIVITY',
              'args': {'pid': pid, 'activity': message['activity']},
              'nonce': DateTime.now().microsecondsSinceEpoch.toString(),
            }),
          );
        case 'close':
          transport?.close();
          transport = null;
      }
    });
  }
}
