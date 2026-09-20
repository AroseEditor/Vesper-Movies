import 'package:flutter/material.dart';

import '../../design/icons.dart';
import '../../design/widgets/page_scaffold.dart';

class LiveTvPage extends StatelessWidget {
  const LiveTvPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PagePlaceholder(
      title: 'Live TV',
      message: 'Add an M3U playlist to stream live channels.',
      icon: VesperIcons.liveTv,
    );
  }
}
