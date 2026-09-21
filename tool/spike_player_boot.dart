import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

final File _report = File('spike_boot.txt');

void _note(String line) {
  try {
    _report.writeAsStringSync('$line\n', mode: FileMode.append);
  } on Object catch (_) {
    return;
  }
}

Future<void> _probe() async {
  _note('runApp reached');
  try {
    final player = Player();
    _note('player constructed');
    await player.open(Media('https://127.0.0.1:1/none.mp4'), play: false);
    _note('open returned');
    await player.dispose();
    _note('player disposed');
  } on Object catch (error) {
    _note('player error: $error');
  }
  _note('done');
  exit(0);
}

void main() {
  try {
    _report.writeAsStringSync('start\n');
  } on Object catch (_) {
    return;
  }
  WidgetsFlutterBinding.ensureInitialized();
  _note('binding ready');
  MediaKit.ensureInitialized();
  _note('mediakit ready');
  runApp(const _BootApp());
  _probe();
}

class _BootApp extends StatelessWidget {
  const _BootApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        backgroundColor: Color(0xFF141414),
        body: SizedBox.shrink(),
      ),
    );
  }
}
