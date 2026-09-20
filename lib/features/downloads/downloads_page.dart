import 'package:flutter/material.dart';

import '../../design/icons.dart';
import '../../design/widgets/page_scaffold.dart';

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PagePlaceholder(
      title: 'Downloads',
      message: 'Saved episodes and movies appear here.',
      icon: VesperIcons.downloads,
    );
  }
}
