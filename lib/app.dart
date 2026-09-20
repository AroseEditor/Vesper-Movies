import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'design/theme.dart';
import 'shell/router.dart';

class VesperApp extends StatefulWidget {
  const VesperApp({super.key});

  @override
  State<VesperApp> createState() => _VesperAppState();
}

class _VesperAppState extends State<VesperApp> {
  late final GoRouter _router = buildRouter();

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
