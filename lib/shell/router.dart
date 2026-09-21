import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/categories/categories_page.dart';
import '../features/downloads/downloads_page.dart';
import '../features/home/home_page.dart';
import '../features/live_tv/live_tv_page.dart';
import '../features/search/search_page.dart';
import '../features/splash/splash_page.dart';
import 'app_shell.dart';
import 'destinations.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

GoRouter buildRouter() {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    routes: [
      GoRoute(
        path: '/splash',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => NoTransitionPage(
          child: SplashPage(onComplete: () => context.go(AppDestination.home.path)),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppDestination.home.path,
                pageBuilder: (context, state) => const NoTransitionPage(child: HomePage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppDestination.categories.path,
                pageBuilder: (context, state) => const NoTransitionPage(child: CategoriesPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppDestination.search.path,
                pageBuilder: (context, state) => const NoTransitionPage(child: SearchPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppDestination.liveTv.path,
                pageBuilder: (context, state) => const NoTransitionPage(child: LiveTvPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppDestination.downloads.path,
                pageBuilder: (context, state) => const NoTransitionPage(child: DownloadsPage()),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
