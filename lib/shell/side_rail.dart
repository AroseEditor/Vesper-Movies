import 'package:flutter/material.dart';

import '../design/colors.dart';
import '../design/motion.dart';
import '../design/typography.dart';
import 'destinations.dart';
import 'input_mode.dart';

class SideRail extends StatefulWidget {
  const SideRail({
    super.key,
    required this.currentIndex,
    required this.onSelect,
    required this.mode,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;
  final InputMode mode;

  @override
  State<SideRail> createState() => _SideRailState();
}

class _SideRailState extends State<SideRail> {
  final FocusScopeNode _scope = FocusScopeNode(debugLabel: 'rail');
  bool _expanded = false;

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  void _setExpanded(bool value) {
    if (_expanded == value) return;
    setState(() => _expanded = value);
  }

  @override
  Widget build(BuildContext context) {
    final collapsed = widget.mode.isTv ? 84.0 : 72.0;
    final expanded = widget.mode.isTv ? 268.0 : 232.0;

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
          width: _expanded ? expanded : collapsed,
          decoration: BoxDecoration(
            color: VesperColors.canvasDeep,
            border: Border(
              right: BorderSide(color: _expanded ? VesperColors.divider : Colors.transparent),
            ),
          ),
          child: SafeArea(
            right: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: widget.mode.isTv ? 34 : 22),
                _RailBrand(expanded: _expanded, collapsedWidth: collapsed),
                SizedBox(height: widget.mode.isTv ? 38 : 28),
                for (var i = 0; i < AppDestination.values.length; i++)
                  _RailItem(
                    destination: AppDestination.values[i],
                    selected: i == widget.currentIndex,
                    expanded: _expanded,
                    collapsedWidth: collapsed,
                    tv: widget.mode.isTv,
                    onSelect: () => widget.onSelect(i),
                  ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RailBrand extends StatelessWidget {
  const _RailBrand({required this.expanded, required this.collapsedWidth});

  final bool expanded;
  final double collapsedWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          SizedBox(
            width: collapsedWidth,
            child: Center(
              child: ShaderMask(
                shaderCallback: (rect) => VesperColors.brandSweep.createShader(rect),
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
          Expanded(
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
    required this.collapsedWidth,
    required this.tv,
    required this.onSelect,
  });

  final AppDestination destination;
  final bool selected;
  final bool expanded;
  final double collapsedWidth;
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
      onShowFocusHighlight: (value) => setState(() => _focused = value),
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
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: _focused ? VesperColors.surfaceRaised : Colors.transparent,
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(10)),
              border: Border(
                left: BorderSide(
                  color: widget.selected ? VesperColors.accent : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: widget.collapsedWidth - 3,
                  child: Icon(
                    widget.selected ? widget.destination.activeIcon : widget.destination.icon,
                    color: widget.selected ? VesperColors.accent : color,
                    size: widget.tv ? 26 : 22,
                  ),
                ),
                Expanded(
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
                      overflow: TextOverflow.clip,
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
