import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../design/colors.dart';
import '../design/icons.dart';
import '../design/motion.dart';
import '../design/typography.dart';
import '../design/widgets/glass_surface.dart';
import '../features/settings/settings_page.dart';
import 'destinations.dart';
import 'input_mode.dart';

class SideRail extends StatefulWidget {
  const SideRail({
    super.key,
    required this.currentIndex,
    required this.onSelect,
    required this.mode,
    this.scope,
    this.itemNodes,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;
  final InputMode mode;
  final FocusScopeNode? scope;
  final List<FocusNode>? itemNodes;

  static double collapsedWidthFor(InputMode mode) => mode.isTv ? 84.0 : 72.0;

  @override
  State<SideRail> createState() => _SideRailState();
}

class _SideRailState extends State<SideRail> {
  late final FocusScopeNode _scope = widget.scope ?? FocusScopeNode(debugLabel: 'rail');
  bool _expanded = false;

  double get _collapsedWidth => SideRail.collapsedWidthFor(widget.mode);

  double get _expandedWidth => widget.mode.isTv ? 268.0 : 232.0;

  double get _headerHeight {
    final top = widget.mode.isTv ? 34.0 : 22.0;
    final afterBrand = widget.mode.isTv ? 38.0 : 28.0;
    return top + 34.0 + afterBrand;
  }

  double get _itemSlotHeight => (widget.mode.isTv ? 56.0 : 48.0) + 4.0;

  double get _pillTop => _headerHeight + widget.currentIndex * _itemSlotHeight;

  @override
  void dispose() {
    if (widget.scope == null) _scope.dispose();
    super.dispose();
  }

  void _setExpanded(bool value) {
    if (_expanded == value || !mounted) return;
    setState(() => _expanded = value);
  }

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      node: _scope,
      onFocusChange: _setExpanded,
      child: MouseRegion(
        onEnter: (_) {
          if (widget.mode.usesPointer) _setExpanded(true);
        },
        onExit: (_) {
          if (widget.mode.usesPointer && !_scope.hasFocus) _setExpanded(false);
        },
        child: AnimatedContainer(
          duration: VesperMotion.normal,
          curve: VesperMotion.enter,
          width: _expanded ? _expandedWidth : _collapsedWidth,
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
          child: GlassSurface(
            shape: const LiquidRoundedSuperellipse(borderRadius: 26),
            raised: true,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: _expandedWidth - 16,
                maxWidth: _expandedWidth - 16,
                child: SafeArea(
                  right: false,
                  child: Stack(
                    children: [
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 500),
                        curve: VesperMotion.overshoot,
                        top: _pillTop,
                        left: 0,
                        width: _expandedWidth - 16,
                        height: _itemSlotHeight,
                        child: GlassSurface(
                          settings: VesperGlass.pill,
                          shape: LiquidRoundedSuperellipse(borderRadius: _itemSlotHeight / 2),
                          showRim: false,
                          child: const SizedBox.expand(),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(height: widget.mode.isTv ? 34 : 22),
                          _RailBrand(expanded: _expanded, iconSlot: _collapsedWidth - 8),
                          SizedBox(height: widget.mode.isTv ? 38 : 28),
                          for (var i = 0; i < AppDestination.values.length; i++)
                            _RailItem(
                              destination: AppDestination.values[i],
                              selected: i == widget.currentIndex,
                              focusNode: widget.itemNodes?[i],
                              expanded: _expanded,
                              iconSlot: _collapsedWidth - 8,
                              railWidth: _expandedWidth - 16,
                              tv: widget.mode.isTv,
                              onSelect: () => widget.onSelect(i),
                            ),
                          const Spacer(),
                          _RailAction(
                            icon: VesperIcons.settings,
                            label: 'Settings',
                            expanded: _expanded,
                            iconSlot: _collapsedWidth - 8,
                            tv: widget.mode.isTv,
                            onActivate: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(builder: (context) => const SettingsPage()),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RailBrand extends StatelessWidget {
  const _RailBrand({required this.expanded, required this.iconSlot});

  final bool expanded;
  final double iconSlot;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          SizedBox(
            width: iconSlot,
            child: Center(
              child: ShaderMask(
                shaderCallback: VesperColors.brandSweep.createShader,
                child: const Text(
                  'V',
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
          Flexible(
            child: AnimatedOpacity(
              opacity: expanded ? 1 : 0,
              duration: VesperMotion.fast,
              child: Text(
                'VESPER',
                style: VesperType.label.copyWith(
                  color: VesperColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.4,
                ),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  const _RailItem({
    required this.destination,
    required this.selected,
    required this.expanded,
    required this.iconSlot,
    required this.railWidth,
    required this.tv,
    required this.onSelect,
    this.focusNode,
  });

  final FocusNode? focusNode;
  final AppDestination destination;
  final bool selected;
  final bool expanded;
  final double iconSlot;
  final double railWidth;
  final bool tv;
  final VoidCallback onSelect;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _focused;
    final color = active ? VesperColors.textPrimary : VesperColors.textTertiary;
    final height = widget.tv ? 56.0 : 48.0;

    return FocusableActionDetector(
      focusNode: widget.focusNode,
      onShowFocusHighlight: (value) {
        if (_focused != value) setState(() => _focused = value);
      },
      mouseCursor: SystemMouseCursors.click,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onSelect();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelect,
        child: Semantics(
          label: widget.destination.label,
          selected: widget.selected,
          button: true,
          child: AnimatedContainer(
            duration: VesperMotion.fast,
            curve: VesperMotion.enter,
            height: height,
            width: widget.railWidth,
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: _focused && !widget.selected
                  ? VesperColors.surfaceRaised.withValues(alpha: 0.5)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(height / 2),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: widget.iconSlot - 3,
                  child: Icon(
                    widget.selected ? widget.destination.activeIcon : widget.destination.icon,
                    color: widget.selected ? VesperColors.accent : color,
                    size: widget.tv ? 26 : 22,
                  ),
                ),
                Flexible(
                  child: AnimatedOpacity(
                    opacity: widget.expanded ? 1 : 0,
                    duration: VesperMotion.fast,
                    child: Text(
                      widget.destination.label,
                      style: VesperType.bodyStrong.copyWith(
                        color: color,
                        fontSize: widget.tv ? 17 : 15,
                        fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
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

class _RailAction extends StatefulWidget {
  const _RailAction({
    required this.icon,
    required this.label,
    required this.expanded,
    required this.iconSlot,
    required this.tv,
    required this.onActivate,
  });

  final IconData icon;
  final String label;
  final bool expanded;
  final double iconSlot;
  final bool tv;
  final VoidCallback onActivate;

  @override
  State<_RailAction> createState() => _RailActionState();
}

class _RailActionState extends State<_RailAction> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final color = _focused ? VesperColors.textPrimary : VesperColors.textTertiary;

    return FocusableActionDetector(
      onShowFocusHighlight: (value) {
        if (_focused != value) setState(() => _focused = value);
      },
      mouseCursor: SystemMouseCursors.click,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onActivate();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onActivate,
        child: Semantics(
          label: widget.label,
          button: true,
          child: Container(
            height: widget.tv ? 52 : 46,
            color: _focused ? VesperColors.surfaceRaised : Colors.transparent,
            child: Row(
              children: [
                SizedBox(
                  width: widget.iconSlot,
                  child: Icon(widget.icon, size: widget.tv ? 24 : 21, color: color),
                ),
                Flexible(
                  child: AnimatedOpacity(
                    opacity: widget.expanded ? 1 : 0,
                    duration: VesperMotion.fast,
                    child: Text(
                      widget.label,
                      style: VesperType.bodyStrong.copyWith(color: color, fontSize: 15),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
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
