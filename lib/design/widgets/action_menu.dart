import 'package:flutter/material.dart';

import '../colors.dart';
import '../icons.dart';
import 'choice_dialog.dart';
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
    return FocusableItem(
      onActivate: () async {
        final index = await showChoiceDialog<int>(
          context,
          title: semanticLabel,
          options: [
            for (var i = 0; i < actions.length; i++)
              ChoiceOption(value: i, label: actions[i].label, icon: actions[i].icon),
          ],
        );
        if (index != null) actions[index].onSelected();
      },
      borderRadius: 18,
      scaleOnFocus: false,
      semanticLabel: semanticLabel,
      child:
          child ??
          Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(VesperIcons.more, size: iconSize, color: VesperColors.textSecondary),
          ),
    );
  }
}
