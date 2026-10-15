import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'design/theme.dart';
import 'player/discord_presence.dart';
import 'shell/router.dart';

class VesperApp extends ConsumerStatefulWidget {
  const VesperApp({super.key});

  @override
  ConsumerState<VesperApp> createState() => _VesperAppState();
}

class _VesperAppState extends ConsumerState<VesperApp> {
  late final GoRouter _router = buildRouter();

  @override
  void initState() {
    super.initState();
    ref.read(discordPresenceProvider);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Vesper Movies',
      debugShowCheckedModeBanner: false,
      theme: VesperTheme.build(),
      routerConfig: _router,
    );
  }
}
