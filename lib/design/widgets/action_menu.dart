import 'package:flutter/material.dart';

import '../colors.dart';
import '../icons.dart';
import '../typography.dart';
import 'focusable_item.dart';

class MenuAction {
  const MenuAction({required this.icon, required this.label, required this.onSelected});

  final IconData icon;
  final String label;
  final VoidCallback onSelected;
}

class ActionMenu extends StatelessWidget {
  const ActionMenu({
    super.key,
    required this.actions,
    this.semanticLabel = 'More options',
    this.iconSize = 22,
    this.child,
  });

  final List<MenuAction> actions;
  final String semanticLabel;
  final double iconSize;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(VesperColors.surfaceRaised),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      menuChildren: [
        for (final action in actions)
          MenuItemButton(
            onPressed: action.onSelected,
            leadingIcon: Icon(action.icon, size: 19, color: VesperColors.textSecondary),
            child: Padding(
              padding: const EdgeInsets.only(right: 18),
              child: Text(action.label, style: VesperType.label),
            ),
          ),
      ],
      builder: (context, controller, _) => FocusableItem(
        onActivate: () => controller.isOpen ? controller.close() : controller.open(),
        borderRadius: 18,
        scaleOnFocus: false,
        semanticLabel: semanticLabel,
        child:
            child ??
            Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(VesperIcons.more, size: iconSize, color: VesperColors.textSecondary),
            ),
      ),
    );
  }
}
