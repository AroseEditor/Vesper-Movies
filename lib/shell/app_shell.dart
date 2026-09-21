import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/update_check.dart';
import '../design/colors.dart';
import 'bottom_dock.dart';
import 'input_mode.dart';
import 'side_rail.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(inputModeProvider.notifier).resolve();
    });
  }

  void _select(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  bool _updateNoticeShown = false;

  void _announceUpdate(UpdateInfo? info) {
    if (_updateNoticeShown || info == null || !info.isNewer || !mounted) return;
    _updateNoticeShown = true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 10),
        backgroundColor: VesperColors.surfaceRaised,
        content: Text('Vesper ${info.latest} is available.'),
        action: SnackBarAction(
          label: 'Get it',
          textColor: VesperColors.accent,
          onPressed: () => launchUrl(Uri.parse(info.url), mode: LaunchMode.externalApplication),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(inputModeProvider);
    ref.listen(updateCheckProvider, (_, next) => _announceUpdate(next.value));

    if (mode.isTv) {
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    }

    final body = widget.navigationShell;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: VesperColors.canvas,
      ),
      child: InputModeScope(
        mode: mode,
        child: PopScope(
          canPop: widget.navigationShell.currentIndex == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && widget.navigationShell.currentIndex != 0) {
              _select(0);
            }
          },
          child: Scaffold(
            backgroundColor: VesperColors.canvas,
            body: mode.usesRail
                ? Row(
                    children: [
                      SideRail(
                        currentIndex: widget.navigationShell.currentIndex,
                        onSelect: _select,
                        mode: mode,
                      ),
                      Expanded(child: body),
                    ],
                  )
                : Stack(
                    children: [
                      Positioned.fill(child: body),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: BottomDock(
                          currentIndex: widget.navigationShell.currentIndex,
                          onSelect: _select,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
