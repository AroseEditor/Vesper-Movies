import 'package:flutter/material.dart';

import '../colors.dart';
import '../icons.dart';
import '../typography.dart';

class ChoiceOption<T> {
  const ChoiceOption({
    required this.value,
    required this.label,
    this.icon,
    this.trailing,
    this.selected = false,
  });

  final T value;
  final String label;
  final IconData? icon;
  final String? trailing;
  final bool selected;
}

Future<T?> showChoiceDialog<T>(
  BuildContext context, {
  required String title,
  required List<ChoiceOption<T>> options,
}) {
  return showDialog<T>(
    context: context,
    builder: (dialogContext) {
      var focusIndex = options.indexWhere((option) => option.selected);
      if (focusIndex < 0) focusIndex = 0;
      return Dialog(
        backgroundColor: VesperColors.surfaceRaised,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440, maxHeight: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Text(title, style: VesperType.sectionTitle),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    for (var i = 0; i < options.length; i++)
                      ListTile(
                        autofocus: i == focusIndex,
                        focusColor: VesperColors.surfaceHover,
                        hoverColor: VesperColors.surfaceHover,
                        onTap: () => Navigator.of(dialogContext).pop(options[i].value),
                        leading: SizedBox(
                          width: 24,
                          child: options[i].selected
                              ? const Icon(VesperIcons.check, size: 20, color: VesperColors.accent)
                              : options[i].icon == null
                              ? null
                              : Icon(options[i].icon, size: 20, color: VesperColors.textSecondary),
                        ),
                        title: Text(options[i].label, style: VesperType.label),
                        trailing: options[i].trailing == null
                            ? null
                            : Text(options[i].trailing!, style: VesperType.meta),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
