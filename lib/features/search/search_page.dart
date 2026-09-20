import 'package:flutter/material.dart';

import '../../design/icons.dart';
import '../../design/widgets/page_scaffold.dart';

class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PagePlaceholder(
      title: 'Search',
      message: 'Find any title across your sources.',
      icon: VesperIcons.search,
    );
  }
}
