import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shell/input_mode.dart';
import '../colors.dart';
import '../icons.dart';
import '../typography.dart';

class PagePlaceholder extends ConsumerWidget {
  const PagePlaceholder({
    super.key,
    required this.title,
    required this.message,
    this.icon = VesperIcons.empty,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(inputModeProvider);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: mode.gutter),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: VesperColors.textTertiary),
            const SizedBox(height: 16),
            Text(title, style: VesperType.sectionTitle),
            const SizedBox(height: 8),
            Text(message, style: VesperType.body, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
