import 'package:flutter/widgets.dart';

import '../design/icons.dart';

enum AppDestination {
  home('/home', 'Home', VesperIcons.home, VesperIcons.homeOutline),
  categories(
    '/categories',
    'Categories',
    VesperIcons.categories,
    VesperIcons.categoriesOutline,
  ),
  search('/search', 'Search', VesperIcons.search, VesperIcons.search),
  liveTv('/live', 'Live TV', VesperIcons.liveTv, VesperIcons.liveTvOutline),
  downloads(
    '/downloads',
    'Downloads',
    VesperIcons.downloads,
    VesperIcons.downloadsOutline,
  );

  const AppDestination(this.path, this.label, this.activeIcon, this.icon);

  final String path;
  final String label;
  final IconData activeIcon;
  final IconData icon;
}
