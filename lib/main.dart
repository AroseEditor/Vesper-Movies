import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/memo_cache.dart';
import 'core/secure_dns.dart';
import 'shell/input_mode.dart';
import 'sources/links/site_domains.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = SecureDnsHttpOverrides();
  MediaKit.ensureInitialized();

  startupInputMode = await detectInputMode();
  await MemoCache.openDisk();
  await SiteDomains.load();
  await StreamTunnel.loadPreference();
  await StreamTunnel.start();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
  }

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  AppLifecycleListener(onInactive: MemoCache.flushAll, onPause: MemoCache.flushAll);

  runApp(const ProviderScope(child: VesperApp()));
}
