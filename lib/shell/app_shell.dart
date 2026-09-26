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
  final FocusScopeNode _railScope = FocusScopeNode(debugLabel: 'rail');
  final FocusScopeNode _bodyScope = FocusScopeNode(debugLabel: 'body');

  @override
  void dispose() {
    _railScope.dispose();
    _bodyScope.dispose();
    super.dispose();
  }

  KeyEventResult _bodyKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.arrowLeft) {
      return KeyEventResult.ignored;
    }
    final focused = FocusManager.instance.primaryFocus;
    if (focused == null || !focused.focusInDirection(TraversalDirection.left)) {
      _railScope.requestFocus();
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _railKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.ignored;
    }
    _bodyScope.requestFocus();
    return KeyEventResult.handled;
  }

  void _back(InputMode mode) {
    if (mode.isTv && !_railScope.hasFocus) {
      _railScope.requestFocus();
      return;
    }
    if (widget.navigationShell.currentIndex != 0) {
      _select(0);
      return;
    }
    SystemNavigator.pop();
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

    FocusManager.instance.highlightStrategy = mode.isTv
        ? FocusHighlightStrategy.alwaysTraditional
        : FocusHighlightStrategy.automatic;

    final body = widget.navigationShell;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: VesperColors.canvas,
      ),
      child: InputModeScope(
        mode: mode,
        child: PopScope(
          canPop: !mode.isTv && widget.navigationShell.currentIndex == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _back(mode);
          },
          child: Scaffold(
            backgroundColor: VesperColors.canvas,
            body: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: mode.usesRail ? SideRail.collapsedWidthFor(mode) : 0,
                    ),
                    child: FocusScope(
                      node: _bodyScope,
                      child: Focus(
                        canRequestFocus: false,
                        skipTraversal: true,
                        onKeyEvent: mode.usesRail ? _bodyKey : null,
                        child: body,
                      ),
                    ),
                  ),
                ),
                if (mode.usesRail)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Focus(
                      canRequestFocus: false,
                      skipTraversal: true,
                      onKeyEvent: _railKey,
                      child: SideRail(
                        currentIndex: widget.navigationShell.currentIndex,
                        onSelect: _select,
                        mode: mode,
                        scope: _railScope,
                      ),
                    ),
                  )
                else
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
