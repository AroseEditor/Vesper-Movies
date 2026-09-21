import 'package:flutter/material.dart';

import '../design/colors.dart';
import '../design/motion.dart';
import '../design/typography.dart';
import 'destinations.dart';

class BottomDock extends StatelessWidget {
  const BottomDock({super.key, required this.currentIndex, required this.onSelect});

  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 10 + bottomInset * 0.4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: VesperColors.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: VesperColors.divider),
          boxShadow: const [
            BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 8)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < AppDestination.values.length; i++)
                Expanded(
                  child: _DockItem(
                    destination: AppDestination.values[i],
                    selected: i == currentIndex,
                    onTap: () => onSelect(i),
                  ),
                ),
            ],
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
    final color = selected ? VesperColors.accent : VesperColors.textTertiary;

    return Semantics(
      label: destination.label,
      selected: selected,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: VesperMotion.fast,
              curve: VesperMotion.enter,
              height: 3,
              width: selected ? 22 : 0,
              decoration: BoxDecoration(
                color: VesperColors.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 7),
            AnimatedScale(
              scale: selected ? 1.08 : 1.0,
              duration: VesperMotion.fast,
              curve: VesperMotion.overshoot,
              child: Icon(
                selected ? destination.activeIcon : destination.icon,
                color: color,
                size: 23,
              ),
            ),
            const SizedBox(height: 4),
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
