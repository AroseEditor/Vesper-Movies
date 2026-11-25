import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../design/colors.dart';
import '../design/motion.dart';
import '../design/typography.dart';
import '../design/widgets/glass_surface.dart';
import 'destinations.dart';

class BottomDock extends StatelessWidget {
  const BottomDock({super.key, required this.currentIndex, required this.onSelect});

  final int currentIndex;
  final ValueChanged<int> onSelect;

  static const double _dockHeight = 64;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final itemCount = AppDestination.values.length;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 10 + bottomInset * 0.4),
      child: GlassSurface(
        raised: true,
        shape: const LiquidRoundedSuperellipse(borderRadius: 22),
        child: SizedBox(
          height: _dockHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final itemWidth = constraints.maxWidth / itemCount;
                return Stack(
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 500),
                      curve: VesperMotion.overshoot,
                      left: currentIndex * itemWidth + 4,
                      top: 6,
                      width: itemWidth - 8,
                      height: constraints.maxHeight - 12,
                      child: GlassSurface(
                        settings: VesperGlass.pill,
                        shape: LiquidRoundedSuperellipse(
                          borderRadius: (constraints.maxHeight - 12) / 2,
                        ),
                        showRim: false,
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (var i = 0; i < itemCount; i++)
                          Expanded(
                            child: _DockItem(
                              destination: AppDestination.values[i],
                              selected: i == currentIndex,
                              onTap: () => onSelect(i),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({required this.destination, required this.selected, required this.onTap});

  final AppDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? VesperColors.textPrimary : VesperColors.textTertiary;

    return Semantics(
      label: destination.label,
      selected: selected,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: selected ? 1.08 : 1.0,
              duration: VesperMotion.fast,
              curve: VesperMotion.overshoot,
              child: Icon(
                selected ? destination.activeIcon : destination.icon,
                color: color,
                size: 22,
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: VesperMotion.fast,
              style: VesperType.label.copyWith(
                fontSize: 10,
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
              child: Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
