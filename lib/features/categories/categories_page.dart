import 'package:flutter/material.dart';

import '../../design/icons.dart';
import '../../design/widgets/page_scaffold.dart';

class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PagePlaceholder(
      title: 'Categories',
      message: 'Browse every genre and type.',
      icon: VesperIcons.categories,
    );
  }
}
