import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/colors.dart';
import '../../design/icons.dart';
import '../../design/typography.dart';
import '../../design/widgets/action_menu.dart';
import '../../design/widgets/hero_billboard.dart';
import '../../design/widgets/media_row.dart';
import '../../design/widgets/shimmer.dart';
import '../../models/media.dart';
import '../../shell/input_mode.dart';
import '../../storage/library_controller.dart';
import '../../storage/library_store.dart';
import '../categories/categories_page.dart';
import '../details/details_page.dart';
import 'home_controller.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(inputModeProvider);
    final feed = ref.watch(homeFeedProvider);

    return feed.when(
      loading: () => _HomeSkeleton(mode: mode),
      error: (error, stack) =>
          _HomeError(mode: mode, onRetry: () => ref.read(homeFeedProvider.notifier).refresh()),
      data: (data) => _HomeContent(mode: mode, feed: data),
    );
  }
}

class _HomeContent extends ConsumerWidget {
  const _HomeContent({required this.mode, required this.feed});

  final InputMode mode;
  final HomeFeed feed;

  void _open(BuildContext context, CatalogItem item) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (context) => DetailsPage(item: item)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spotlight = feed.spotlight;
    final bottomPad = mode.isTouch ? 108.0 : 40.0;

    final resume = ref.watch(continueWatchingProvider);
    final favourites = ref.watch(favouritesProvider);

    return CustomScrollView(
      slivers: [
        if (spotlight != null)
          SliverToBoxAdapter(
            child: HeroBillboard(
              item: spotlight,
              mode: mode,
              description: feed.spotlightOverview,
              autofocusPlay: mode.isTv,
              onPlay: () => _open(context, spotlight),
              onInfo: () => _open(context, spotlight),
              onToggleList: () => _open(context, spotlight),
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.only(top: mode.rowGap, bottom: bottomPad),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              if (resume.isNotEmpty)
                MediaRow(
                  title: 'Continue Watching',
                  items: [for (final entry in resume) entry.toCatalogItem()],
                  mode: mode,
                  onSelect: (item) => _open(context, item),
                  progressOf: (item) => _progressFor(resume, item),
                  menuOf: (item) => [
                    for (final entry in resume)
                      if (entry.id == item.id.value) ...[
                        MenuAction(
                          icon: VesperIcons.close,
                          label: 'Remove from Continue Watching',
                          onSelected: () => ref.read(libraryProvider.notifier).forget(entry),
                        ),
                        MenuAction(
                          icon: VesperIcons.watched,
                          label: 'Mark as watched',
                          onSelected: () => ref
                              .read(libraryProvider.notifier)
                              .setWatched(
                                item,
                                watched: true,
                                season: entry.season,
                                episode: entry.episode,
                              ),
                        ),
                      ],
                  ],
                ),
              if (favourites.isNotEmpty)
                MediaRow(
                  title: 'My List',
                  items: favourites,
                  mode: mode,
                  onSelect: (item) => _open(context, item),
                ),
              if (ref.read(metadataServiceProvider).hasTmdb)
                for (var i = 0; i < indianRows().length; i++)
                  _IndianRow(index: i, mode: mode, onSelect: (item) => _open(context, item)),
              for (final shelf in feed.shelves)
                MediaRow(
                  title: shelf.title,
                  items: shelf.items,
                  mode: mode,
                  onSelect: (item) => _open(context, item),
                ),
              for (final row in homeGenreRows)
                _GenreRow(
                  title: row.$1,
                  query: BrowseQuery(type: row.$2, genre: row.$3),
                  mode: mode,
                  onSelect: (item) => _open(context, item),
                ),
            ]),
          ),
        ),
      ],
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton({required this.mode});

  final InputMode mode;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: height * (mode.isTouch ? 0.62 : 0.68),
            child: const Stack(
              fit: StackFit.expand,
              children: [
                Shimmer(width: double.infinity, height: double.infinity, borderRadius: 0),
                Center(child: LoadingNote(label: 'Loading your feed')),
              ],
            ),
          ),
          SizedBox(height: mode.rowGap),
          for (var i = 0; i < 2; i++)
            MediaRow(title: ' ', items: const [], mode: mode, loading: true),
        ],
      ),
    );
  }
}

class _HomeError extends StatelessWidget {
  const _HomeError({required this.mode, required this.onRetry});

  final InputMode mode;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: mode.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(VesperIcons.warning, size: 42, color: VesperColors.textTertiary),
            const SizedBox(height: 14),
            const Text('Nothing loaded', style: VesperType.sectionTitle),
            const SizedBox(height: 6),
            const Text(
              'Check your connection and try again.',
              style: VesperType.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            HeroButton(label: 'Retry', icon: VesperIcons.refresh, onTap: onRetry, filled: true),
          ],
        ),
      ),
    );
  }
}

double? _progressFor(List<WatchEntry> entries, CatalogItem item) {
  for (final entry in entries) {
    if (entry.id == item.id.value) return entry.progress;
  }
  return null;
}

const homeGenreRows = <(String, String, String)>[
  ('Action Movies', 'movie', 'Action'),
  ('Comedy Movies', 'movie', 'Comedy'),
  ('Crime Series', 'series', 'Crime'),
  ('Thrillers', 'movie', 'Thriller'),
  ('Sci-Fi and Fantasy', 'movie', 'Sci-Fi'),
  ('Drama Series', 'series', 'Drama'),
  ('Horror', 'movie', 'Horror'),
  ('Romance', 'movie', 'Romance'),
  ('Animation', 'movie', 'Animation'),
  ('Documentaries', 'movie', 'Documentary'),
];

class _GenreRow extends ConsumerWidget {
  const _GenreRow({
    required this.title,
    required this.query,
    required this.mode,
    required this.onSelect,
  });

  final String title;
  final BrowseQuery query;
  final InputMode mode;
  final void Function(CatalogItem item) onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(browseProvider(query));
    return items.when(
      loading: () => MediaRow(title: title, items: const [], mode: mode, loading: true),
      error: (error, stack) => const SizedBox.shrink(),
      data: (list) => list.isEmpty
          ? const SizedBox.shrink()
          : MediaRow(title: title, items: list, mode: mode, onSelect: onSelect),
    );
  }
}

class _IndianRow extends ConsumerWidget {
  const _IndianRow({required this.index, required this.mode, required this.onSelect});

  final int index;
  final InputMode mode;
  final void Function(CatalogItem item) onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = indianRows()[index].title;
    return ref
        .watch(indianRowProvider(index))
        .when(
          loading: () => MediaRow(title: title, items: const [], mode: mode, loading: true),
          error: (error, stack) => const SizedBox.shrink(),
          data: (items) => items.isEmpty
              ? const SizedBox.shrink()
              : MediaRow(title: title, items: items, mode: mode, onSelect: onSelect),
        );
  }
}
